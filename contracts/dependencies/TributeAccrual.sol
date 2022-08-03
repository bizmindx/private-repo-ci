// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "../dependencies/SafeUint32.sol";
import "../dependencies/SafeUint224.sol";
import "../interfaces/IERC20ConvictionScore.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @dev Implementation of {TributeAccrual} contract.
 *
 * The TributeAccrual contract implements logic to keep accounting of
 * tribute amounts. The tributes are accrued as percentage fee deducted
 * when users withdraw their FSD for exiting the network.
 *
 * The accumulated tributes are distributed to the remaining users of
 * the FSD Network based on their conviction scores.
 *
 * Provides function to view and claim the claimable tribute amounts for users.
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
abstract contract TributeAccrual is IERC20ConvictionScore, ERC20Permit {
    /* ========== LIBRARIES ========== */

    using SafeMath for uint256;
    using SafeUint32 for *;
    using SafeUint224 for *;

    /* ========== STATE VARIABLES ========== */

    /**
     * @dev {Tribute} struct contains parameters for a tribute.
     * blockNumber: Block number at which tribute was added.
     * amount: Amount of FSD for distribution associated with tribute.
     * claimed: Mapping from `address` -> `bool` representing tribute
     * claimed status of an address.
     */
    struct Tribute {
        uint32 blockNumber;
        uint224 amount;
        mapping(address => bool) claimed;
    }

    // mapping of tribute id to tribute struct.
    mapping(uint256 => Tribute) internal tributes;

    // pending tributes waiting for approval.
    uint224 internal pendingTributes;

    // total number of tributes.
    uint256 internal totalTributes;

    // mapping of governance tribute id to governance tribute struct.
    mapping(uint256 => Tribute) internal governanceTributes;

    // pending governance tributes waiting for approval.
    uint224 internal pendingGovernanceTributes;

    // total number governance tributes.
    uint256 internal totalGovernanceTributes;

    // Address to signify snapshotted total conviction score and governance conviction score
    address internal constant TOTAL_CONVICTION_SCORE = address(0);
    address internal constant TOTAL_GOVERNANCE_SCORE =
        address(type(uint160).max);

    /* ========== EVENTS ========== */

    // Event emitted when a user claims its share from a tribute.
    event TributeClaimed(address indexed beneficiary, uint256 amount);
    // Event emitted when a user claims its share from a governance tribute.
    event GovernanceTributeClaimed(address indexed beneficiary, uint256 amount);

    /* ========== CONSTRUCTOR ========== */

    /* ========== VIEWS ========== */

    /**
     * @dev Returns total amount of FSD that are claimable by `msg.sender`
     * in all staking tributes and all governance tributes.
     */
    function totalAvailableTribute(uint256 offset)
        external
        view
        override
        returns (uint256 total)
    {
        uint256 _totalTributes = totalTributes;
        for (uint256 i = offset; i < _totalTributes; i++)
            total = total.add(availableTribute(i));

        uint256 _totalGovernanceTributes = totalGovernanceTributes;
        for (uint256 i = offset; i < _totalGovernanceTributes; i++)
            total = total.add(availableGovernanceTribute(i));
    }

    /**
     * @dev Returns tribute share of `msg.sender` in staking tribute represented by {num}.
     */
    function availableTribute(uint256 num)
        public
        view
        override
        returns (uint256)
    {
        Tribute storage tribute = tributes[num];

        if (tributes[num].claimed[msg.sender]) return 0;

        uint256 userCS = uint256(
            getPriorConvictionScore(msg.sender, tribute.blockNumber)
        );
        uint256 totalCS = uint256(
            getPriorConvictionScore(TOTAL_CONVICTION_SCORE, tribute.blockNumber)
        );
        uint256 amount = uint256(tribute.amount);

        return amount.mul(userCS).div(totalCS);
    }

    /**
     * @dev Returns tribute share of `msg.sender` in governance tribute represented by {num}.
     */
    function availableGovernanceTribute(uint256 num)
        public
        view
        override
        returns (uint256)
    {
        Tribute storage tribute = governanceTributes[num];

        if (governanceTributes[num].claimed[msg.sender]) return 0;

        uint256 userCS = uint256(
            getPriorConvictionScore(msg.sender, tribute.blockNumber)
        );
        uint256 totalCS = uint256(
            getPriorConvictionScore(TOTAL_GOVERNANCE_SCORE, tribute.blockNumber)
        );
        uint256 amount = uint256(tribute.amount);

        return amount.mul(userCS).div(totalCS);
    }

    function getPriorConvictionScore(address user, uint256 blockNumber)
        public
        view
        virtual
        override
        returns (uint224);

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows claiming of staking tribute by `msg.sender`.
     * It updates the claimed status of user against the tribute
     * being claimed.
     *
     * Requirements:
     * - claiming amount must not be 0.
     */
    function _claimTribute(uint256 num) internal {
        uint256 tribute = availableTribute(num);

        require(
            tribute != 0,
            "TributeAccrual::_claimTribute: No fees are claimable"
        );

        tributes[num].claimed[msg.sender] = true;

        _transfer(address(this), msg.sender, tribute);

        emit TributeClaimed(msg.sender, tribute);
    }

    /**
     * @dev Allows claiming of governance tribute by `msg.sender`.
     * It updates the claimed status of user against the tribute
     * being claimed.
     *
     * Requirements:
     * - claiming amount must not be 0.
     */
    function _claimGovernanceTribute(uint256 num) internal {
        uint256 tribute = availableGovernanceTribute(num);

        require(
            tribute != 0,
            "TributeAccrual::_claimGovernanceTribute: No fees are claimable"
        );

        governanceTributes[num].claimed[msg.sender] = true;

        _transfer(address(this), msg.sender, tribute);

        emit GovernanceTributeClaimed(msg.sender, tribute);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Increases the pending tributes.
     *
     * Requirements:
     * - reverts if tribute amount exceeds `uint224`.
     */
    function _registerTribute(uint256 tribute) internal {
        uint224 _tribute = tribute.safe224(
            "TributeAccrual::_registerTribute: Tribute overflow"
        );

        pendingTributes = pendingTributes.add224(
            _tribute,
            "TributeAccrual::_registerTribute: Tribute overflow"
        );
    }

    /**
     * @dev Increases the pending governance tributes.
     *
     * Requirements:
     * - reverts if tribute amount exceeds `uint224`.
     */
    function _registerGovernanceTribute(uint256 tribute) internal {
        uint224 _tribute = tribute.safe224(
            "TributeAccrual::_registerGovernanceTribute: Tribute overflow"
        );

        pendingGovernanceTributes = pendingGovernanceTributes.add224(
            _tribute,
            "TributeAccrual::_registerGovernanceTribute: Tribute overflow"
        );
    }

    /**
     * @dev Adds tribute amount to the {tributes} mapping against a
     * new tribute id.
     *
     * Tribute amounts added in the same block are stored against the same
     * block number.
     *
     * Requirements:
     * - reverts if tribute amount exceeds `uint224`.
     * - reverts if block.number exceeds `uint32`.
     */
    function _addTribute(uint256 tribute) internal {
        uint224 _tribute = tribute.safe224(
            "TributeAccrual::_addTribute: Tribute overflow"
        );

        Tribute storage lastTribute = tributes[totalTributes - 1];

        if (lastTribute.blockNumber == block.number) {
            lastTribute.amount = lastTribute.amount.add224(
                _tribute,
                "TributeAccrual::_addTribute: Addition of tributes overflow"
            );
        } else {
            Tribute storage newTribute = tributes[totalTributes++];
            newTribute.amount = _tribute;
            newTribute.blockNumber = block.number.safe32(
                "TributeAccrual::_addTribute: Block number overflow"
            );
        }

        pendingTributes = pendingTributes.sub224(
            _tribute,
            "TributeAccrual::_addTribute: Pending tribute underflow"
        );
    }

    /**
     * @dev Adds governance tribute amount to the {governanceTributes} mapping
     * against a new tribute id.
     *
     * Tribute amounts added in the same block are stored against the same
     * block number.
     *
     * Requirements:
     * - reverts if tribute amount exceeds `uint224`.
     * - reverts if block.number exceeds `uint32`.
     */
    function _addGovernanceTribute(uint256 tribute) internal {
        uint224 _tribute = tribute.safe224(
            "TributeAccrual::_addTribute: Tribute overflow"
        );

        Tribute storage lastTribute = governanceTributes[
            totalGovernanceTributes - 1
        ];

        if (lastTribute.blockNumber == block.number) {
            lastTribute.amount = lastTribute.amount.add224(
                _tribute,
                "TributeAccrual::_addTribute: Addition of tributes overflow"
            );
        } else {
            Tribute storage newTribute = governanceTributes[
                totalGovernanceTributes++
            ];
            newTribute.amount = _tribute;
            newTribute.blockNumber = block.number.safe32(
                "TributeAccrual::_addTribute: Block number overflow"
            );
        }

        pendingGovernanceTributes = pendingGovernanceTributes.sub224(
            _tribute,
            "TributeAccrual::_addGovernanceTribute: Pending tribute underflow"
        );
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
