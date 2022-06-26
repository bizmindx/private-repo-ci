// SPDX-License-Identifier: Unlicense

import "../interfaces/IFairSideDAO.sol";
import "../interfaces/IERC20ConvictionScore.sol";
import "../timelock/Timelock.sol";
import "../dependencies/DSMath.sol";

pragma solidity =0.6.8;
pragma experimental ABIEncoderV2;

/**
 * @dev Implementation of {FairSideDAO} contract.
 *
 * The FairSideDAO contract allows creation of proposals by anyone
 * by anyone possessing the status of governance committee and possess conviction
 * score greater than {proposalThreshold}.
 *
 * Anyone can vote on the created proposals if they have a conviction score
 * greater than {votingThreshold}.
 *
 * Only 1 proposal can be active at a time by a particular proposer.
 *
 * A proposal can be voted either on-chain or off-chain. Off-chain voting requires
 * validation of cumulative {voteHash}.
 *
 * A proposal is queued when it succeeds and can be executed after a cool-off
 * time period specified by {delay} in the Timelock contract.
 *
 * A proposal can be cancelled by a {guardian} if it has not been already
 * executed. It can also be cancelled by anyone if the original proposer's
 * conviction score falls below {proposalThreshold}.
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract FairSideDAO is IFairSideDAO {
    /* ========== LIBRARIES ========== */

    using DSMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // The name of this contract
    string public constant name = "FairSide Governance";

    // Permitted call for a forced on-chain vote, disablement of offchain voting
    bytes32 private immutable DISABLE_OFFCHAIN_HASH;

    // Permitted call for a forced on-chain vote, adjustment of governance threshold
    bytes32 private immutable ADJUST_THRESHOLD_HASH;

    // Address to signify snapshotted total conviction score and governance conviction score
    address internal constant TOTAL_CONVICTION_SCORE = address(0);

    // Address to signify snapshotted total conviction score of governance
    address private constant GOVERNANCE_CONVICTION_SCORE =
        address(type(uint160).max);

    // Percentage of votes required to achieve a quorum
    uint256 private constant QUORUM_PERCENTAGE = 0.04 ether; // 4%

    // Percentage of votes required to make a proposal.
    uint256 private constant PROPOSAL_THRESHOLD = 0.01 ether; // 1%

    // The number of seconds per block
    uint256 private constant SECS_PER_BLOCK = 15; // ~15s for Ethereum

    // The address of the FairSide Timelock
    Timelock public immutable timelock;

    // The address of the FairSide Conviction Token
    IERC20ConvictionScore private immutable FSD;

    // The address of the Governor Guardian
    address public guardian;

    // The total number of proposals
    uint256 public proposalCount;

    // A bool indicating whether offchain or onchain voting processes should be used
    bool public offchain = true;

    struct Proposal {
        // Creator of the proposal
        address proposer;
        // The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        // the ordered list of target addresses for calls to be made
        address[] targets;
        // The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        // The ordered list of function signatures to be called
        string[] signatures;
        // The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        // The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        // The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        // Current number of votes in favor of this proposal
        uint256 forVotes;
        // Current number of votes in opposition to this proposal
        uint256 againstVotes;
        // Flag marking whether the proposal has been canceled
        bool canceled;
        // Flag marking whether the proposal has been executed
        bool executed;
        // Flag marking whether the proposal is meant to be voted offchain
        bool offchain;
        // Cumulative hash of votes for offchain proposals
        bytes32 voteHash;
        // Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
    }

    // Ballot receipt record for a voter
    struct Receipt {
        // Whether or not a vote has been cast
        bool hasVoted;
        // Whether or not the voter supports the proposal
        bool support;
        // The number of votes the voter had, which were cast
        uint224 votes;
    }

    // Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    // The official record of all proposals ever proposed associated via an ID
    mapping(uint256 => Proposal) private proposals;

    // The latest proposal for each proposer
    mapping(address => uint256) public latestProposalIds;

    // The EIP-712 typehash for the contract's domain
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    // The EIP-712 typehash for the ballot struct used by the contract
    bytes32 private constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,bool support)");

    /**
     * @dev {VoterPack} struct containing parameters for a vote for vote hash validation.
     * voter: Address of voter.
     * votes: Number of votes to vote.
     * support: The vote is in favour or against the proposal.
     */
    struct VotePack {
        address voter;
        uint256 votes;
        bool support;
    }

    /* ========== EVENTS ========== */

    // An event emitted when a new proposal is created
    event ProposalCreated(
        uint256 id,
        address proposer,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    // An event emitted when a vote has been cast on a proposal
    event VoteCast(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 votes
    );

    // An event emitted when offchain votes have been recorded on-chain
    event OffchainVotesCast(
        uint256 proposalId,
        bytes32 voteHash,
        uint256 forVotes,
        uint256 againstVotes
    );

    // An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    // An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    // An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initializes the contract's state setting FSD, guardian and timelock addresses.
     */
    constructor(
        Timelock _timelock,
        IERC20ConvictionScore _FSD,
        address _guardian
    ) public {
        FSD = _FSD;
        guardian = _guardian;
        timelock = _timelock;
        ADJUST_THRESHOLD_HASH = keccak256("updateGovernanceThreshold(uint256)");
        DISABLE_OFFCHAIN_HASH = keccak256("disableOffchainVoting()");
    }

    /* ========== VIEWS ========== */

    // The total votes within the system
    function totalVotes() public view returns (uint256) {
        return totalVotes(block.number - 1);
    }

    // Returns total votes within system at block {n}.
    function totalVotes(uint256 n) public view returns (uint256) {
        return FSD.getPriorConvictionScore(GOVERNANCE_CONVICTION_SCORE, n);
    }

    // Conviction score necessary to be able to vote
    function votingThreshold() public view returns (uint256) {
        return FSD.governanceThreshold();
    }

    // The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public view returns (uint256) {
        return quorumVotes(totalVotes());
    }

    // Returns quorum percentage of provided parameter of {_totalVotes}.
    function quorumVotes(uint256 _totalVotes) public pure returns (uint256) {
        return _totalVotes.wmul(QUORUM_PERCENTAGE);
    }

    // The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public view returns (uint256) {
        return proposalThreshold(totalVotes());
    } // 100,000 = 1% of Comp

    // Returns the calculated number minimum votes required proposal based on {_totalVotes}.
    function proposalThreshold(uint256 _totalVotes)
        public
        pure
        returns (uint256)
    {
        return _totalVotes.wmul(PROPOSAL_THRESHOLD);
    } // 100,000 = 1% of Comp

    // The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint256) {
        return 10;
    } // 10 actions

    // The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint256) {
        return 1;
    } // 1 block

    // The duration of voting on a proposal, in blocks
    function votingPeriod() public pure returns (uint256) {
        return 3 days / SECS_PER_BLOCK;
    } // ~3 days in blocks

    /**
     * @dev Returns the actions contained in a proposal with id {proposalId}.
     */
    function getActions(uint256 proposalId)
        public
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /**
     * @dev Returns receipt of the {voter} against the proposal with id {proposalId}.
     */
    function getReceipt(uint256 proposalId, address voter)
        public
        view
        returns (Receipt memory)
    {
        return proposals[proposalId].receipts[voter];
    }

    /**
     * @dev Returns the current state of the proposal with id {proposalId}.
     *
     * Requirements:
     * - The {proposalId} should be greater than 0
     * - The {proposalId} should be less than or equal to {proposalCount}
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "FairSideDAO::state: invalid proposal id"
        );
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (
            proposal.forVotes.mul(10000) /
                proposal.forVotes.add(proposal.againstVotes) <=
            6600 ||
            proposal.forVotes < quorumVotes(totalVotes(proposal.startBlock))
        ) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (
            block.timestamp >= proposal.eta.add(timelock.GRACE_PERIOD())
        ) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @dev Validates the votes pack for off-chain vote hash validation.
     */
    function validateVoteHash(uint256 proposalId, VotePack[] calldata votes)
        external
        view
        returns (bool)
    {
        uint256 voteBlock = proposals[proposalId].startBlock;
        bytes32 voteHash = keccak256(abi.encode(proposalId, voteBlock));
        for (uint256 i = 0; i < votes.length; i++) {
            voteHash = keccak256(abi.encode(voteHash, votes[i]));
            if (
                FSD.getPriorConvictionScore(votes[i].voter, voteBlock) !=
                votes[i].votes
            ) return false;
        }
        return voteHash == proposals[proposalId].voteHash;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows to make a proposal if the conviction score of `msg.sender` is
     * greater than {proposalThreshold}.
     *
     * It accepts targets along with the values, signature and calldatas
     * for the actions to perform if the proposal succeeds.
     *
     * Allows specific actions to be performed forcefully on-chain. These actions
     * are {DISABLE_OFFCHAIN_HASH} on current contract and {ADJUST_THRESHOLD_HASH}
     * on FSD contract.
     *
     * Requirements:
     * - targets, values, signatures and calldatas arrays' lengths must be greater
     *   than zero, less than {proposalMaxOperations} and are the same length.
     * - the caller must not have an active/pending proposal.
     * - the caller must have governance committee status and conviction score
     *   greater than {proposalThreshold}.
     * - for {forceOnchain} proposal, there can only be one action either {DISABLE_OFFCHAIN_HASH}
     *   or {ADJUST_THRESHOLD_HASH}.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        bool forceOnchain
    ) public override returns (uint256) {
        require(
            FSD.getPriorConvictionScore(msg.sender, block.number - 1) >
                proposalThreshold() &&
                FSD.isGovernance(msg.sender),
            "FairSideDAO::propose: proposer votes below proposal threshold"
        );
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            "FairSideDAO::propose: proposal function information arity mismatch"
        );
        require(
            targets.length != 0,
            "FairSideDAO::propose: must provide actions"
        );
        require(
            targets.length <= proposalMaxOperations(),
            "FairSideDAO::propose: too many actions"
        );

        uint256 userCS = uint256(
            FSD.getPriorConvictionScore(msg.sender, block.number - 1)
        );
        uint256 totalCS = uint256(
            FSD.getPriorConvictionScore(TOTAL_CONVICTION_SCORE, block.number - 1)
        );
        require(
            userCS.mul(100) / totalCS >= 1,
            "FairSideDAO::propose: need 1% or more of the full network Conviction Score"
        );

        if (forceOnchain) {
            require(
                targets.length == 1,
                "FairSideDAO::propose: only a single action is permitted for a forced onchain vote"
            );
            bytes32 signatureHash = keccak256(abi.encodePacked(signatures[0]));
            require(
                (targets[0] == address(this) &&
                    signatureHash == DISABLE_OFFCHAIN_HASH) ||
                    (targets[0] == address(FSD) &&
                        signatureHash == ADJUST_THRESHOLD_HASH),
                "FairSideDAO::propose: only adjustment of governance threshold or revocation of offchain process can be forced onchain"
            );
        }

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(
                latestProposalId
            );
            require(
                proposersLatestProposalState != ProposalState.Active,
                "FairSideDAO::propose: one live proposal per proposer, found an already active proposal"
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                "FairSideDAO::propose: one live proposal per proposer, found an already pending proposal"
            );
        }

        uint256 startBlock = block.number + votingDelay();
        uint256 endBlock = startBlock + votingPeriod();

        proposalCount++;
        uint256 proposalId = proposalCount;

        proposals[proposalId].proposer = msg.sender;
        proposals[proposalId].targets = targets;
        proposals[proposalId].values = values;
        proposals[proposalId].signatures = signatures;
        proposals[proposalId].calldatas = calldatas;
        proposals[proposalId].startBlock = startBlock;
        proposals[proposalId].endBlock = endBlock;
        proposals[proposalId].offchain = forceOnchain ? false : offchain;

        latestProposalIds[msg.sender] = proposalId;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            startBlock,
            endBlock,
            description
        );

        return proposalId;
    }

    /**
     * @dev Queues a proposal by setting the hashes of its actions in {Timelock} contract.
     * It also determines 'eta' for the proposal by adding timestamp to {delay} in {Timelock}
     * and sets it against the proposal in question.
     *
     * Requirements:
     * - the proposal in question must have succeeded either through majority for-votes.
     */
    function queue(uint256 proposalId) public {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "FairSideDAO::queue: proposal can only be queued if it is succeeded"
        );
        Proposal storage proposal = proposals[proposalId];
        uint256 targetCount = proposal.targets.length;
        uint256 eta = block.timestamp + timelock.delay();
        for (uint256 i = 0; i < targetCount; i++) {
            _queueOrRevert(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                eta
            );
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    /**
     * @dev Executes a proposal after it has been queued and delay time has elapsed.
     * It sets the {executed} status of the proposal to 'true'.
     *
     * Requirements:
     * - the proposal in question must have been queued and delay time has elapsed.
     * - none of the actions of the proposal revert upon execution.
     */
    function execute(uint256 proposalId) public payable {
        require(
            state(proposalId) == ProposalState.Queued,
            "FairSideDAO::execute: proposal can only be executed if it is queued"
        );
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        uint256 targetCount = proposal.targets.length;
        for (uint256 i = 0; i < targetCount; i++) {
            timelock.executeTransaction{value: proposal.values[i]}(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }
        emit ProposalExecuted(proposalId);
    }

    /**
     * @dev Cancels the proposal with id {proposalId}.
     * It also sets the {canceled} property of {Proposal} to `true` and
     * removes the proposal's corresponding actions from {Timelock} contract.
     *
     * Requirements:
     * - proposal must not be already executed.
     * - can be called by guardian at any time.
     * - can be called by anyone with
     * - the caller must have governance committee status if proposer's
     *   conviction score falls below {proposalThreshold}.
     */
    function cancel(uint256 proposalId) public {
        ProposalState _state = state(proposalId);
        require(
            _state != ProposalState.Executed,
            "FairSideDAO::cancel: cannot cancel executed proposal"
        );

        Proposal storage proposal = proposals[proposalId];
        require(
            msg.sender == guardian ||
                (FSD.getPriorConvictionScore(
                    proposal.proposer,
                    block.number - 1
                ) <
                    proposalThreshold() &&
                    FSD.isGovernance(msg.sender)),
            "FairSideDAO::cancel: proposer above threshold"
        );

        proposal.canceled = true;

        uint256 targetCount = proposal.targets.length;
        for (uint256 i = 0; i < targetCount; i++) {
            timelock.cancelTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }

        emit ProposalCanceled(proposalId);
    }

    /**
     * @dev Casts vote by {msg.sender}.
     * It calls the internal function `_castVote` to perform vote casting.
     */
    function castVote(uint256 proposalId, bool support) public override {
        require(
            FSD.isGovernance(msg.sender),
            "FairSideDAO::castVote: not part of governance"
        );
        _castVote(msg.sender, proposalId, support);
    }

    /**
     * @dev Called by a relayer to cast vote by a message signer.
     *
     * Requirements:
     * - {signatory} retrieved must not be a zero address
     */
    function castVoteBySig(
        uint256 proposalId,
        bool support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                getChainId(),
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(BALLOT_TYPEHASH, proposalId, support)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "FairSideDAO::castVoteBySig: invalid signature"
        );
        require(
            FSD.isGovernance(signatory),
            "FairSideDAO::castVote: not part of governance"
        );
        _castVote(signatory, proposalId, support);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Disables off-chain voting by setting {offchain} to `false` and
     * abdicating guardian.
     *
     * Requirements:
     * - can only be called by either {guardian} or {timelock}.
     */
    function disableOffchainVoting() public {
        require(
            msg.sender == guardian || msg.sender == address(timelock),
            "FairSideDAO::disableOffchainVoting: sender must be guardian or timelock address"
        );
        guardian = address(0);
        offchain = false;
    }

    /**
     * @dev Enables off-chain voting by setting {offchain} to `true` and
     * setting a new {guardian}.
     *
     * Requirements:
     * - can only be called by either {guardian} or {timelock}.
     */
    function enableOffchainVoting(address _guardian) public {
        require(
            msg.sender == address(timelock),
            "FairSideDAO::enableOffchainVoting: sender must be timelock address"
        );
        guardian = _guardian;
        offchain = true;
    }

    /**
     * @dev Casts the off-chain votes against a proposal.
     *
     * Requirements:
     * - only guardian can call.
     * - proposal must have {Defeated} status prior to off-chain vote casting.
     * - proposal only accepts off-chain votes.
     */
    function __castOffchainVotes(
        uint256 proposalId,
        bytes32 voteHash,
        uint256 forVotes,
        uint256 againstVotes
    ) public {
        require(
            msg.sender == guardian,
            "FairSideDAO::__castOffchainVotes: sender must be gov guardian"
        );
        // Defeated is the status once voting has ended and no votes have been cast
        require(
            state(proposalId) == ProposalState.Defeated,
            "FairSideDAO::__castOffchainVotes: voting is in progress"
        );
        Proposal storage proposal = proposals[proposalId];
        require(
            proposal.offchain,
            "FairSideDAO::__castOffchainVotes: proposal is meant to be voted onchain"
        );
        proposal.voteHash = voteHash;
        proposal.forVotes = forVotes;
        proposal.againstVotes = againstVotes;

        emit OffchainVotesCast(proposalId, voteHash, forVotes, againstVotes);
    }

    /**
     * @dev Calls {acceptAdmin} on {Timelock} contract and makes the current contract
     * the admin of {Timelock} contract.
     *
     * Requirements:
     * - only guardian can call it
     * - current contract must be the `pendingAdmin` in {Timelock} contract
     */
    function __acceptAdmin() public {
        require(
            msg.sender == guardian,
            "FairSideDAO::__acceptAdmin: sender must be gov guardian"
        );
        timelock.acceptAdmin();
    }

    /**
     * @dev Gives up the guardian role associated with the contract.
     *
     * Requirements:
     * - only callable by guardian
     */
    function __abdicate() public {
        require(
            msg.sender == guardian,
            "FairSideDAO::__abdicate: sender must be gov guardian"
        );
        guardian = address(0);
    }

    /**
     * @dev Queues the transaction to set `pendingAdmin` in {Timelock}.
     *
     * Requirements:
     * - only callable by guardian
     */
    function __queueSetTimelockPendingAdmin(
        address newPendingAdmin,
        uint256 eta
    ) public {
        require(
            msg.sender == guardian,
            "FairSideDAO::__queueSetTimelockPendingAdmin: sender must be gov guardian"
        );
        timelock.queueTransaction(
            address(timelock),
            0,
            "setPendingAdmin(address)",
            abi.encode(newPendingAdmin),
            eta
        );
    }

    /**
     * @dev Executes the transaction to set `pendingAdmin` in {Timelock}.
     *
     * Requirements:
     * - only callable by guardian
     */
    function __executeSetTimelockPendingAdmin(
        address newPendingAdmin,
        uint256 eta
    ) public {
        require(
            msg.sender == guardian,
            "FairSideDAO::__executeSetTimelockPendingAdmin: sender must be gov guardian"
        );
        timelock.executeTransaction(
            address(timelock),
            0,
            "setPendingAdmin(address)",
            abi.encode(newPendingAdmin),
            eta
        );
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Queues a transaction in {Timelock}.
     *
     * Requirements:
     * - transaction is not already queued in {Timelock}.
     */
    function _queueOrRevert(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) internal {
        require(
            !timelock.queuedTransactions(
                keccak256(abi.encode(target, value, signature, data, eta))
            ),
            "FairSideDAO::_queueOrRevert: proposal action already queued at eta"
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    /**
     * @dev Casts vote against proposal with id {proposalId}.
     * It gets the conviction score that is treated as votes from FSD contract
     * at block number corresponding to when proposal started and adds those
     * votes to either {forVotes} or {againstVotes} property of {Proposal}
     * depending upon if the voter is voting in favor of or against the proposal.
     *
     * Requirements:
     * - proposal being voted must be active.
     * - voter has not already voted against the proposal.
     * - proposal is scheduled to be executed on-chain.
     * - {votes} to cast be greater than {votingThreshold}.
     */
    function _castVote(
        address voter,
        uint256 proposalId,
        bool support
    ) internal {
        require(
            state(proposalId) == ProposalState.Active,
            "FairSideDAO::_castVote: voting is closed"
        );
        Proposal storage proposal = proposals[proposalId];
        require(
            !proposal.offchain,
            "FairSideDAO::_castVote: proposal is meant to be voted offchain"
        );
        Receipt storage receipt = proposal.receipts[voter];
        require(
            !receipt.hasVoted,
            "FairSideDAO::_castVote: voter already voted"
        );
        uint224 votes = FSD.getPriorConvictionScore(voter, proposal.startBlock);
        require(
            votes >= uint224(votingThreshold()),
            "FairSideDAO::_castVote: insufficient votes"
        );

        if (support) {
            proposal.forVotes = proposal.forVotes.add(votes);
        } else {
            proposal.againstVotes = proposal.againstVotes.add(votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }

    // gets the chainid from current network
    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        // solhint-disable-next-line
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
