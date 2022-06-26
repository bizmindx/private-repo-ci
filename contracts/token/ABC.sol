// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "../dependencies/DSMath.sol";
import "../dependencies/FairSideFormula.sol";

/**
 * @dev Implementation of Augmented Bonding Curve (ABC) contract.
 *
 * Attributes:
 * - Calculates amount of FSD to be minted given a particular token supply and an amount of reserve
 * - Calculates amount of reserve to be unlocked given a particular token supply and an amount of FSD tokens
 * - Tracks creations and timestamps
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract ABC {
    /* ========== LIBRARIES ========== */

    using DSMath for uint256;

    /* ========== STATE VARIABLES ========== */

    /**
     * @dev The factor used to adjust maximum Cost Share Benefits the network
     * can offer in relation to its Capital Pool of funds in ETH. (initial Gearing factor = 10)
     */
    uint256 public gearingFactor = 1000;

    /* ========== EVENTS ========== */

    /* ========== CONSTRUCTOR ========== */

    /* ========== VIEWS ========== */

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ========== RESTRICTED FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    // Returns absolute value of the parameter {a}.
    function _abs(int256 a) internal pure returns (uint256) {
        return uint256(a < 0 ? -a : a);
    }

    /**
     * @dev Returns the delta amount representing change in the supply of FSD token
     * supply after the change in reserve amount is considered.
     *
     * Requirement:
     * - the reserve amount should not go below {Fshare}.
     */
    function _calculateDeltaOfFSD(
        uint256 _reserve,
        int256 _reserveDelta,
        uint256 _openRequests,
        uint256 _availableCSB
    ) internal view returns (uint256) {
        // FSHARE = Total Available Cost Share Benefits / Gearing Factor
        uint256 fShare = _availableCSB.mul(100) / gearingFactor;
        // Floor of 4000 ETH
        if (fShare < 4000 ether) fShare = 4000 ether;

        // Capital Pool = Total Funds held in ETH – Open Cost Share Requests
        // Open Cost Share Request = Cost share request awaiting assessor consensus
        uint256 capitalPool = _reserve - _openRequests;

        uint256 currentSupply = FairSideFormula.g(capitalPool, fShare);

        uint256 nextSupply;
        if (_reserveDelta < 0) {
            uint256 capitalPostWithdrawal = capitalPool.sub(
                _abs(_reserveDelta)
            );
            require(
                capitalPostWithdrawal >= fShare,
                "ABC::_calculateDeltaOfFSD: Insufficient Capital to Withdraw"
            );
            nextSupply = FairSideFormula.g(capitalPostWithdrawal, fShare);
        } else {
            nextSupply = FairSideFormula.g(
                capitalPool.add(uint256(_reserveDelta)),
                fShare
            );
        }

        return
            _reserveDelta < 0
                ? currentSupply.sub(nextSupply)
                : nextSupply.sub(currentSupply);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
