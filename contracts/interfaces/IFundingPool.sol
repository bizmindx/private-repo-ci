// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

interface IFundingPool {
    function funded() external view returns (bool);
}
