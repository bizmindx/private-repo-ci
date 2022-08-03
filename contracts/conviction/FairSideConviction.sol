// SPDX-License-Identifier: Unlicense

import "../dependencies/SafeUint224.sol";
import "../interfaces/IERC20ConvictionScore.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../dependencies/DSMath.sol";

import "../interfaces/IFairSideConviction.sol";

pragma solidity 0.8.3;

/**
 * @dev Implementation of {FairSideConviction} contract.
 *
 * The FairSideConviction contract allows exiting of FSD network by locking in
 * the FSD amount and conviction score of the user and minting a {ConvictionNFT} against it.
 *
 * The minted NFT continues to accrue conviction score but these are not applied
 * towards total governance score.
 *
 * When an NFT is burned, its conviction score is combined with the user's conviction
 * score and correspondingly adjusts their governance eligibility.
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract FairSideConviction is ERC721, IFairSideConviction {
    /* ========== LIBRARIES ========== */

    using SafeERC20 for IERC20;
    using SafeUint224 for *;

    /* ========== STATE VARIABLES ========== */

    /**
     * @dev {ConvictionScore} struct contains properties for a conviction NFT.
     *
     * ts: Timestamp when the NFT is minted.
     * score: Continuously accruing conviction score of the NFT.
     * locked: Locked FSD token amount against the NFT.
     * isGovernance: Flag representing if the NFT minting user is part of Governance committee.
     */
    struct ConvictionScore {
        uint256 ts;
        uint256 score;
        uint256 locked;
        bool isGovernance;
    }

    // The NFT properties against the token id.
    mapping(uint256 => ConvictionScore) public conviction;

    // The last minted token's id.
    uint256 private _tokenId = 1;

    // Instance of FSD contract.
    IERC20 public immutable FSD;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev It initialises the contract's state setting the value for FSD instance
     * and also passes symbol and name to the constructor of {ERC721} contract that
     * is inherited in the current contract.
     */
    constructor(IERC20 _fsd) public ERC721("FairSide Conviction", "FSC") {
        FSD = _fsd;
    }

    /* ========== VIEWS ========== */

    /**
     @dev Returns the latest accrued amount of conviction score against the NFT
     * represented by {id}.
     */
    function getConvictionScore(uint256 id)
        public
        view
        returns (uint256 convictionScore)
    {
        ConvictionScore memory cs = conviction[id];

        convictionScore = cs.score;

        if (cs.locked != 0 && cs.score >= uint256(IERC20ConvictionScore(address(FSD)).minimumBalance()))
            convictionScore = convictionScore + (
                cs.locked * (block.timestamp - cs.ts) / 1 days
            );
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Mints an NFT token and stores the received properties for the NFT
     * by token id in {conviction} mapping.
     *
     * Requirements:
     * - only FSD contract can call this function
     */
    function createConvictionNFT(
        address user,
        uint256 score,
        uint256 locked,
        bool isGovernance
    ) external override returns (uint256) {
        require(
            msg.sender == address(FSD),
            "FairSideConviction::createConvictionNFT: Insufficient Privileges"
        );
        uint256 id = _tokenId++;

        ConvictionScore storage cs = conviction[id];

        cs.score = score;
        cs.ts = block.timestamp;
        cs.isGovernance = isGovernance;
        cs.locked = locked;

        _mint(user, id);

        return id;
    }

    /**
     * @dev Burns NFT token against the {id} and releases the locked FSD
     * amount against NFT back to the FSD contract. It also deleted the
     * NFT entry in the {conviction} mapping.
     *
     * It internally calls `_release` function.
     *
     * Requirements:
     * - only FSD contract can call this function
     * - the parameter {from} should be the owner of the NFT being burned
     */
    function burn(address from, uint256 id)
        external
        override
        returns (
            uint224 convictionScore,
            uint256 released,
            bool wasGovernance
        )
    {
        require(
            msg.sender == address(FSD),
            "FairSideConviction::burn: Insufficient Privileges"
        );
        require(from == ownerOf(id), "FairSideConviction::burn: NFT not owned");
        (convictionScore, released) = _release(id);
        _burn(id);
        wasGovernance = conviction[id].isGovernance;
        delete conviction[id];
    }

    /**
     * @dev Releases the locked amount of FSD associated with NFT against {id}.
     *
     * * It internally calls `_release` function.
     *
     * Requirements:
     * - only callable by the owner of token
     */
    function release(uint256 id) external returns (uint256, uint256) {
        require(
            msg.sender == ownerOf(id),
            "FairSideConviction::release: Insufficient Privileges"
        );
        return _release(id);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Releases the locked FSD amount associated with NFT against {id}.
     * It also updates the properties of NFT in conviction mapping, setting
     * released, locked and conviction score amounts.
     *
     * Requirements:
     * - reverts if conviction score overflows uint224
     */
    function _release(uint256 id)
        internal
        returns (uint224 convictionScore, uint256 released)
    {
        ConvictionScore storage cs = conviction[id];

        if (cs.locked == 0)
            return (
                cs.score.safe224(
                    "FairSideConviction::_release: Conviction Overflow"
                ),
                0
            );

        convictionScore = getConvictionScore(id).safe224(
            "FairSideConviction::_release: Conviction Overflow"
        );

        cs.score = uint256(convictionScore);
        released = cs.locked;
        cs.locked = 0;
        FSD.safeTransfer(ownerOf(id), released);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
