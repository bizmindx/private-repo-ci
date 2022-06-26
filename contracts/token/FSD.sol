// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../dependencies/ERC20ConvictionScore.sol";
import "../dependencies/Withdrawable.sol";
import "../dependencies/DSMath.sol";
import "../dependencies/FSOwnable.sol";
import "../interfaces/IFSDNetwork.sol";
import "../interfaces/IFSDVesting.sol";
import "../interfaces/IFSDVestingFactory.sol";
import "../interfaces/IFSD.sol";
import "./ABC.sol";

/**
 * @dev Implementation {FSD} ERC20 Token contract.
 *
 * The FSD contract allows depositing of ETH for bonding to curve and minting
 * FSD in return. Only 70% of the deposit is bonded to curve during VCWL phase
 * and the rest 30% is deposited to `fundingPool`.
 *
 * It also allows burning of FSD tokens to withdraw ETH. A portion of withdrawing ETH
 * reserve is taken as tribute fee which is distributed to existing network users on
 * the basis of their conviction scores.
 *
 * Has utility functions to modify the contract's state.
 *
 * Attributes:
 * - Mintable via an Augmented Bonding Curve
 * - Burnable via an Agumented Bonding Curve
 * - Tracks creations and timestamps
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract FSD is FSOwnable, ABC, ERC20ConvictionScore, Withdrawable, IFSD {
    /* ========== LIBRARIES ========== */

    using DSMath for uint256;
    using Address for address payable;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // 70% bonding curve ratio
    uint256 private constant BONDING_CURVE_RATIO = 0.7 ether;
    // Uniswap Router
    IUniswapV2Router02 private constant ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // DAI
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // WETH
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Funding pool needs to achieve 500 ether
    address public immutable fundingPool;
    // Timelock address
    address public immutable timelock;
    // FSD Network address
    IFSDNetwork public fsdNetwork;
    // FSD minter contract address
    address public minter;
    // currect phase of the FSD token
    Phase public override currentPhase;
    // Indicator of token tranfer pause
    bool public paused;
    // 3.5% tribute fee on exit
    uint256 private tributeFee = 0.035 ether;

    /* ========== EVENTS ========== */

    /**
     * @dev Emitted when the pause functionality is triggered.
     */
    event PauseToggled();

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initialises the contract's state with {fundingPool} and {timelock} addresses.
     * It also passes token name and symbol to {ERC20ConvictionScore} contract and
     * the name to the Permit extension.
     */
    constructor(address _fundingPool, address _timelock)
        public
        ERC20Permit("FSD")
        ERC20ConvictionScore("FairSide Token", "FSD")
    {
        fundingPool = _fundingPool;
        timelock = _timelock;
    }

    /**
     * @dev receive functions for ETH
     */
    // solhint-disable-next-line
    receive() external payable {}

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the amount of FSD available for minting after
     * reserve is increased by delta.
     */
    function getTokensMinted(uint256 investment)
        external
        view
        override
        returns (uint256)
    {
        return calculateDeltaOfFSD(getReserveBalance(), int256(investment));
    }

    /**
     * @dev Returns the amount of FSD available for burning after
     * reserve is decreased by delta.
     */
    function getTokensBurned(uint256 withdrawal)
        external
        view
        returns (uint256)
    {
        return calculateDeltaOfFSD(getReserveBalance(), -int256(withdrawal));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the Final phase, 100% of the deposited ETH are bonded.
     *
     * Requirements:
     * - bonding ETH amount cannot be zero
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     */
    function mint(address to, uint256 tokenMinimum)
        external
        payable
        override
        onlyMinterOrNetwork
        returns (uint256)
    {
        require(msg.value != 0, "FSD::mint: Deposit amount cannot be zero");

        return _mintInternal(to, tokenMinimum);
    }

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the Final phase, 100% of the deposited ETH are bonded.
     *
     * Requirements:
     * - bonding ETH amount cannot be zero
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     */
    function mintDirect(address to, uint256 amount)
        external
        override
        onlyMinter
    {
        require(
            currentPhase == Phase.Premine || currentPhase == Phase.KOL,
            "FSD::mintTo: Invalid Phase"
        );

        // if (amount >= uint256(governanceMinimumBalance)) {
        //     _bestowGovernanceStatus(to);
        // }

        _mint(to, amount);
    }

    /**
     * @dev Allows burning of FSD tokens for ETH that are withdrawable through
     * {Withdrawable::withdraw} function.
     * It also takes cut of {tributeFee} and adds it as tribute which is distributed
     * to the existing users of the network based on their conviction scores.
     *
     * Requirements:
     * - the FSD token amount being burned must not exceed parameter {tokenMaximum}
     */
    function burn(uint256 capitalDesired, uint256 tokenMaximum) external {
        require(currentPhase == Phase.Final, "FSD::burn: Invalid Phase");

        uint256 etherBalanceAtBurn = getReserveBalance();

        uint256 tokenAmount = calculateDeltaOfFSD(
            etherBalanceAtBurn,
            -int256(capitalDesired)
        );

        require(tokenAmount <= tokenMaximum, "FSD::burn: High Slippage");

        _burn(msg.sender, tokenAmount);

        // See: https://github.com/dapphub/ds-math#wmul
        uint256 tribute = capitalDesired.wmul(tributeFee);
        uint256 reserveWithdrawn = capitalDesired - tribute;

        (uint256 totalOpenReq, ) = fsdNetwork.getAdoptionStats();
        require(
            reserveWithdrawn <=
                (etherBalanceAtBurn - totalOpenReq).wmul(0.01 ether),
            "FSD::burn: Withdraw exceeds 1% of the capital pool"
        );

        _increaseWithdrawal(msg.sender, reserveWithdrawn);

        uint256 mintAmount = calculateDeltaOfFSD(
            etherBalanceAtBurn - reserveWithdrawn,
            int256(tribute)
        );

        _mint(address(this), mintAmount);
        _addTribute(mintAmount);
    }

    /**
     * @dev Allows claiming of all available tributes represented by param {num}.
     * It internally calls `_claimTribute` & `_claimGovernanceTribute`.
     *
     */
    function claimAvailableTributes(uint256 num) external override {
        _claimTribute(num);
        if (
            isGovernance[msg.sender] &&
            governanceThreshold <=
            getPriorConvictionScore(
                msg.sender,
                governanceTributes[num].blockNumber
            )
        ) _claimGovernanceTribute(num);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function phaseAdvance() external onlyOwner {
        require(
            currentPhase != Phase.Final,
            "FSD::phaseAdvance: FSD is already at its final phase"
        );
        currentPhase = Phase(uint8(currentPhase) + 1);
    }

    /**
     * @dev Allows claiming of all available tributes represented by param {num}.
     * It internally calls `_claimTribute` & `_claimGovernanceTribute`.
     *
     */
    function registerTribute(uint256 registrationTribute)
        external
        override
        onlyFSD
    {
        _registerTribute(registrationTribute);
    }

    /**
     * @dev Allows claiming of all available tributes represented by param {num}.
     * It internally calls `_claimTribute` & `_claimGovernanceTribute`.
     *
     */
    function registerGovernanceTribute(uint256 registrationTribute)
        external
        override
        onlyFSD
    {
        _registerGovernanceTribute(registrationTribute);
    }

    /**
     * @dev Adds staking rewards tribute gathered upon registration which is distributed
     * to the existing users of the network based on their conviction scores.
     *
     * Requirements:
     * - only {fsdNetwork} can call this function
     */
    function addRegistrationTribute(uint256 registrationTribute)
        external
        onlyOwner
    {
        _addTribute(registrationTribute);
    }

    /**
     * @dev Adds governance rewards tribute gathered upon registration which is distributed
     * to the existing users of the network based on their conviction scores.
     *
     * Requirements:
     * - only {fsdNetwork} can call this function
     */
    function addRegistrationTributeGovernance(uint256 registrationTribute)
        external
        onlyOwner
    {
        _addGovernanceTribute(registrationTribute);
    }

    /**
     * @dev Allows paying of claims upon processing of Cost Share Requests.
     * It pays claims in DAI when parameter {inStable} in true and otherwise perform
     * account for later withdrawal of ETH by the {beneficiary}.
     *
     * Requirements:
     * - only callable by FSD contract.
     */
    function payClaim(
        address beneficiary,
        uint256 amount,
        bool inStable
    ) external override onlyFSD {
        if (inStable) {
            IERC20(DAI).safeTransfer(beneficiary, amount);
        } else {
            _increaseWithdrawal(beneficiary, amount);
        }
    }

    /**
     * @dev Liquidates ETH to DAI through Uniswap AMM and returns the converted
     * DAI amount.
     *
     * Requirements:
     * - only FSD contract can call this function.
     * - the amount of DAI received after conversion must be greater or equal to param {min}
     */
    function liquidateEth(uint256 amount, uint256 min)
        external
        override
        onlyFSD
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;
        uint256[] memory amounts = ROUTER.swapExactETHForTokens{value: amount}(
            min,
            path,
            address(this),
            block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    /**
     * @dev Liquidates DAI to ETH through Uniswap AMM.
     *
     * Requirements:
     * - only FSD contract can call this function.
     * - the amount of ETH received after conversion must be greater or equal to param {min}
     */
    function liquidateDai(uint256 amount, uint256 min)
        external
        override
        onlyFSD
    {
        IERC20(DAI).approve(address(ROUTER), amount);

        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;
        ROUTER.swapExactTokensForETH(
            amount,
            min,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Sets the gearing factor of the FSD formula.
     *
     * Requirements:
     * - only FSD contract can call this function.
     * - gearing factor must be more than zero.
     */
    function setGearingFactor(uint256 _gearingFactor) external onlyFSD {
        gearingFactor = _gearingFactor;
    }

    /**
     * @dev Renounces the contract's ownership by setting {owner} to address(0)
     * leaving the contract permanently without an owner.
     *
     * Requirements:
     * - only callable by {owner} or {timelock} contract.
     */
    function abdicate() external onlyTimelockOrOwner {
        _renounceOwnership();
    }

    /**
     * @dev Allows updating of governance threshold.
     *
     * Requirements:
     * - only callable by {owner} or {timelock} contract.
     */
    function updateGovernanceThreshold(uint256 _governanceThreshold)
        external
        onlyTimelockOrOwner
    {
        governanceThreshold = _governanceThreshold;
    }

    /**
     * @dev Allows updating of governance minimum balance.
     *
     * Requirements:
     * - only callable by {owner} or {timelock} contract.
     */
    function updateGovernanceMinimumBalance(int256 _governanceMinimumBalance)
        external
        onlyTimelockOrOwner
    {
        governanceMinimumBalance = _governanceMinimumBalance;
    }

    /**
     * @dev Allows updating of FSD minimum balance to acquire Conviction Score.
     *
     * Requirements:
     * - only callable by {owner} or {timelock} contract.
     */
    function updateminimumBalance(int256 _minimumBalance)
        external
        onlyTimelockOrOwner
    {
        minimumBalance = _minimumBalance;
    }

    /**
     * @dev Allows setting convictionless status of the {user}.
     * It also resets the conviction if it is already set.
     *
     * Requirements:
     * - only callable by {owner} or {timelock} contract.
     */
    function setConvictionless(address user, bool isConvictionless)
        external
        onlyTimelockOrOwner
    {
        convictionless[user] = isConvictionless;

        if (getPriorConvictionScore(user, block.number - 1) != 0) {
            _resetConviction(user);
        }
    }

    /**
     * @dev Sets membership fee.
     *
     * Requirements:
     * - only callable by governance or timelock contracts.
     */
    function setTributeFee(uint256 _tributeFee) external onlyTimelockOrOwner {
        tributeFee = _tributeFee;
    }

    /**
     * @dev Allows updating of {FairSideConviction} address. Invocable only once.
     *
     * Requirements:
     * - only callable by {owner} contract
     * - the param {_fairSideConviction} cannot be a zero address value
     */
    function setFairSideConviction(address _fairSideConviction)
        external
        onlyOwner
    {
        require(
            fairSideConviction == IFairSideConviction(0),
            "FSD::setFairSideConviction: Already Set!"
        );
        fairSideConviction = IFairSideConviction(_fairSideConviction);
        convictionless[_fairSideConviction] = true;
    }

    /**
     * @dev Allows updating of {_fsdNetwork} address. Invocable only once.
     *
     * Requirements:
     * - only callable by {owner} contract
     * - the param {_fsdNetwork} cannot be a zero address value
     */
    function setFairSideNetwork(IFSDNetwork _fsdNetwork) external onlyOwner {
        require(
            fsdNetwork == IFSDNetwork(0),
            "FSD::setFairSideNetwork: Already Set!"
        );
        fsdNetwork = _fsdNetwork;
    }

    /**
     * @dev Allows updating of {minter} address. Invocable only once.
     *
     * Requirements:
     * - only callable by {owner} contract
     * - the param {_minter} cannot be a zero address value
     */
    function setMinter(address _minter) external onlyOwner {
        require(
            _minter != address(0),
            "Vesting::setMinter: Cannot be the zero address"
        );
        require(minter == address(0), "Vesting::setMinter: Already set");
        minter = _minter;
        convictionless[address(minter)] = true;
    }

    /**
     * @dev Allows pausing token transfers.
     *
     * Requirements:
     * - only callable by {owner} contract
     */
    function togglePause() external onlyOwner {
        paused = !paused;
        emit PauseToggled();
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * ABC wrapper, returns the change in FSD supply upon
     * the total reserves and change in reserves.
     */
    function calculateDeltaOfFSD(uint256 _reserve, int256 _reserveDelta)
        internal
        view
        returns (uint256)
    {
        (
            uint256 openRequestsInEth,
            uint256 availableCostShareBenefits
        ) = fsdNetwork.getAdoptionStats();
        return
            _calculateDeltaOfFSD(
                _reserve,
                _reserveDelta,
                openRequestsInEth,
                availableCostShareBenefits
            );
    }

    function _mintInternal(address to, uint256 tokenMinimum)
        private
        returns (uint256)
    {
        uint256 bonded = msg.value;
        uint256 mintAmount = calculateDeltaOfFSD(
            getReserveBalance() - msg.value,
            int256(bonded)
        );

        require(mintAmount >= tokenMinimum, "FSD:: High Slippage");

        // if (mintAmount >= uint256(governanceMinimumBalance)) {
        //     _bestowGovernanceStatus(to);
        // }

        _mint(to, mintAmount);

        if (fundingPool.balance < 500 ether) {
            // See: https://github.com/dapphub/ds-math#wmul
            bonded = bonded.wmul(BONDING_CURVE_RATIO);

            uint256 maxAllowedInFundingPool = 500 ether - fundingPool.balance;
            uint256 amountAfterBonding = msg.value - bonded;

            uint256 toFundingPool = amountAfterBonding > maxAllowedInFundingPool
                ? maxAllowedInFundingPool
                : amountAfterBonding;

            payable(fundingPool).sendValue(toFundingPool);
        }

        return mintAmount;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _onlyTimelockOrOwner() private view {
        require(
            msg.sender == timelock || msg.sender == owner(),
            "FSD:: only Timelock or Owner can call"
        );
    }

    function _onlyFSD() private view {
        require(msg.sender == address(fsdNetwork), "FSD:: only FSD can call");
    }

    function _onlyMinter() private view {
        require(msg.sender == minter, "FSD:: only FSD minter can call");
    }

    function _onlyMinterOrNetwork() private view {
        require(
            msg.sender == minter || msg.sender == address(fsdNetwork),
            "FSD:: only FSD minter or network can call"
        );
    }

    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - the contract must not be paused.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        ERC20ConvictionScore._beforeTokenTransfer(from, to, amount);

        require(!paused, "FSD: token transfer while paused");
    }

    /* ========== MODIFIERS ========== */

    modifier onlyTimelockOrOwner() {
        _onlyTimelockOrOwner();
        _;
    }

    modifier onlyFSD() {
        _onlyFSD();
        _;
    }

    modifier onlyMinter() {
        _onlyMinter();
        _;
    }

    modifier onlyMinterOrNetwork() {
        _onlyMinterOrNetwork();
        _;
    }

    // /**
    //  * @dev Allows claiming of tribute represented by param {num}.
    //  * It internally calls `_claimGovernanceTribute`.
    //  *
    //  * Requirements:
    //  * - `msg.sender` should have governance status
    //  * - `msg.sender`'s conviction score must be greater or equal to {governanceThreshold}
    //  */
    // function claimGovernanceTribute(uint256 num) external override {
    //     require(
    //         isGovernance[msg.sender] &&
    //             governanceThreshold <=
    //             getPriorConvictionScore(
    //                 msg.sender,
    //                 governanceTributes[num].blockNumber
    //             ),
    //         "FSD::claimGovernanceTribute: Not a governance member"
    //     );
    //     _claimGovernanceTribute(num);
    // }
}
