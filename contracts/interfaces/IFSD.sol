// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IFSD {
    /**
     * @dev Phases of the FSD token.
     * Premine: Token pre-mine
     * KOL: KOL token pre-mine
     * VCWL: Venture Capital white-list
     * CWL: Community white-list
     * Final: Curve indefinitely open
     */
    enum Phase {
        Premine,
        KOL,
        VCWL,
        CWL,
        Final
    }

    function currentPhase() external returns (Phase);

    function getTokensMinted(uint256 investment)
        external
        view
        returns (uint256);

    function payClaim(
        address beneficiary,
        uint256 amount,
        bool inStable
    ) external;

    function liquidateEth(uint256 amount, uint256 min)
        external
        returns (uint256);

    function liquidateDai(uint256 amount, uint256 min) external;

    function mint(address to, uint256 tokenMinimum)
        external
        payable
        returns (uint256);

    function mintDirect(address to, uint256 amount) external;
}
