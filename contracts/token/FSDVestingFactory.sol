// SPDX-License-Identifier: Unlicense

import "@openzeppelin/contracts/proxy/Clones.sol";
import "../interfaces/IFSDVestingFactory.sol";
import "./FSDVestingPRE.sol";
import "./FSDVestingVC.sol";
import "./FSDVestingKOL.sol";
import "../dependencies/FSOwnable.sol";

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

/**
 * FSD Vesting Factory
 *
 * Attributes:
 * - Allows for universal vesting start
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract FSDVestingFactory is FSOwnable, IFSDVestingFactory {
    /* ========== LIBRARIES ========== */

    using Clones for address;

    /* ========== STATE VARIABLES ========== */

    // FairSide Conviction Token address
    address public immutable minter;
    // Address of the vesting implementation contract
    address public vestingImplementation;

    /* ========== EVENTS ========== */

    /*
     * @param vesting - address of the vesting smart contract
     * @param beneficiary - address of the recipient of the tokens
     * @param startTime - start timestamp of the vesting in seconds
     * @param amount - amount of tokens to vest
     */
    event VestingCreated(
        address indexed vesting,
        address indexed beneficiary,
        uint256 startTime,
        uint256 amount
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address _minter) public {
        minter = _minter;
    }

    /* ========== VIEWS ========== */

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Sets the FSD vesting implementation.
     * @param template Addresses of the FSD vesting implementation
     */
    function setImplementation(address template) external onlyOwner {
        require(
            template != address(0),
            "FSDVestingFactory::setImplementation: Cannot be the zero address"
        );

        vestingImplementation = template;
    }

    /**
     * @dev Creates a new vesting address based on the Premine phase schedule for `beneficiary`. Only one vesting per user is allowed.
     * @param beneficiary Address of the token recipient entitled to claim the vested funds
     * @param amount Number of FSD tokens to vest
     */
    function createVestingPRE(address beneficiary, uint256 amount)
        external
        override
        onlyMinter
        returns (address vestingAddress)
    {
        vestingAddress = vestingImplementation.clone();
        FSDVestingPRE vesting = FSDVestingPRE(vestingAddress);

        vesting.initiateVesting(beneficiary, amount);

        emit VestingCreated(
            vestingAddress,
            beneficiary,
            block.timestamp,
            amount
        );
    }

    /**
     * @dev Creates a new vesting address based on the VC whitelist phase schedule for `beneficiary`. Only one vesting per user is allowed.
     * @param beneficiary Address of the token recipient entitled to claim the vested funds
     * @param amount Number of FSD tokens to vest
     */
    function createVestingVC(address beneficiary, uint256 amount)
        external
        override
        onlyMinter
        returns (address vestingAddress)
    {
        vestingAddress = vestingImplementation.clone();
        FSDVestingVC vesting = FSDVestingVC(vestingAddress);

        vesting.initiateVesting(beneficiary, amount);

        emit VestingCreated(
            vestingAddress,
            beneficiary,
            block.timestamp,
            amount
        );
    }

    /**
     * @dev Creates a new vesting address based on the KOL premine phase schedule for `beneficiary`. Only one vesting per user is allowed.
     * @param beneficiary Address of the token recipient entitled to claim the vested funds
     * @param amount Number of FSD tokens to vest
     */
    function createVestingKOL(address beneficiary, uint256 amount)
        external
        override
        onlyMinter
        returns (address vestingAddress)
    {
        vestingAddress = vestingImplementation.clone();
        FSDVestingKOL vesting = FSDVestingKOL(vestingAddress);

        vesting.initiateVesting(beneficiary, amount);

        emit VestingCreated(
            vestingAddress,
            beneficiary,
            block.timestamp,
            amount
        );
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */

    /**
     * @dev Throws if called by any account other than the FSD minter contract.
     */
    modifier onlyMinter() {
        require(
            msg.sender == minter,
            "FSDVestingFactory:: Caller is not the FSD minter contract"
        );
        _;
    }
}
