// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/utils/Address.sol";
import "./DSMath.sol";

/**
 * @dev Implementation of {Withdrawable} contract.
 *
 * The Withdrawable contract allows assigning withdrawable ETH amounts
 * to users that they can later withdraw using the {withdraw} function.
 *
 * This contract is used in the inheritance chain of FSD contract and
 * the amounts withdrawable through {withdraw} function are the ETH
 * amounts available to user either after burning FSD tokens or when
 * the Cost Share Request(CSR) of the user is approved and the payout
 * is in ETH.
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract Withdrawable {
    /* ========== LIBRARIES ========== */

    using DSMath for uint256;
    using Address for address payable;

    /* ========== STATE VARIABLES ========== */

    // Prevent re-entrancy in burn

    // mapping of user to withdrawable amount.
    mapping(address => uint256) public availableWithdrawal;

    // total withdrawable amount for all users in ETH.
    uint256 public pendingWithdrawals;

    /* ========== EVENTS ========== */

    /* ========== CONSTRUCTOR ========== */

    /* ========== VIEWS ========== */

    /**
     * @dev Returns available ETH balance minus pending withdraws.
     */
    function getReserveBalance() public view returns (uint256) {
        return address(this).balance.sub(pendingWithdrawals);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows withdrawing of ETH claimable amount by `msg.sender`.
     * Updates the user's available withdrawal amount and the total
     * pending claimable amount.
     */
    function withdraw() external {
        uint256 reserveAmount = availableWithdrawal[msg.sender];
        require(reserveAmount > 0, "FSD::withdraw: Insufficient Withdrawal");
        delete availableWithdrawal[msg.sender];
        pendingWithdrawals = pendingWithdrawals.sub(reserveAmount);
        msg.sender.sendValue(reserveAmount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Increases withdrawable amount for a user.
     * Updates the user's available withdrawal amount and the total
     * pending claimable amount.
     */
    function _increaseWithdrawal(address user, uint256 amount) internal {
        availableWithdrawal[user] = availableWithdrawal[user].add(amount);
        pendingWithdrawals = pendingWithdrawals.add(amount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
