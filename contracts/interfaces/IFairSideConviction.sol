// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IFairSideConviction {
    function createConvictionNFT(
        address,
        uint256,
        uint256,
        bool
    ) external returns (uint256);

    function burn(address, uint256)
        external
        returns (
            uint224,
            uint256,
            bool
        );
}
