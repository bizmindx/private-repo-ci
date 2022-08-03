// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

/**
 * @dev Implementation of {SignatureWhitelist} contract.
 *
 * The SignatureWhitelist contract allows whitelisting of users to
 * enable them to participate in FSD token during `hatch` phase.
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract SignatureWhitelist is EIP712 {
    /* ========== LIBRARIES ========== */

    /* ========== STATE VARIABLES ========== */
    // Retain the list of whitelisted users
    mapping(address => bool) public whitelisted;
    // EIP712 Action
    bytes32 private constant WHITELIST_ACTION =
        keccak256("Whitelist(address user)");

    // The party responsible for signing the whitelist
    address private immutable WHITELIST_SIGNER;

    /* ========== EVENTS ========== */

    /* ========== CONSTRUCTOR ========== */

    // Initialises contract's state with signer.
    constructor(address signer) public EIP712("FSD", "v1.0.0") {
        WHITELIST_SIGNER = signer;
    }

    /* ========== VIEWS ========== */

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ========== RESTRICTED FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Returns the whitelisted status of the user.
     * If the user is not already whitelisted then it retrieves
     * the parameter {sig} signer and compares it to the state
     * variable {WHITELIST_SIGNER}, the success of which determines
     * the whitelist status of the user and that status is stored in
     * {whitelisted} mapping.
     */
    function _whitelist(bytes memory sig, address user)
        internal
        returns (bool isWhitelisted)
    {
        if (whitelisted[user]) return true;

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(WHITELIST_ACTION, user))
        );

        if (ECDSA.recover(digest, sig) == WHITELIST_SIGNER) {
            whitelisted[user] = isWhitelisted = true;
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
