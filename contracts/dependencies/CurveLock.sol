// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "./TributeAccrual.sol";

/**
 * @dev Implementation of {CurveLock} contract.
 *
 * The contract enables locking the transfer of FSD in the same block
 * as it is minted or burned.
 *
 * This contract lies in inheritance chain of FSD contract.
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
abstract contract CurveLock is TributeAccrual {
    /* ========== STATE VARIABLES ========== */

    // mapping of user to locking block number.
    mapping(address => uint256) internal _curveBlock;

    /* ========== CONSTRUCTOR ========== */

    /* ========== VIEWS ========== */

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ========== RESTRICTED FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev A hook function that is executed upon transfer, mint and burn of tokens.
     *
     * It enables to disallow user performing FSD transfers within the same block as they
     * enter or exit the FSD system.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        ERC20._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            require(
                _curveBlock[to] < block.number,
                "CurveLock::_beforeTokenTransfer: Cannot transfer after a mint/burn"
            );
            _curveBlock[to] = block.number;
        } else {
            require(
                _curveBlock[from] < block.number,
                "CurveLock::_beforeTokenTransfer: Cannot transfer after a mint/burn"
            );
            if (to == address(0)) {
                _curveBlock[from] = block.number;
            }
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
