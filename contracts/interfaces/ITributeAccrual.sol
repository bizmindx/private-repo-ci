// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITributeAccrual is IERC20 {
    function totalAvailableTribute(uint256 offset)
        external
        view
        returns (uint256 total);

    function availableTribute(uint256 num) external view returns (uint256);

    function availableGovernanceTribute(uint256 num)
        external
        view
        returns (uint256);
}
