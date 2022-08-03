// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IFSDMinter.sol";

/**
 * @dev Implementation {Zapper} ERC20 tokens contract.
 *
 * The Zapper contract allows using ERC-20 tokens to mint FSD ones
 * instead of ETH via 1inch.
 *
 * Attributes:
 * - receives the user's preferred ERC-20 token to mint FSD
 * - receives ETH only from 1inch's router
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract Zapper {
    using SafeERC20 for IERC20;
    using Address for address;

    IFSDMinter private immutable MINTER;

    constructor(IFSDMinter _minter) public {
        MINTER = _minter;
    }

    // solhint-disable-next-line
    receive() external payable {}

    /**
     * @dev Allows using ERC-20 tokens to mint FSD ones instead of ETH
     *
     * Requirements:
     * - the FSD token must be during its Community whitelist phase
     * - the user should approve the contract before initiating the swap
     * - the FSD token amount being minted must not exceed parameter {tokenMaximum}
     */
    function swapFromTokenCWL(
        address tokenAddr,
        uint256 amount,
        uint256 tokenMinimum,
        address dex,
        bytes memory sig,
        bytes memory data
    ) public returns (bool) {
        require(data.length > 0, "Zapper::swapFromToken: Wrong input");

        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(tokenAddr).approve(dex, amount);

        dex.functionCall(data);

        MINTER.mintToCWL{value: address(this).balance}(
            msg.sender,
            sig,
            tokenMinimum
        );

        return true;
    }

    /**
     * @dev Allows using ERC-20 tokens to mint FSD ones instead of ETH
     *
     * Requirements:
     * - the FSD token must be during its Final phase
     * - the user should approve the contract before initiating the swap
     * - the FSD token amount being minted must not exceed parameter {tokenMaximum}
     */
    function swapFromTokenFinal(
        address tokenAddr,
        uint256 amount,
        uint256 tokenMinimum,
        address dex,
        bytes memory data
    ) public returns (bool) {
        require(data.length > 0, "Zapper::swapFromToken: Wrong input");

        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(tokenAddr).approve(dex, amount);

        dex.functionCall(data);

        MINTER.mintToFinal{value: address(this).balance}(
            msg.sender,
            tokenMinimum
        );

        return true;
    }
}
