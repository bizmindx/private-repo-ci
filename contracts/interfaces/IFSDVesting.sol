// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

interface IFSDVesting {
    function claimVestedTokens() external;

    function updateVestedTokens(uint256 _amount) external;
}
