// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

import "../dependencies/SafeUint224.sol";
import "../interfaces/IFairSideConviction.sol";
import "./CurveLock.sol";
import "./DSMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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
abstract contract ERC20ConvictionScore is CurveLock, ReentrancyGuard {
    // Ten days in seconds
    uint256 private constant TEN_DAYS = 10 days;

    // The FairSideConviction ERC-721 token address
    IFairSideConviction public fairSideConviction;

    // TODO: This section really need some rewrite

    // Conviction score necessary to become part of governance: // 10 days * 10,000 units
    uint256 public override governanceThreshold = 10 * 10000e18;

    // Minimum governance balance: // 10,000 tokens
    uint256 public governanceMinimumBalance = 10000 ether;

    // Minimum balance
    int256 public override minimumBalance = 1000 ether; // 1,000 tokens

    // Conviction tracking using SNX reward contract style
    mapping(address => uint256) public convictions;
    mapping(address => uint256) public userConvictionPerTokenProvided;

    uint256 public immutable rewardDurationInSeconds;
    uint256 public periodFinish;
    uint256 public convictionRate;
    uint256 public lastUpdateTime;
    uint256 public convictionPerTokenStored;

    uint256 constant internal BASE_UNIT = 1e18;

    address public deployer;
    uint256 public initialConvictionEmissionTime = 0;

    event ConvictionAccumulationStarted(address account);

    constructor(string memory name, string memory symbol) ERC20(name, symbol){
        // Assuming conviction will be accrued and accounted for 100 years from the day of the deployment
        rewardDurationInSeconds = 100 * 365 * 1 days;
        deployer = msg.sender;
        initialConvictionEmissionTime = block.timestamp;
    }

    modifier updateConviction(address account) {
        convictionPerTokenStored = convictionPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            convictions[account] = convictionAccumulated(account);
            userConvictionPerTokenProvided[account] = convictionPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function convictionPerToken() public view returns (uint256) {
        if (super.totalSupply() == 0) {
            return convictionPerTokenStored;
        }
        return convictionPerTokenStored + (lastTimeRewardApplicable() - lastUpdateTime) * convictionRate * BASE_UNIT / super.totalSupply();
    }

    function convictionAccumulated(address account) public view returns (uint256) {
        return  super.balanceOf(account) * (convictionPerToken() - userConvictionPerTokenProvided[account]) / BASE_UNIT + convictions[account];
    }

    function fundConvictions(uint256 initialSystemConvictions) external updateConviction(address(0)) {
        require(initialSystemConvictions > 0, "ERC20Conviction: Invalid initialSystemConvictions");
        require(msg.sender == deployer, "ERC20Conviction: caller is not eligible to fund conviction");

        if (block.timestamp < periodFinish) {
            initialSystemConvictions += (periodFinish - block.timestamp) * convictionRate;
        }

        convictionRate = initialSystemConvictions / rewardDurationInSeconds;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardDurationInSeconds;
    }

    // Start acquiring conviction
    function startAcquireConviction() public nonReentrant updateConviction(msg.sender) {
        emit ConvictionAccumulationStarted(msg.sender);
    }

    // We compute the total of all conviction emission since the first time it started
    function getTotalAvailableConviction() public view override returns (uint256) {
        uint256 timeElapsed = block.timestamp - initialConvictionEmissionTime;
        uint256 totalConvictionEmitted = timeElapsed * convictionRate;
        return totalConvictionEmitted;
    }


    function isGovernance(address member) external override view returns (bool) {
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override virtual {
        super._beforeTokenTransfer(from, to, amount);
    }


    function getPriorConvictionScore(address user, uint256 blockNumber) public view virtual override returns (uint224) {
        return SafeCast.toUint224(convictionAccumulated(user));
    }

    function getConvictionScore(address user) public view override returns (uint224) {
        return SafeCast.toUint224(convictionAccumulated(user));
    }

    // TODO: Re-implement Conviction tokenization
    function tokenizeConviction(uint256 locked) external override returns (uint256) {
        if (locked > 0) {
            _transfer(msg.sender, address(fairSideConviction), locked);
        }

        uint256 score = getConvictionScore(msg.sender);
        require(score != 0 || locked != 0, "ERC20ConvictionScore::tokenizeConviction: Invalid tokenized conviction");

        //        _resetConviction(msg.sender);

        return fairSideConviction.createConvictionNFT(
            msg.sender,
            score,
            locked,
            true
        );
    }
}
