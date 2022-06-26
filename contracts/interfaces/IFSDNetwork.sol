// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IFSDNetwork {
    function getAdoptionStats() external view returns (uint256, uint256);
}
