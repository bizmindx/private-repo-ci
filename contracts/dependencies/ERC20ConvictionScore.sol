// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "../dependencies/SafeUint224.sol";
import "../interfaces/IFairSideConviction.sol";
import "./CurveLock.sol";
import "./DSMath.sol";

/**
 * @dev Implementation of {ERC20ConvictionScore} contract.
 *
 * The ERC20ConvictionScore contract keeps track of conviction scores of users
 * on checkpoints basis.
 *
 * Allow assigning and removal of governance committee status of users if they
 * meet the {governanceMinimumBalance} and {governanceThreshold}.
 *
 * Allows users to exit from FSD network by minting conviction NFT and locking in
 * their FSD tokens and conviction score.
 *
 * Allows redemption of conviction NFT by owner assimilation of redeemed conviction
 * score with user's conviction score.
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
abstract contract ERC20ConvictionScore is CurveLock {
    /* ========== LIBRARIES ========== */

    using SafeUint224 for *;

    /* ========== STATE VARIABLES ========== */

    // Ten days in seconds
    uint256 private constant TEN_DAYS = 10 days;

    // The FairSideConviction ERC-721 token address
    IFairSideConviction public fairSideConviction;

    // Mapping indicating whether a user is part of the governance committee
    mapping(address => bool) public override isGovernance;

    // Mapping indicating whether a user should accrue conviction or not
    mapping(address => bool) public convictionless;

    // // Mapping indicating a user's conviction score update
    // mapping(address => uint256) public lastConvictionTs;

    // Conviction score necessary to become part of governance
    uint256 public override governanceThreshold = 10 * 10000e18; // 10 days * 10,000 units

    // Minimum balance
    int256 public override minimumBalance = 1000 ether; // 1,000 tokens

    // Minimum governance balance
    int256 public governanceMinimumBalance = 10000 ether; // 10,000 tokens

    /**
     * @dev A checkpoint for marking the conviction score from a given block
     * fromBlock: Block number of the checkpoint.
     * convictionScore: Conviction score at a given block.
     * ts: Timestamp of the block.
     */
    struct Checkpoint {
        uint32 fromBlock;
        uint224 convictionScore;
        uint256 ts;
    }

    // Conviction score based on # of days multiplied by # of FSD & NFT
    // A record of conviction score checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    // The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initialises the contract's state and setup ERC20 name and symbol.
     *
     * Sets the {convictionless} status for {TOTAL_CONVICTION_SCORE} and {TOTAL_GOVERNANCE_SCORE}.
     */
    constructor(string memory name, string memory symbol)
        public
        ERC20(name, symbol)
    {
        convictionless[TOTAL_CONVICTION_SCORE] = true;
        convictionless[TOTAL_GOVERNANCE_SCORE] = true;
    }

    // solhint-disable-next-line
    function claimAvailableTributes(uint256 num) external virtual override {}

    // solhint-disable-next-line
    function registerTribute(uint256 num) external virtual override {}

    // solhint-disable-next-line
    function registerGovernanceTribute(uint256 num) external virtual override {}

    /* ========== VIEWS ========== */

    /**
     * @notice Determine the prior amount of conviction score for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the conviction score balance at
     * @return convictionScore The amount of conviction score the account had as of the given block
     */
    function getPriorConvictionScore(address account, uint256 blockNumber)
        public
        view
        override
        returns (uint224 convictionScore)
    {
        require(
            blockNumber < block.number,
            "ERC20ConvictionScore::getPriorConvictionScore: not yet determined"
        );

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].convictionScore;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;

        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow

            Checkpoint memory cp = checkpoints[account][center];

            if (cp.fromBlock == blockNumber) {
                return cp.convictionScore;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center > 0 ? center - 1 : 0;
            }
        }

        return checkpoints[account][lower].convictionScore;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Updates the conviction score for `msg.sender`.
     * Internally calls `updateConvictionScore(address)` function.
     */
    function updateConvictionScore() external returns (uint256) {
        return updateConvictionScore(msg.sender);
    }

    /**
     * @dev Updates the conviction score for {user}.
     * Internally calls `_updateConvictionScore` and `_updateConvictionTotals` functions.
     */
    function updateConvictionScore(address user) public returns (uint256) {
        (
            uint224 convictionDelta,
            int224 governanceDelta
        ) = _updateConvictionScore(user, 0);

        _updateConvictionTotals(convictionDelta, governanceDelta);

        return uint256(convictionDelta);
    }

    /**
     * @dev Allows exiting from FSD Network by minting a conviction NFT
     * on {FairSideConviction} contract which locks their FSD amount
     * and conviction score.
     *
     * It resets the user's conviction score in contract.
     *
     * Requirements:
     * - score or locked amount, both must not be zero.
     */
    function tokenizeConviction(uint256 locked)
        external
        override
        returns (uint256)
    {
        if (locked > 0) {
            _transfer(msg.sender, address(fairSideConviction), locked);
        } else {
            updateConvictionScore(msg.sender);
        }

        (, , uint224 score, ) = _getCheckpointInfo(msg.sender);

        require(
            score != 0 || locked != 0,
            "ERC20ConvictionScore::tokenizeConviction: Invalid tokenized conviction"
        );

        bool wasGovernance = isGovernance[msg.sender];
        _resetConviction(msg.sender);

        return
            fairSideConviction.createConvictionNFT(
                msg.sender,
                uint256(score),
                locked,
                wasGovernance
            );
    }

    /**
     * @dev Allows redemption of conviction NFT and receives its locked FSD along
     * with locked conviction score.
     *
     * Increases the conviction score of user and total conviction score by
     * the conviction score redeemed from NFT.
     *
     * Increases total governance conviction score by redeemed conviction score
     * if the redeemer is already a part of governance committee or else it is
     * increased by the conventional conviction of user.
     */
    function acquireConviction(uint256 id) external returns (uint256) {
        (uint224 convictionDelta, , bool wasGovernance) = fairSideConviction
            .burn(msg.sender, id);

        (, , , uint256 prevTimestamp) = _getCheckpointInfo(msg.sender);
        uint224 userNew = _increaseConvictionScore(msg.sender, convictionDelta);
        int224 governanceDelta;

        if (isGovernance[msg.sender]) {
            governanceDelta = convictionDelta.safeSign(
                "ERC20ConvictionScore::acquireConviction: Abnormal NFT conviction"
            );
        } else if (
            wasGovernance ||
            _meetsGovernanceMinimum(
                balanceOf(msg.sender),
                userNew,
                prevTimestamp
            )
        ) {
            isGovernance[msg.sender] = true;

            governanceDelta = userNew.safeSign(
                "ERC20ConvictionScore::acquireConviction: Abnormal total conviction"
            );
        }

        _updateConvictionTotals(convictionDelta, governanceDelta);

        return uint256(convictionDelta);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Sets governance status of the user when it meets the {governanceThreshold}.
     */
    function _bestowGovernanceStatus(address user) internal {
        if (!isGovernance[user]) {
            isGovernance[user] = true;
        }
    }

    /**
     * @dev Returns the boolean value indicating if user meets governance minimum
     */
    function _meetsGovernanceMinimum(
        uint256 balance,
        uint224 convictionScore,
        uint256 ts
    ) internal view returns (bool) {
        return
            (convictionScore >= governanceThreshold) &&
            (balance >= uint256(governanceMinimumBalance)) &&
            (block.timestamp - ts) >= TEN_DAYS;
    }

    /**
     * @dev Returns last checkpoint info of a user.
     */
    function _getCheckpointInfo(address user)
        internal
        view
        returns (
            uint32 checkpointCount,
            uint32 prevFromBlock,
            uint224 prevConvictionScore,
            uint256 prevTimestamp
        )
    {
        checkpointCount = numCheckpoints[user];

        if (checkpointCount > 0) {
            Checkpoint memory checkpoint = checkpoints[user][
                checkpointCount - 1
            ];

            prevFromBlock = checkpoint.fromBlock;
            prevConvictionScore = checkpoint.convictionScore;
            prevTimestamp = checkpoint.ts;
        }
    }

    /**
     * @dev Writes checkpoint for a user.
     *
     * Requirements:
     * - block.number must not exceed `uint32`.
     */
    function _writeCheckpoint(
        address user,
        uint32 nCheckpoints,
        uint224 newCS
    ) internal {
        uint32 blockNumber = block.number.safe32(
            "ERC20ConvictionScore::_writeCheckpoint: block number exceeds 32 bits"
        );

        Checkpoint storage checkpoint = checkpoints[user][nCheckpoints - 1];

        if (nCheckpoints > 0 && checkpoint.fromBlock == blockNumber) {
            checkpoint.convictionScore = newCS;
        } else {
            checkpoints[user][nCheckpoints] = Checkpoint(
                blockNumber,
                newCS,
                block.timestamp
            );

            numCheckpoints[user] = nCheckpoints + 1;
        }
    }

    /**
     * @dev Increases conviction score of a {user} by {amount}
     * and write the checkpoint.
     *
     * Requirements:
     * - {amount} must not overflow `uint224`.
     */
    function _increaseConvictionScore(address user, uint224 amount)
        internal
        returns (uint224 newConvictionScore)
    {
        (
            uint32 checkpointCount,
            ,
            uint224 prevConvictionScore,

        ) = _getCheckpointInfo(user);

        if (amount == 0) return prevConvictionScore;

        newConvictionScore = prevConvictionScore.add224(
            amount,
            "ERC20ConvictionScore::_increaseConvictionScore: conviction score amount overflows"
        );

        _writeCheckpoint(user, checkpointCount, newConvictionScore);
    }

    /**
     * @dev Decreases conviction score of a {user} by {amount}
     * and write the checkpoint.
     *
     * Requirements:
     * - {amount} must not overflow `uint224`.
     */
    function _decreaseConvictionScore(address user, uint224 amount)
        internal
        returns (uint224 newConvictionScore)
    {
        (
            uint32 checkpointCount,
            ,
            uint224 prevConvictionScore,

        ) = _getCheckpointInfo(user);

        if (amount == 0) return prevConvictionScore;

        newConvictionScore = prevConvictionScore.sub224(
            amount,
            "ERC20ConvictionScore::_decreaseConvictionScore: conviction score amount underflows"
        );

        _writeCheckpoint(user, checkpointCount, newConvictionScore);
    }

    /**
     * @dev Apply conviction score of a {user} by {delta}
     * and write the checkpoint.
     *
     * Conviction score is increased if delta is greater than 0 and
     * decreased when delta is less than 0.
     *
     * Requirements:
     * - {amount} must not overflow `uint224`.
     */
    function _applyConvictionDelta(address user, int224 delta)
        internal
        returns (uint224 newConvictionScore)
    {
        (
            uint32 checkpointCount,
            ,
            uint224 prevConvictionScore,

        ) = _getCheckpointInfo(user);

        if (delta == 0) return prevConvictionScore;

        newConvictionScore = delta > 0
            ? prevConvictionScore.add224(
                uint224(delta),
                "ERC20ConvictionScore::_applyConvictionDelta: conviction score amount overflows"
            )
            : prevConvictionScore.sub224(
                uint224(-delta),
                "ERC20ConvictionScore::_applyConvictionDelta: conviction score amount underflows"
            );

        _writeCheckpoint(user, checkpointCount, newConvictionScore);
    }

    /**
     * @dev Resets the user's staking and governance conviction scores with
     * updating the state variables of {TOTAL_CONVICTION_SCORE} and {TOTAL_GOVERNANCE_SCORE}.
     */
    function _resetConviction(address user) internal {
        (uint32 userNum, , uint224 convictionDelta, ) = _getCheckpointInfo(
            user
        );
        _writeCheckpoint(user, userNum, 0);

        _decreaseConvictionScore(TOTAL_CONVICTION_SCORE, convictionDelta);

        if (isGovernance[user]) {
            isGovernance[user] = false;
            _decreaseConvictionScore(TOTAL_GOVERNANCE_SCORE, convictionDelta);
        }
    }

    /**
     * @dev Updates the state variables of {TOTAL_CONVICTION_SCORE} and {TOTAL_GOVERNANCE_SCORE}
     * by {convictionDelta} and {governanceDelta}, respectively.
     */
    function _updateConvictionTotals(
        uint224 convictionDelta,
        int224 governanceDelta
    ) internal {
        _increaseConvictionScore(TOTAL_CONVICTION_SCORE, convictionDelta);
        _applyConvictionDelta(TOTAL_GOVERNANCE_SCORE, governanceDelta);
    }

    /**
     * @dev Updates the conviction score of a user and returns the conviction
     * and governance delta.
     *
     * If the user maintains {governanceMinimumBalance} and once the accrued
     * conviction amount exceeds {governanceThreshold}, then it is awarded governance
     * committee status and the user becomes eligible to vote.
     *
     * Updates the user's conviction score with the newly accrued amount since last update.
     *
     * Removes the governance committee status of user if its balance falls below
     * than {governanceMinimumBalance}.
     *
     * Returns the change in conventional conviction and governance conviction.
     *
     * Requirements:
     * - the amounts in accounting of conviction scores must not overflow.
     */
    function _updateConvictionScore(address user, int256 amount)
        internal
        returns (uint224 convictionDelta, int224 governanceDelta)
    {
        if (convictionless[user]) return (0, 0);

        uint256 balance = balanceOf(user);

        if (balance < uint256(minimumBalance)) return (0, 0);

        (
            uint32 checkpointCount,
            ,
            uint224 prevConvictionScore,
            uint256 prevTimestamp
        ) = _getCheckpointInfo(user);

        convictionDelta = (balance.mul(block.timestamp - prevTimestamp) /
            1 days).safe224(
                "ERC20ConvictionScore::_updateConvictionScore: Conviction score has reached maximum limit"
            );

        if (checkpointCount == 0) {
            _writeCheckpoint(user, 0, 0);
            return (convictionDelta, 0);
        }

        bool hasMinimumGovernanceBalance = (int256(balance) + amount) >=
            governanceMinimumBalance;

        if (
            convictionDelta == 0 &&
            isGovernance[user] &&
            !hasMinimumGovernanceBalance
        ) {
            isGovernance[user] = false;

            governanceDelta = -prevConvictionScore.safeSign(
                "ERC20ConvictionScore::_updateConvictionScore: Abnormal total conviction"
            );

            return (convictionDelta, governanceDelta);
        }

        uint224 userNew = prevConvictionScore.add224(
            convictionDelta,
            "ERC20ConvictionScore::_updateConvictionScore: conviction score amount overflows"
        );

        _writeCheckpoint(user, checkpointCount, userNew);

        if (address(fairSideConviction) == user) {
            governanceDelta = 0;
        } else if (isGovernance[user]) {
            if (hasMinimumGovernanceBalance) {
                governanceDelta = convictionDelta.safeSign(
                    "ERC20ConvictionScore::_updateConvictionScore: Abnormal conviction increase"
                );
            } else {
                isGovernance[user] = false;
                governanceDelta = -getPriorConvictionScore(
                    user,
                    block.number - 1
                ).safeSign(
                        "ERC20ConvictionScore::_updateConvictionScore: Abnormal total conviction"
                    );
            }
        } else if (
            userNew >= governanceThreshold &&
            hasMinimumGovernanceBalance &&
            (block.timestamp - prevTimestamp) >= TEN_DAYS
        ) {
            isGovernance[user] = true;
            governanceDelta = userNew.safeSign(
                "ERC20ConvictionScore::_updateConvictionScore: Abnormal total conviction"
            );
        }
    }

    /**
     * @dev A transfer hook that updates sender and recipient's conviction scores
     * and also update the total staking and governance scores.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        CurveLock._beforeTokenTransfer(from, to, amount);

        (
            uint224 convictionDeltaA,
            int224 governanceDeltaA
        ) = _updateConvictionScore(from, -int256(amount));

        (
            uint224 convictionDeltaB,
            int224 governanceDeltaB
        ) = _updateConvictionScore(to, int256(amount));

        uint224 convictionDelta = convictionDeltaA.add224(
            convictionDeltaB,
            "ERC20ConvictionScore::_beforeTokenTransfer: Total Conviction Overflow"
        );

        int224 governanceDelta = governanceDeltaA.addSigned224(
            governanceDeltaB,
            "ERC20ConvictionScore::_beforeTokenTransfer: Governance Conviction Overflow"
        );

        _updateConvictionTotals(convictionDelta, governanceDelta);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */

    // function claimGovernanceTribute(uint256 num) external virtual override {}
}
