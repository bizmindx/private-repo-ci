// SPDX-License-Identifier: Unlicense

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IFairSideDAO.sol";
import "../interfaces/IFSDVesting.sol";
import "../interfaces/IFSDVestingFactory.sol";
import "../interfaces/IERC20ConvictionScore.sol";
import "../dependencies/DSMath.sol";
import "../dependencies/FSOwnable.sol";
import "../dependencies/SafeUint224.sol";

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

/**
 * FSD Vesting
 *
 * Attributes:
 * - FSD token vesting over a period of time with a cliff
 * - Allow users to vote with vested tokens
 * - Vesting duration of 30 months with a 12-month cliff
 * - 5% unlocked after the cliff period
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract FSDVestingKOL is IFSDVesting {
    /* ========== LIBRARIES ========== */

    using DSMath for uint256;
    using SafeERC20 for IERC20ConvictionScore;

    /* ========== STATE VARIABLES ========== */

    // One month in seconds
    uint256 private constant ONE_MONTH = 30 days;
    // Duration of a vest
    uint256 private constant DURATION = 12 * ONE_MONTH;

    // Amount of FSD that are vested
    uint256 public amount;
    // Amount of FSD claimed from the vesting contract
    uint256 public totalClaimed;
    // Vesting start timestamp in seconds
    uint256 public start;
    // Latest claim timestamp in seconds
    uint256 public lastClaimAt;

    // Beneficiary address of the FSD vesting
    address public beneficiary;
    // FairSide Conviction Token address
    IERC20ConvictionScore public immutable fsd;
    // Address of the FSD vesting
    IFSDVestingFactory public immutable factory;
    // Address of the FSD minter
    address public immutable minter;
    // FairSide DAO address
    IFairSideDAO public immutable dao;
    // The FairSideConviction ERC-721 token address
    IERC721 public immutable fairSideConviction;

    /* ========== EVENTS ========== */
    event TokensClaimed(
        address indexed beneficiary,
        uint256 amount,
        uint256 claimedAt
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IERC20ConvictionScore _token,
        IFSDVestingFactory _factory,
        address _minter,
        IFairSideDAO _dao,
        IERC721 _fairSideConviction
    ) public {
        fsd = _token;
        factory = _factory;
        minter = _minter;
        dao = _dao;
        fairSideConviction = _fairSideConviction;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Calculate the unclaimed token amount.
     * @return the unclaimed token amount
     */
    function unclaimedTokens() external view returns (uint256) {
        return amount - totalClaimed;
    }

    /**
     * @dev Calculate the vested tokens available to claim.
     * @return vestedAmount the vested tokens available to claim
     */
    function calculateVestingClaim() public view returns (uint256) {
        if (block.timestamp < start.add(DURATION)) {
            return 0;
        }

        return amount.sub(totalClaimed);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows a vesting beneficiary to claim the vested tokens.
     */
    function claimVestedTokens() external override onlyBeneficiary {
        uint256 tokenClaim = calculateVestingClaim();
        require(
            tokenClaim > 0,
            "FSDVesting::claimVestedTokens: Zero claimable tokens"
        );

        totalClaimed = totalClaimed.add(tokenClaim);
        lastClaimAt = block.timestamp;

        fsd.safeTransfer(msg.sender, tokenClaim);

        emit TokensClaimed(msg.sender, tokenClaim, block.timestamp);

        if (amount == totalClaimed) {
            uint256 tokenId = fsd.tokenizeConviction(0);
            fairSideConviction.transferFrom(address(this), msg.sender, tokenId);
        }
    }

    /**
     * @dev Allows a vesting beneficiary to extend their vested token amount.
     * @param _amount Number of tokens to increment the vested amount
     */
    function updateVestedTokens(uint256 _amount) external override {
        require(
            msg.sender == minter,
            "FSDVesting::updateVestedTokens: Caller is not the FSD contract"
        );

        amount = amount.add(_amount);
    }

    /**
     * @dev Add a new proposal for the DAO to vote on.
     * @param targets The ordered list of target addresses for calls to be made
     * @param values The ordered list of values (i.e. msg.value) to be passed to the calls to be made
     * @param signatures The ordered list of function signatures to be called
     * @param calldatas The ordered list of calldata to be passed to each call
     * @param description The proposal description
     * @param forceOnchain A bool indicating whether offchain or onchain voting processes should be used
     * @return The newly created proposal's unique id
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        bool forceOnchain
    ) public onlyBeneficiary returns (uint256) {
        return
            dao.propose(
                targets,
                values,
                signatures,
                calldatas,
                description,
                forceOnchain
            );
    }

    /**
     * @dev Vote for a specific proposal.
     * @param proposalId The proposal's unique id
     * @param support Whether or not the voter supports the proposal
     */
    function castVote(uint256 proposalId, bool support)
        external
        onlyBeneficiary
    {
        dao.castVote(proposalId, support);
    }

    /**
     * @dev Allows claiming of availabe tributes by `msg.sender`
     * during their vesting period. It updates the claimed status
     * of the vest against the tribute being claimed.
     *
     * Requirements:
     * - claiming amount must not be 0.
     */
    function claimAvailableTributes(uint256 num) external onlyBeneficiary {
        uint256 tribute = fsd.availableTribute(num).add(
            fsd.availableGovernanceTribute(num)
        );

        require(
            tribute != 0,
            "FSDVesting::claimAvailableTributes: No tribute to claim"
        );

        fsd.claimAvailableTributes(num);
        fsd.safeTransfer(msg.sender, tribute);
    }

    /**
     * @dev Initiates a new vesting schedule for `_beneficiary`.
     * @param _beneficiary Address of the token recipient entitled to claim the vested funds
     * @param _amount Total number of tokens to-be-vested
     */
    function initiateVesting(address _beneficiary, uint256 _amount)
        external
        onlyFactory
    {
        beneficiary = _beneficiary;
        start = block.timestamp;
        amount = _amount;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */

    /**
     * @dev Throws if called by any account other than the vesting factory contract.
     */
    modifier onlyFactory() {
        require(
            msg.sender == address(factory),
            "FSDVesting:: Caller is not the vesting factory contract"
        );
        _;
    }

    /**
     * @dev Throws if called by any account other than the vesting beneficiary.
     */
    modifier onlyBeneficiary() {
        require(
            msg.sender == beneficiary,
            "Vesting:: Caller is not the vesting beneficiary"
        );
        _;
    }

    // /**
    //  * @dev Allows claiming of staking tribute by `msg.sender` during their vesting period.
    //  * It updates the claimed status of the vest against the tribute
    //  * being claimed.
    //  *
    //  * Requirements:
    //  * - claiming amount must not be 0.
    //  */
    // function claimTribute(uint256 num) external onlyBeneficiary {
    //     uint256 tribute = fsd.availableTribute(num);

    //     require(tribute != 0, "FSDVesting::claimTribute: No tribute to claim");

    //     fsd.claimTribute(num);
    //     fsd.safeTransfer(msg.sender, tribute);
    // }

    // /**
    //  * @dev Allows claiming of governance tribute by `msg.sender` during their vesting period.
    //  * It updates the claimed status of the vest against the tribute
    //  * being claimed.
    //  *
    //  * Requirements:
    //  * - claiming amount must not be 0.
    //  */
    // function claimGovernanceTribute(uint256 num) external onlyBeneficiary {
    //     uint256 tribute = fsd.availableGovernanceTribute(num);

    //     require(
    //         tribute != 0,
    //         "FSDVesting::claimGovernanceTribute: No governance tribute to claim"
    //     );

    //     fsd.claimGovernanceTribute(num);
    //     fsd.safeTransfer(msg.sender, tribute);
    // }
}
