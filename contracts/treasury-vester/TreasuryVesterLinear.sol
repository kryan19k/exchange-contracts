// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IMiniChefV2 {
    function fundRewards(uint256 newFunding, uint256 duration) external;
}

interface IPng is IERC20 {
    function mint(address dst, uint rawAmount) external;
}

/**
 * @notice A contract that vests & distributes tokens.
 * It only distributes a single token with a `mint` function.
 */
contract TreasuryVesterLinear is Ownable {
    using SafeERC20 for IPng;

    struct Recipient{
        address account;
        uint allocation;
        bool isMiniChef;
    }

    /// @notice The list of recipients who have an allocation
    Recipient[] public recipients;

    /// @notice The multisig who can initialize the vesting
    address public guardian;

    /// @notice The token to be vested/minted
    IPng public immutable vestedToken;

    /// @notice Whether the vesting is enabled or not
    bool public vestingEnabled;

    /// @notice The time stamp of the last vesting
    uint public lastUpdate;

    /// @notice The amount of tokens distributed on each vesting
    uint public immutable dailyVestingAmount;

    /// @notice The denominator for both the allocations and the vesting percentages
    uint private constant DENOMINATOR = 10000;

    /// @notice The minimum duration between two vestings (i.e.: 1 day)
    uint private constant VESTING_CLIFF = 86400;

    /**
     * @notice Construct a new TreasuryVester contract
     * @param newVestedToken The token that is being vested & distributed
     * @param newRecipients Recipients with an allocation
     * @param newGuardian An authorized address that can initialize the vesting
     * @param newDailyVestingAmount The total number of tokens to be distributed
     */
    constructor(
        address newVestedToken,
        Recipient[] memory newRecipients,
        address newGuardian,
        uint newDailyVestingAmount
    ) {
        require(newDailyVestingAmount > DENOMINATOR, "TreasuryVester::Constructor: low vesting amount");
        require(newGuardian != address(0), "TreasuryVester::Constructor: invalid guardian address");
        require(newVestedToken.code.length > 0, "TreasuryVester::Constructor: invalid token address");
        guardian = newGuardian;
        vestedToken = IPng(newVestedToken);
        dailyVestingAmount = newDailyVestingAmount;
        setRecipients(newRecipients);
    }

    /**
     * @notice Distributes the tokens to recipients based on their allocation
     * @dev If the vesting is enabled, anyone can call this function with 1 day intervals
     */
    function distribute() external {
        require(vestingEnabled, "TreasuryVester::distribute: vesting is not enabled");
        require(
            block.timestamp >= lastUpdate + VESTING_CLIFF,
            "TreasuryVester::distribute: it is too early to distribute"
        );
        lastUpdate = block.timestamp;

        // distributes vestingAmount of tokens to recipients based on their allocation
        uint length = recipients.length;
        for (uint i; i < length; ++i) {
            Recipient memory recipient = recipients[i];
            uint amount = recipient.allocation * dailyVestingAmount / DENOMINATOR;
            if (recipient.isMiniChef) {
                // calls fund rewards of minichef after minting tokens to self
                vestedToken.mint(address(this), amount);
                vestedToken.approve(recipient.account, amount);
                IMiniChefV2(recipient.account).fundRewards(amount, VESTING_CLIFF);
            } else {
                // simply mints or transfer tokens to regular recipients
                vestedToken.mint(recipient.account, amount);
            }
        }
        emit TokensVested();
    }

    /**
     * @notice Adds new recipients by overriding old recipients
     * @dev Only callable by the owner (i.e.: governance)
     * @param newRecipients An array of new recipients with allocation
     */
    function setRecipients(Recipient[] memory newRecipients) public onlyOwner {
        delete recipients;
        uint length = newRecipients.length;
        require(
            length != 0 && length < 41,
            "TreasuryVester::setRecipients: invalid recipient number"
        );
        uint allocations;
        for (uint i; i < length; ++i) {
            Recipient memory recipient = newRecipients[i];
            require(
                recipient.account != address(0),
                "TreasuryVester::setRecipients: invalid recipient address"
            );
            require(
                recipient.allocation != 0,
                "TreasuryVester::setRecipients: invalid recipient allocation"
            );
            recipients.push(recipient);
            allocations += recipient.allocation;
        }
        require(
            allocations == DENOMINATOR,
            "TreasuryVester::setRecipients: invalid total allocation"
        );
        emit RecipientsChanged(newRecipients);
    }

    /**
     * @notice Enables distribution of the tokens
     * @dev Callable by either the owner (i.e.: governance) or guardian
     */
    function startVesting() external {
        require(
            msg.sender == guardian || msg.sender == owner(),
            "TreasuryVester::startVesting: unauthorized message sender"
        );
        require(
            !vestingEnabled,
            "TreasuryVester::startVesting: vesting is already enabled"
        );
        vestingEnabled = true;
        emit VestingEnabled();
    }

    /// @notice An event that is emitted when vesting is enabled
    event VestingEnabled();

    /// @notice An event that is emitted when tokens are distributed
    event TokensVested();

    /// @notice An event that is emitted when recipients are changed
    event RecipientsChanged(Recipient[] newRecipients);
}
