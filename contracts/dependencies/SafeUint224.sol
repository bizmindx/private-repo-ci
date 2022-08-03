// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

library SafeUint224 {
    function safe224(uint256 n, string memory errorMessage)
        internal
        pure
        returns (uint224)
    {
        require(n <= type(uint224).max, errorMessage);
        return uint224(n);
    }

    function safeSign(uint224 n, string memory errorMessage)
        internal
        pure
        returns (int224)
    {
        require(n <= uint224(type(int224).max), errorMessage);
        return int224(n);
    }

    function add224(
        uint224 a,
        uint224 b,
        string memory errorMessage
    ) internal pure returns (uint224) {
        uint224 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function addSigned224(
        int224 a,
        int224 b,
        string memory errorMessage
    ) internal pure returns (int224) {
        int224 c = a + b;
        require(b > 0 ? c > a : c <= a, errorMessage); // Should never occur
        return c;
    }

    function sub224(
        uint224 a,
        uint224 b,
        string memory errorMessage
    ) internal pure returns (uint224) {
        uint224 c = a - b;
        require(c <= a, errorMessage);
        return c;
    }
}
