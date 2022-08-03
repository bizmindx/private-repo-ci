// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

interface IFairSideDAO {
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas,
        string calldata description,
        bool forceOnchain
    ) external returns (uint256);

    function castVote(uint256 proposalId, bool support) external;
}
