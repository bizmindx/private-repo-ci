// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IFSDMinter {
    function mintToCWL(address to, bytes calldata sig, uint256 tokenMinimum) external payable;

    function mintToFinal(address to, uint256 tokenMinimum) external payable;
}