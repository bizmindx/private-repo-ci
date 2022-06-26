// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/drafts/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

import "../interfaces/chainlink/AggregatorV3Interface.sol";
import "../dependencies/FairSideFormula.sol";
import "../dependencies/DSMath.sol";
import "../token/FSD.sol";

// import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
// import '../dependencies/UniswapV2OracleLibrary.sol';

/**
 * @dev Implementation of {FSDNetwork}.
 *
 * The FSDNetwork contract allows purchasing of network membership using
 * FSD tokens. The FSD tokens collected in fees are distribute among the contract,
 * staking tribute, governance tribute and funding pool in specific percentages.
 *
 * Allows opening, updating and processing of Cross Share Requests.
 *
 * Attributes:
 * - Supports the full workflow of a cost share request
 * - Handles FSD membership
 * - Handles governance rewards
 * - Retrieves ETH price via Chainlink
 * - Calculates FSD price via Uniswap using Time-Weighted Price Averages (TWAP)
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract FSDNetwork is EIP712 {
    /* ========== LIBRARIES ========== */

    using SafeERC20 for FSD;
    using Address for address payable;
    using DSMath for uint256;
    using FixedPoint for FixedPoint.uq112x112;

    /* ========== STATE VARIABLES ========== */

    /**
     * @dev Actions to perform on Cost Share Request (CSR).
     * Expire: Action for expiring of CSR when at least 7 days have passes since
     *         CSR creation and voting has not opened.
     * SubmitEvidence: Action for submitting of evidence against CSR.
     * ApproveClaim: Action for acceptance of CSR.
     * DenyClaim: Action for rejection of CSR.
     * ExtendClaim: Action for opening voting against CSR.
     */
    enum Action {
        Expire,
        SubmitEvidence,
        ApproveClaim,
        DenyClaim,
        ExtendClaim
    }

    /**
     * @dev {Membership} struct contains parameters representing a user's
     * membership in FSD Network.
     * availableCostShareBenefits: Amount of cross share benefits purchased by a member.
     * openCostShareBenefits: Amount of cross share benefits opened by a member.
     * creation: Timestamp at which the membership is purchased by a user.
     * gracePeriod: Timestamp at which the membership of a user ends.
     */
    struct Membership {
        uint256 availableCostShareBenefits;
        uint256 openCostShareBenefits;
        uint256 creation;
        uint256 gracePeriod;
        address[2] wallets;
    }

    /**
     * @dev {CostShareRequest} struct contains parameters representing a Cross Share Request (CSR).
     * initiator: Creator of CSR.
     * ethAmount: Payout of CSR in ETH.
     * fsdBounty: Bounty associated with CSR (0.4 % of the member's available cross share benefits).
     * creation: Timestamp at which the CSR is created.
     * votingOpen: Timestamp at which the voting is opened.
     * evidence: Evidence associated with CSR.
     * stableAmount: Payout of CSR in Stablecoin (DAI).
     */
    struct CostShareRequest {
        address initiator;
        uint256 ethAmount;
        uint256 fsdBounty;
        uint128 creation;
        uint128 votingOpen;
        bytes32 evidence;
        uint256 stableAmount;
        uint256 csrType;
    }

    // Membership data
    mapping(address => Membership) public membership;
    // Cost Share Requests
    mapping(uint256 => CostShareRequest) public costShareRequests;
    // Network assessor members
    address[3] public assessors;
    // Cost Share Request IDs
    uint256 private nextCSRID;
    // Cost share benefits of the entire network in ETH
    uint256 public totalCostShareBenefits;
    // Open cost share requests in ETH
    uint256 public totalOpenRequests;
    // Slippage Tolerance for stable payouts, starts at 5%
    uint256 public slippageTolerance = 5;
    // 4% membership fee
    uint256 public membershipFee = 0.04 ether;
    // Data entry proposed by the DAO
    mapping(uint256 => bool) public approvedCsrTypes;

    // Submit CSR Action
    bytes32 private constant CSR_ACTION =
        keccak256("Action(uint256 id, uint8 action)");
    // FSD Token Address
    FSD private immutable fsd;
    // Funding Pool Address
    address private immutable FUNDING_POOL;
    // Premiums Pool Address
    address private immutable PREMIUMS_POOL;
    // Governance Address
    address private immutable GOVERNANCE_ADDRESS;
    // Timelock Address, owned by Governance
    address private immutable TIMELOCK;

    // 20% as staking rewards
    uint256 private constant STAKING_REWARDS = 0.20 ether;
    // 7.5% as governance rewards and funding pool
    uint256 private constant GOVERNANCE_FUNDING_POOL_REWARDS = 0.075 ether;
    // 90% as 10% is unshareable cost request which is personal responsibility of user
    uint256 private constant NON_USA = 0.9 ether;
    // FSD TWAP Window
    uint256 public constant PERIOD = 1 hours;
    // Duration of membership (MEMBERSHIP_DURATION)
    uint256 public constant MEMBERSHIP_DURATION = 730 days;
    // Chainlink Oracle (Ether)
    AggregatorV3Interface private constant ETH_CHAINLINK =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    /* ========== EVENTS ========== */

    // An event emitted when a membership is purchased (either new or an extension)
    event NewMembership(address member, uint256 benefits, uint256 fee);

    // An event emitted when a CSR is submitted
    event CreateCSR(
        uint256 id,
        address beneficiary,
        uint256 payoutAmount,
        bool inStable,
        uint256 csrType,
        uint256 timestamp
    );

    // An event emitted when a CSR expires
    event ExpireCSR(uint256 id, address beneficiary, uint256 timestamp);

    // An event emitted when evidence for a CSR is submitted
    event SubmitEvidenceCSR(
        uint256 id,
        address assessor,
        bytes32 evidence,
        uint256 timestamp
    );

    // An event emitted when a CSR is accepted
    event AcceptCSR(
        uint256 id,
        address assessor,
        address beneficiary,
        uint256 payoutAmount,
        uint256 timestamp
    );

    // An event emitted when a CSR is rejected
    event RejectCSR(uint256 id, address assessor, address beneficiary, uint256 timestamp);

    // An event emitted when a CSR is extended.
    event ExtendCSR(uint256 id, address assessor, uint256 timestamp);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initialises the contract's state setting fsd, FUNDING_POOL, GOVERNANCE_ADDRESS
     * and TIMELOCK addresses.
     */
    constructor(
        FSD _fsd,
        address fundingPool,
        address premiumsPool,
        address governance,
        address timelock
    ) public EIP712("FSDNetwork", "v1.0.0") {
        fsd = _fsd;
        FUNDING_POOL = fundingPool;
        PREMIUMS_POOL = premiumsPool;
        GOVERNANCE_ADDRESS = governance;
        TIMELOCK = timelock;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the total open CSRs and total cost share benefits.
     */
    function getAdoptionStats() external view returns (uint256, uint256) {
        return (totalOpenRequests, totalCostShareBenefits);
    }

    /**
     * @dev Token price evaluated as spot price directly on curve
     */
    function getFSDPrice() public view returns (uint256) {
        // FSHARE = Total Available Cost Share Benefits / Gearing Factor
        uint256 fShare = totalCostShareBenefits.mul(100) / fsd.gearingFactor();
        // Floor of 4000 ETH
        if (fShare < 4000 ether) fShare = 4000 ether;

        // Capital Pool = Total Funds held in ETH – Open Cost Share Requests
        // Open Cost Share Request = Cost share request awaiting assessor consensus
        uint256 capitalPool = fsd.getReserveBalance() - totalOpenRequests;

        return FairSideFormula.f(capitalPool, fShare);
    }

    /**
     * @dev Returns the ETH price in DAI using chainlink
     */
    function getEtherPrice() public view returns (uint256) {
        (
            uint80 roundID,
            int256 price,
            ,
            ,
            uint80 answeredInRound
        ) = ETH_CHAINLINK.latestRoundData();
        require(
            answeredInRound >= roundID,
            "FSDNetwork::getEtherPrice: Chainlink Price Stale"
        );
        require(price != 0, "FSDNetwork::getEtherPrice: Chainlink Malfunction");
        // Chainlink returns 8 decimal places so we convert
        return uint256(price).mul(10**10);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows purchasing of membership of FSD Network with ETH.
     *
     * It accepts ETH to allocate the available cross share benefits
     * for a member and also determines membership purchase cost.
     *
     * The membership is purchased using ETH, 65% of which remains in the contract,
     * 20% is allocated with staking rewards, 7.5% is allocated for the {PREMIUMS_POOL}
     * and 7.5% is sent to {FUNDING_POOL}.
     *
     * Requirements:
     * - the {msg.value} must be greater than 0 and divisible by 1 ether
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     * - total cost share benefits must not exceed maximum allowed per user (100 ether)
     * - {fShareRatio} must remain equal or above than 100%
     */
    function purchaseMembershipETH() external payable {
        uint256 costShareBenefit = msg.value;
        require(
            costShareBenefit % 1 ether == 0 && costShareBenefit > 0,
            "FSDNetwork::purchaseMembershipETH: Invalid cost share benefit specified"
        );

        Membership storage user = membership[msg.sender];

        if (user.gracePeriod < block.timestamp) {
            user.creation = 0;
            user.availableCostShareBenefits = 0;
        }

        uint256 totalCostShareBenefit = user.availableCostShareBenefits.add(
            costShareBenefit
        );
        require(
            totalCostShareBenefit <= _getMaximumBenefitPerUser(),
            "FSDNetwork::purchaseMembershipETH: Exceeds cost share benefit limit per account"
        );

        totalCostShareBenefits = totalCostShareBenefits.add(costShareBenefit);

        // FSHARE = Total Available Cost Share Benefits / Gearing Factor
        uint256 fShare = totalCostShareBenefits.mul(100) / fsd.gearingFactor();
        // Floor of 4000 ETH
        if (fShare < 4000 ether) fShare = 4000 ether;

        // FSHARERatio = Capital Pool / FSHARE (scaled by 1e18)
        uint256 fShareRatio = (fsd.getReserveBalance() - totalOpenRequests).mul(
            1 ether
        ) / fShare;

        // 1 ether = 100%
        require(
            fShareRatio >= 1 ether,
            "FSDNetwork::purchaseMembershipETH: Insufficient Capital to Cover Membership"
        );

        uint256 membershipFees = costShareBenefit.wmul(membershipFee);
        uint256 fsdFee = membershipFees.wdiv(getFSDPrice());

        // Automatically locks 65% to the Network by disallowing its retrieval
        fsd.mint{value: membershipFees.wmul(0.65 ether)}(
            address(this),
            fsdFee.wmul(0.6 ether) // 5% slippage tolerance
        );

        if (user.creation == 0) {
            user.creation = block.timestamp;
            user.gracePeriod =
                membership[msg.sender].creation +
                MEMBERSHIP_DURATION +
                60 days;
        } else {
            if (
                ((block.timestamp - user.creation) * 1 ether) /
                    MEMBERSHIP_DURATION <
                1 ether
            ) {
                uint256 durationIncrease = (costShareBenefit.mul(1 ether) /
                    (totalCostShareBenefit - costShareBenefit)).mul(
                        MEMBERSHIP_DURATION
                    ) / 1 ether;
                user.gracePeriod += durationIncrease;
            }
        }
        user.availableCostShareBenefits = totalCostShareBenefit;

        emit NewMembership(msg.sender, costShareBenefit, membershipFees);

        uint256 fundingFee = costShareBenefit.wmul(
            GOVERNANCE_FUNDING_POOL_REWARDS
        );

        // up to 7.5% towards funding pool if not capped
        if (FUNDING_POOL.balance < 500 ether) {
            if (fundingFee > 500 ether - FUNDING_POOL.balance) {
                fundingFee = 500 ether - FUNDING_POOL.balance;
            }
            payable(FUNDING_POOL).sendValue(fundingFee);
        }
        // 7.5% towards premiums pool
        payable(PREMIUMS_POOL).sendValue(costShareBenefit.sub(fundingFee));
    }

    /**
     * @dev Allows purchasing of membership of FSD Network.
     *
     * It accepts {costShareBenefit} parameter to allocate the available cross share benefits
     * for a member and also determines membership purchase cost.
     *
     * The membership is purchased using FSD tokens, 65% of which remains in the contract,
     * 20% is allocated with staking rewards, 7.5% is allocated for governance rewards and
     * 7.5% is sent to {FUNDING_POOL}.
     *
     * Requirements:
     * - parameter {costShareBenefit} must be greater than 0 and divisible by 1 ether
     * - total cost share benefits must not exceed maximum allowed per user (100 ether)
     * - {fShareRatio} must remain equal or above than 100%
     */
    function purchaseMembership(uint256 costShareBenefit) external {
        require(
            costShareBenefit % 1 ether == 0 && costShareBenefit > 0,
            "FSDNetwork::purchaseMembership: Invalid cost share benefit specified"
        );

        Membership storage user = membership[msg.sender];

        if (user.gracePeriod < block.timestamp) {
            user.creation = 0;
            user.availableCostShareBenefits = 0;
        }

        uint256 totalCostShareBenefit = user.availableCostShareBenefits.add(
            costShareBenefit
        );
        require(
            totalCostShareBenefit <= _getMaximumBenefitPerUser(),
            "FSDNetwork::purchaseMembership: Exceeds cost share benefit limit per account"
        );

        totalCostShareBenefits = totalCostShareBenefits.add(costShareBenefit);

        // FSHARE = Total Available Cost Share Benefits / Gearing Factor
        uint256 fShare = totalCostShareBenefits.mul(100) / fsd.gearingFactor();
        // Floor of 4000 ETH
        if (fShare < 4000 ether) fShare = 4000 ether;

        // FSHARERatio = Capital Pool / FSHARE (scaled by 1e18)
        uint256 fShareRatio = (fsd.getReserveBalance() - totalOpenRequests).mul(
            1 ether
        ) / fShare;

        // 1 ether = 100%
        require(
            fShareRatio >= 1 ether,
            "FSDNetwork::purchaseMembership: Insufficient Capital to Cover Membership"
        );

        uint256 membershipFees = costShareBenefit.wmul(membershipFee);
        uint256 fsdSpotPrice = getFSDPrice();
        uint256 fsdFee = membershipFees.wdiv(fsdSpotPrice);

        // Automatically locks 65% to the Network by disallowing its retrieval
        fsd.safeTransferFrom(msg.sender, address(this), fsdFee);

        if (user.creation == 0) {
            user.creation = block.timestamp;
            user.gracePeriod =
                membership[msg.sender].creation +
                MEMBERSHIP_DURATION +
                60 days;
        } else {
            uint256 elapsedDurationPercentage = ((block.timestamp -
                user.creation) * 1 ether) / MEMBERSHIP_DURATION;
            if (elapsedDurationPercentage < 1 ether) {
                uint256 durationIncrease = (costShareBenefit.mul(1 ether) /
                    (totalCostShareBenefit - costShareBenefit)).mul(
                        MEMBERSHIP_DURATION
                    ) / 1 ether;
                user.gracePeriod += durationIncrease;
            }
        }
        user.availableCostShareBenefits = totalCostShareBenefit;

        emit NewMembership(msg.sender, costShareBenefit, membershipFees);

        uint256 governancePoolRewards = fsdFee.wmul(
            GOVERNANCE_FUNDING_POOL_REWARDS
        );

        // Staking Rewards = 20% + [FSHARERatio - 125%] (if FSHARERatio > 125%)
        uint256 stakingMultiplier = fShareRatio >= 1.25 ether
            ? STAKING_REWARDS + fShareRatio - 1.25 ether
            : STAKING_REWARDS;

        // Maximum of 85% as we have 15% distributed to governance + funding pool
        if (stakingMultiplier > 0.85 ether) stakingMultiplier = 0.85 ether;

        uint256 stakingRewards = fsdFee.wmul(stakingMultiplier);

        // 20% minimum as staking rewards & 7.5% towards governance
        fsd.safeTransfer(
            address(fsd),
            stakingRewards.add(governancePoolRewards)
        );
        fsd.registerTribute(stakingRewards);
        fsd.registerGovernanceTribute(governancePoolRewards);

        // 7.5% towards funding pool
        fsd.safeTransfer(FUNDING_POOL, governancePoolRewards);
    }

    /**
     * @dev Allows opening of Cross Share Request (CSR) by a member.
     *
     * It accepts parameter {ethAmount} representing claim amount of which only
     * 90% is paid in cross share benefits while the remaining 10% are unshareable.
     * The parameter {inStable} represents if the CSR's payout should be in ETH or
     * Stablecoin (DAI).
     *
     * Updates the {totalOpenRequests} (if the payout is in ETH) and {openCostShareBenefits} of the member.
     *
     * Determines {bounty} as 0.4% of the user's available cross share benefits, of which
     * half is kept in the contract while the other half is sent to {GOVERNANCE_ADDRESS}.
     *
     * Requirements:
     * - member has been a part of network for at least 24 hours and has active
     *   membership (grace period has not passed).
     * - user's {openCostShareBenefits} must not exceed user's {availableCostShareBenefits}.
     * - CSR type must be in-line with the DAO's approved type
     */
    function openCostShareRequest(
        uint256 ethAmount,
        bool inStable,
        uint256 _csrType
    ) external {
        Membership memory user = membership[msg.sender];
        // 90% of the full claim is paid out as 10% in the USA
        uint256 requestPayout = ethAmount.wmul(NON_USA);

        require(
            user.creation + 24 hours <= block.timestamp &&
                user.gracePeriod >= block.timestamp,
            "FSDNetwork::openCostShareRequest: Ineligible cost share request"
        );
        require(
            user.availableCostShareBenefits - user.openCostShareBenefits >=
                requestPayout,
            "FSDNetwork::openCostShareRequest: Cost request exceeds available cost share benefits"
        );
        require(
            approvedCsrTypes[_csrType],
            "FSDNetwork::openCostShareRequest: Cost request type is not approved"
        );

        uint256 fsdSpotPrice = getFSDPrice();
        // We want 10% of the membership fee -> 0.4% initially
        uint256 bounty = user
            .availableCostShareBenefits
            .wmul(membershipFee / 10)
            .wdiv(fsdSpotPrice);

        uint256 id = nextCSRID++;
        costShareRequests[id] = CostShareRequest(
            msg.sender,
            requestPayout,
            bounty,
            uint128(block.timestamp),
            0,
            bytes32(0),
            0,
            _csrType
        );
        membership[msg.sender].openCostShareBenefits = user
            .openCostShareBenefits
            .add(requestPayout);

        if (inStable) {
            uint256 etherPrice = getEtherPrice();
            // 5% slippage protection
            uint256 dai = fsd.liquidateEth(
                requestPayout,
                (requestPayout.mul(etherPrice) / 1 ether).mul(
                    100 - slippageTolerance
                ) / 100
            );
            costShareRequests[id].stableAmount = dai;
        } else {
            totalOpenRequests = totalOpenRequests.add(requestPayout);
        }

        emit CreateCSR(
            id,
            msg.sender,
            requestPayout,
            inStable,
            _csrType,
            block.timestamp
        );

        uint256 halfBounty = bounty / 2;
        // 50% locked
        fsd.safeTransferFrom(msg.sender, address(this), halfBounty);
        // 50% sent to DAO for manual unlocking based on offchain tracking
        fsd.safeTransferFrom(
            msg.sender,
            GOVERNANCE_ADDRESS,
            bounty - halfBounty
        );
    }

    /**
     * @dev Allows updating of CSR associated with parameter {id}.
     *
     * It accepts parameter {action} that determines the action to perform in
     * updating of CSR.
     *
     * Internally calls the {_processCostShareRequest} function.
     *
     * Requirements:
     * - assessors need to validate the {action} if the CSR has not expired.
     * - {Action.Expire} cannot be performed if the CSR is less than 7 days old
     *   or the voting has already opened.
     */
    function updateCostShareRequest(
        uint256 id,
        Action action,
        bytes calldata data,
        bytes calldata sig
    ) external {
        CostShareRequest memory csrData = costShareRequests[id];

        if (action == Action.Expire) {
            require(
                csrData.creation + 7 days <= block.timestamp &&
                    csrData.votingOpen == 0,
                "FSDNetwork::updateCostShareRequest: Invalid claim expiration"
            );
            _processCostShareRequest(
                id,
                csrData.initiator,
                csrData.ethAmount,
                csrData.stableAmount,
                false
            );

            emit ExpireCSR(id, csrData.initiator, block.timestamp);
        } else if (
            action == Action.SubmitEvidence || action == Action.ExtendClaim
        ) {
            require(
                _isApprovedByAssessors(sig, id, action),
                "FSDNetwork::updateCostShareRequest: Insufficient Privileges"
            );
            CostShareRequest storage csr = costShareRequests[id];
            csr.votingOpen = uint128(block.timestamp);
            if (action == Action.SubmitEvidence) {
                // Should represent hash of evidence
                csr.evidence = abi.decode(data, (bytes32));

                emit SubmitEvidenceCSR(
                    id,
                    msg.sender,
                    csr.evidence,
                    block.timestamp
                );
            } else {
                emit ExtendCSR(id, msg.sender, block.timestamp);
            }
        } else {
            require(
                _isApprovedByAssessors(sig, id, action),
                "FSDNetwork::updateCostShareRequest: Insufficient Privileges"
            );

            if (action == Action.ApproveClaim) {
                _processCostShareRequest(
                    id,
                    csrData.initiator,
                    csrData.ethAmount,
                    csrData.stableAmount,
                    true
                );

                emit AcceptCSR(
                    id,
                    msg.sender,
                    csrData.initiator,
                    csrData.ethAmount,
                    block.timestamp
                );
            } else {
                _processCostShareRequest(
                    id,
                    csrData.initiator,
                    csrData.ethAmount,
                    csrData.stableAmount,
                    false
                );

                emit RejectCSR(id, msg.sender, csrData.initiator, block.timestamp);
            }
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Adds to the network's staking rewards.
     *
     * Requirements:
     * - only callable by {PREMIUMS_POOL}.
     */
    function addStakingReward(uint256 tokenMinimum) external payable {
        require(
            msg.sender == PREMIUMS_POOL,
            "FSDNetwork::addStakingReward: Insufficient Privileges"
        );
        uint256 mintAmount = fsd.mint{value: msg.value}(
            address(this),
            tokenMinimum
        );

        fsd.safeTransfer(address(fsd), mintAmount);
        fsd.registerTribute(mintAmount);
    }

    /**
     * @dev Sets network's assessors.
     *
     * Requirements:
     * - only callable by governance.
     */
    function setAssessors(address[3] calldata _assessors) external {
        require(
            msg.sender == GOVERNANCE_ADDRESS,
            "FSDNetwork::setAssessors: Insufficient Privileges"
        );

        assessors = _assessors;
    }

    /**
     * @dev Sets cost share data entry.
     *
     * Requirements:
     * - only callable by governance.
     */
    function setCsrTypes(uint256 _csrType, bool _isApproved) external {
        require(
            msg.sender == GOVERNANCE_ADDRESS,
            "FSDNetwork::setDataEntry: Insufficient Privileges"
        );

        approvedCsrTypes[_csrType] = _isApproved;
    }

    /**
     * @dev Sets membership's additional wallets.
     *
     * Requirements:
     * - member has active membership (grace period has not passed)
     * - each membership can only contain up to three wallets
     * - wallets can only be set after the first membership purchase
     */
    function setMembershipWallets(address[2] calldata _wallets) external {
        Membership memory user = membership[msg.sender];
        require(
            user.gracePeriod >= block.timestamp,
            "FSDNetwork::setMembershipWallets: Membership expired"
        );
        require(
            _wallets[0] != address(0) && _wallets[1] != address(0),
            "FSDNetwork::setMembershipWallets: Invalid Addresses"
        );
        require(
            _wallets[0] != msg.sender &&
                _wallets[1] != msg.sender &&
                _wallets[0] != _wallets[1],
            "FSDNetwork::setMembershipWallets: Addresses Not Unique"
        );
        require(
            user.wallets[0] == address(0) && user.wallets[1] == address(0),
            "FSDNetwork::setMembershipWallets: Cannot have more than three wallets per membership"
        );

        membership[msg.sender].wallets = _wallets;
    }

    /**
     * @dev Sets slippage tolerance.
     *
     * Requirements:
     * - only callable by governance or timelock contracts.
     * - slippage tolerance must be less than 100%.
     */
    function setSlippageTolerance(uint256 _slippageTolerance)
        external
        onlyTimelockOrGovernance
    {
        require(
            _slippageTolerance <= 100,
            "FSDNetwork::setSlippageTolerance: Incorrect Slippage Specified"
        );
        slippageTolerance = _slippageTolerance;
    }

    /**
     * @dev Sets membership fee.
     *
     * Requirements:
     * - only callable by governance or timelock contracts.
     */
    function setMembershipFee(uint256 _membershipFee)
        external
        onlyTimelockOrGovernance
    {
        membershipFee = _membershipFee;
    }

    /**
     * @dev Sets the gearing factor of the FSD formula.
     *
     * Requirements:
     * - only callable by governance or timelock contracts.
     * - gearing factor must be more than zero.
     */
    function setGearingFactor(uint256 _gearingFactor)
        external
        onlyTimelockOrGovernance
    {
        require(
            _gearingFactor > 0,
            "FSDNetwork::setGearingFactor: Incorrect Value Specified"
        );
        uint256 currentGearingFactor = fsd.gearingFactor();
        // 0.25 max change for each direction
        if (_gearingFactor < currentGearingFactor)
            require(
                currentGearingFactor.sub(_gearingFactor) <= 25,
                "FSDNetwork::setGearingFactor: Cannot change"
            );
        else
            require(
                _gearingFactor.sub(currentGearingFactor) <= 25,
                "FSDNetwork::setGearingFactor: Cannot change"
            );

        fsd.setGearingFactor(_gearingFactor);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Processes a CSR associated with parameter {id}.
     *
     * It performs the payout to user in ETH or stablecoin if CSR is approved.
     * In case, if the CSR is not approved and the payout is in stablecoin then
     * stablecoin amount is converted back to ETH.
     *
     * Updates the available and open cross share benefits of the user.
     */
    function _processCostShareRequest(
        uint256 id,
        address beneficiary,
        uint256 amount,
        uint256 stableAmount,
        bool approved
    ) internal {
        if (stableAmount == 0) {
            totalOpenRequests -= amount;
        }

        if (approved) {
            membership[beneficiary].availableCostShareBenefits -= amount;
            fsd.payClaim(beneficiary, amount, stableAmount != 0);
        } else if (stableAmount != 0) {
            uint256 etherPrice = getEtherPrice();
            fsd.liquidateDai(
                stableAmount,
                (stableAmount.mul(1 ether) / etherPrice).mul(
                    100 - slippageTolerance
                ) / 100
            );
        }

        membership[beneficiary].openCostShareBenefits -= amount;

        delete costShareRequests[id];
    }

    /**
     * @dev Returns maximum cross share benefit allowed per user.
     * with the minimum being 100 ETH.
     */
    function _getMaximumBenefitPerUser() internal pure returns (uint256) {
        return 100 ether;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Returns whether the action was approved or not.
     * If the user is not already whitelisted then it retrieves
     * the parameter {sig} signer and compares it to the state
     * variable {assessors}, the success of which determines
     * the status of the approval.
     */
    function _isApprovedByAssessors(
        bytes memory sig,
        uint256 id,
        Action action
    ) private view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(CSR_ACTION, id, action))
        );

        address sigAssessor = ECDSA.recover(digest, sig);
        uint256 assessorsLength = assessors.length;
        bool assessorOne;
        bool assessorTwo;

        for (uint256 i = 0; i < assessorsLength; i++) {
            if (msg.sender == assessors[i]) {
                assessorOne = true;
            } else if (sigAssessor == assessors[i]) {
                assessorTwo = true;
            }
        }

        require(
            assessorOne && assessorTwo,
            "FSDNetwork::_isApprovedByAssessors: Not an Assessor"
        );

        return true;
    }

    function _onlyTimelockOrGovernance() private view {
        require(
            msg.sender == GOVERNANCE_ADDRESS || msg.sender == TIMELOCK,
            "FSDNetwork:: Insufficient Privileges"
        );
    }

    /* ========== MODIFIERS ========== */

    modifier onlyTimelockOrGovernance() {
        _onlyTimelockOrGovernance();
        _;
    }

    // Uniswap FSD / ETH Pair
    // address public uniswapFSDOracle;
    // Uniswap TWAP Variables
    // uint32 private blockTimestampLast;
    // uint256 private price0CumulativeLast;
    // FixedPoint.uq112x112 private price0Average;

    // function setUniswapOracle(IUniswapV2Pair _uniswapFSDOracle) external {
    //     require(msg.sender == governance, "FSDNetwork::setUniswapOracle: Insufficient Privileges");
    //     require(uniswapFSDOracle == address(0x0), "FSDNetwork::setUniswapOracle: Oracle already set");
    //     uniswapFSDOracle = _uniswapFSDOracle;
    // }

    // Security-wise, a TWAP of 1 hour is sufficient for the FSD price in USD as this is solely used for membership and claim fees
    // function getFSDPrice() public view returns (uint256) {
    //     (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
    // UniswapV2OracleLibrary.currentCumulativePrices(address(uniswapFSDOracle));

    //     if (blockTimestamp - blockTimestampLast >= PERIOD) {
    //         price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
    //         // price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));
    //         price0CumulativeLast = price0Cumulative;
    //         // price1CumulativeLast = price1Cumulative;
    //         blockTimestampLast = blockTimestamp;
    //     }

    //     // 1 FSD to ETH multiplied by ETH's price
    //     return price0Average.decode144().wmul(getEtherPrice());
    // }

    // /**
    //  * @dev Returns maximum cross share benefit allowed per user.
    //  * It is the minimum between 100 ETH and 0.05% of the capital pool.
    //  */
    // function _getMaximumBenefitPerUser() internal view returns (uint256) {
    //     uint256 minimumMaxBenefit = 100 ether;
    // uint256 dynamicMaxBenefit = (fsd.getReserveBalance() -
    //     totalOpenRequests).wmul(0.05 ether); // 5% of Capital Pool
    //     return
    //         minimumMaxBenefit > dynamicMaxBenefit
    //             ? minimumMaxBenefit
    //             : dynamicMaxBenefit;
    // }
}
