// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

interface IFSDVestingFactory {
    function createVestingPRE(address beneficiary, uint256 amount)
        external
        returns (address);

    function createVestingVC(address beneficiary, uint256 amount)
        external
        returns (address);

    function createVestingKOL(address beneficiary, uint256 amount)
        external
        returns (address);
}
