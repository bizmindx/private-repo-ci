// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

interface IFSDNetwork {
    function getAdoptionStats() external view returns (uint256, uint256);
}
