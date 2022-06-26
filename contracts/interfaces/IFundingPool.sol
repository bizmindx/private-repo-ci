// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IFundingPool {
    function funded() external view returns (bool);
}
