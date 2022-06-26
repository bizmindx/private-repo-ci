// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IFSDVesting {
    function claimVestedTokens() external;

    function updateVestedTokens(uint256 _amount) external;
}
