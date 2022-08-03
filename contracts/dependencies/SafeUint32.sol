// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

library SafeUint32 {
    function safe32(
        uint256 n,
        string memory errorMessage
    ) internal pure returns (uint32) {
        require(n <= type(uint32).max, errorMessage);
        return uint32(n);
    }

    function safeSign(
        uint32 n,
        string memory errorMessage
    ) internal pure returns (int32) {
        require(n <= uint32(type(int32).max), errorMessage);
        return int32(n);
    }

    function add32(
        uint32 a,
        uint32 b,
        string memory errorMessage
    ) internal pure returns (uint32) {
        uint32 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function addSigned32(
        int32 a,
        int32 b,
        string memory error
    ) internal pure returns (int32) {
        int32 c = a + b;
        require(b > 0 ? c > a : c <= a, error); // Should never occur
        return c;
    }

    function sub32(
        uint32 a,
        uint32 b,
        string memory errorMessage
    ) internal pure returns (uint32) {
        uint32 c = a - b;
        require(c <= a, errorMessage);
        return c;
    }
}
