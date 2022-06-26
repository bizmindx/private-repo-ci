// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "./ITributeAccrual.sol";

interface IERC20ConvictionScore is ITributeAccrual {
    function getPriorConvictionScore(address user, uint256 blockNumber)
        external
        view
        returns (uint224);

    function governanceThreshold() external view returns (uint256);

    function isGovernance(address member) external view returns (bool);

    function minimumBalance() external view returns (int256);

    function tokenizeConviction(uint256 locked) external returns (uint256);

    function claimAvailableTributes(uint256 num) external;

    function registerTribute(uint256 num) external;

    function registerGovernanceTribute(uint256 num) external;

    // function claimTribute(uint256 num) external;

    // function claimGovernanceTribute(uint256 num) external;
}
