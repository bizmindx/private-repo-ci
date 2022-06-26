// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/drafts/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../dependencies/SignatureWhitelist.sol";
import "../dependencies/DSMath.sol";
import "../dependencies/FSOwnable.sol";
import "../interfaces/IFSDVesting.sol";
import "../interfaces/IFSDVestingFactory.sol";
import "../interfaces/IFSD.sol";

/**
 * @dev Implementation {FSDMinter} FSD minter contract.
 *
 * Has utility functions to modify the contract's state.
 *
 * Attributes:
 * - Mintable via an Augmented Bonding Curve
 */
// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
contract FSDMinter is SignatureWhitelist, FSOwnable {
    /* ========== LIBRARIES ========== */

    using DSMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // FSD token contract address
    IFSD public immutable fsd;
    // FSD Vesting contract address
    IFSDVestingFactory public vestingFactory;

    // Maps a user address to its vesting contract address
    mapping(address => address) public userVesting;

    /* ========== EVENTS ========== */

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initialises the contract's state with {fsd} address.
     * It also passes {whitelistSigner} address to the constructor of {SignatureWhitelist} contract.
     */
    constructor(IFSD _fsd, address _whitelistSigner)
        public
        SignatureWhitelist(_whitelistSigner)
    {
        fsd = _fsd;
    }

    /* ========== VIEWS ========== */

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the VCWL phase (when funding pool's balance is less than 500 ETH), only
     * 70% of the deposited ETH are bonded, the rest 30% are sent to the {fundingPool}.
     * The bonded amount is immediately vested according to the FSD vesting schedule.
     *
     * Requirements:
     * - during VCWL phase, only whitelisted users can mint
     * - during VCWL phase, the tokens that are minted are immediately vested
     * - bonding ETH amount cannot be zero
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     */
    function mintVCWL(bytes calldata sig, uint256 tokenMinimum)
        external
        payable
        onlyValidPhase(IFSD.Phase.VCWL)
    {
        _mintInternal(sig, msg.sender, tokenMinimum, true, true);
    }

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the CWL phase, 100% of the deposited ETH are bonded.
     *
     * Requirements:
     * - during CWL phase, only whitelisted users can mint
     * - bonding ETH amount cannot be zero
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     */
    function mintCWL(bytes calldata sig, uint256 tokenMinimum)
        external
        payable
        onlyValidPhase(IFSD.Phase.CWL)
    {
        _mintInternal(sig, msg.sender, tokenMinimum, false, true);
    }

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the Community whitelist phase, 100% of the deposited ETH are bonded.
     *
     * Requirements:
     * - bonding ETH amount cannot be zero
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     */
    function mintToCWL(
        address to,
        bytes calldata sig,
        uint256 tokenMinimum
    ) external payable onlyValidPhase(IFSD.Phase.CWL) {
        _mintInternal(sig, to, tokenMinimum, false, true);
    }

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the Final phase, 100% of the deposited ETH are bonded.
     *
     * Requirements:
     * - bonding ETH amount cannot be zero
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     */
    function mintToFinal(address to, uint256 tokenMinimum)
        external
        payable
        onlyValidPhase(IFSD.Phase.Final)
    {
        _mintInternal(new bytes(0), to, tokenMinimum, false, false);
    }

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the Final phase, 100% of the deposited ETH are bonded.
     *
     * Requirements:
     * - bonding ETH amount cannot be zero
     * - the minted FSD amount must not be less than parameter {tokenMinimum}
     */
    function mint(uint256 tokenMinimum)
        external
        payable
        onlyValidPhase(IFSD.Phase.Final)
    {
        _mintInternal(new bytes(0), msg.sender, tokenMinimum, false, false);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Sets the vesting factory address. Invocable only once.
     * @param _vestingFactory Address of the vesting factory smart contract
     */
    function setVestingFactory(IFSDVestingFactory _vestingFactory)
        external
        onlyOwner
    {
        require(
            _vestingFactory != IFSDVestingFactory(0),
            "Vesting::setVestingFactory: Cannot be the zero address"
        );
        require(
            vestingFactory == IFSDVestingFactory(0),
            "Vesting::setVestingFactory: Already set"
        );
        vestingFactory = _vestingFactory;
    }

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the Premine or KOL phases, 100% of the deposited ETH are bonded. The bonded amount is
     * immediately vested according to the FSD vesting schedule.
     *
     * Requirements:
     * - during Premine or KOL phases, only the token owner can mint to a group of users
     * - during Premine or KOL phases, depositing any ether for bonding is disallowed
     * - during Premine or KOL phases, the tokens that are minted are immediately vested
     */
    function mintPremine(address[] calldata users, uint256[] calldata amounts)
        external
        onlyOwner
    {
        IFSD.Phase currentPhase = fsd.currentPhase();
        require(
            currentPhase == IFSD.Phase.Premine ||
                currentPhase == IFSD.Phase.KOL,
            "FSD::mintPremineUS: Invalid Phase"
        );
        _mintInternalPremine(currentPhase, users, amounts);
    }

    /**
     * @dev Allows minting of FSD tokens by depositing ETH for bonding in the contract.
     * During the Premine phase, 100% of the deposited ETH are bonded. The bonded amount is
     * immediately vested according to the FSD vesting schedule.
     *
     * Requirements:
     * - during Premine phase, only the token owner can mint to a group of users
     * - during Premine phase, depositing any ether for bonding is disallowed
     * - during Premine phase, the tokens that are minted are immediately vested
     */
    function mintPremineUS(address[] calldata users, uint256[] calldata amounts)
        external
        onlyOwner
    {
        IFSD.Phase currentPhase = fsd.currentPhase();
        require(
            currentPhase == IFSD.Phase.Premine ||
                currentPhase == IFSD.Phase.KOL,
            "FSD::mintPremineUS: Invalid Phase"
        );
        uint256 userLength = users.length;
        require(
            userLength == amounts.length,
            "FSD::mintPremineUS: Different sized arrays"
        );

        for (uint256 i = 0; i < userLength; i++) {
            fsd.mintDirect(users[i], amounts[i]);
        }
    }

    function pullTokensPremine(
        address[] calldata users,
        bytes[] calldata sigs,
        uint256[] calldata amounts
    ) external onlyOwner {
        IFSD.Phase currentPhase = fsd.currentPhase();
        require(
            currentPhase == IFSD.Phase.Premine ||
                currentPhase == IFSD.Phase.KOL,
            "FSD::pullTokensPremine: Invalid Phase"
        );
        uint256 userLength = users.length;
        require(
            userLength == sigs.length,
            "FSD::pullTokensPremine: Different sized arrays"
        );
        require(
            userLength == amounts.length,
            "FSD::pullTokensPremine: Different sized arrays"
        );

        for (uint256 i = 0; i < userLength; i++) {
            if (sigs[i].length != 65) {
                revert("FSD::pullTokensPremine: Invalid signature length");
            }

            address user = users[i];
            bytes memory signature = sigs[i];
            uint256 amount = amounts[i];
            // Divide the signature in r, s and v variables
            bytes32 r;
            bytes32 s;
            uint8 v;

            // solhint-disable-next-line no-inline-assembly
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }

            address vestingAddress = userVesting[user];
            if (vestingAddress == address(0)) {
                if (currentPhase == IFSD.Phase.Premine) {
                    vestingAddress = vestingFactory.createVestingPRE(
                        user,
                        amount
                    );
                    userVesting[user] = vestingAddress;
                } else {
                    vestingAddress = vestingFactory.createVestingKOL(
                        user,
                        amount
                    );
                    userVesting[user] = vestingAddress;
                }
            } else {
                IFSDVesting(vestingAddress).updateVestedTokens(amount);
            }

            IERC20Permit(address(fsd)).permit(
                user,
                address(this),
                amount,
                111111111111,
                v,
                r,
                s
            ); // change timestamp
            IERC20(address(fsd)).transferFrom(user, vestingAddress, amounts[i]);
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _mintInternal(
        bytes memory sig,
        address to,
        uint256 tokenMinimum,
        bool vest,
        bool onlyWhitelist
    ) private {
        if (onlyWhitelist) _onlyWL(sig, to);

        if (vest) _createVesting(to, tokenMinimum);
        else fsd.mint{value: msg.value}(to, tokenMinimum);
    }

    function _mintInternalPremine(
        IFSD.Phase _phase,
        address[] memory _users,
        uint256[] memory _amounts
    ) private {
        uint256 userLength = _users.length;
        require(userLength == _amounts.length, "FSD:: Different sized arrays");

        for (uint256 i = 0; i < userLength; i++) {
            _createVestingPremine(_phase, _users[i], _amounts[i]);
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Creates a new vesting contract for the user. Only one vesting per user is allowed.
     * @param to FSD token holder
     * @param tokenMinimum Minimum amount of FSD token to vest
     */
    function _createVesting(address to, uint256 tokenMinimum) private {
        uint256 amount = fsd.getTokensMinted(msg.value);
        address vestingAddress = userVesting[to];
        if (vestingAddress == address(0)) {
            vestingAddress = vestingFactory.createVestingVC(to, amount);
            userVesting[to] = vestingAddress;
        } else {
            IFSDVesting(vestingAddress).updateVestedTokens(amount);
        }

        fsd.mint{value: msg.value}(vestingAddress, tokenMinimum);
    }

    /**
     * @dev Creates a new vesting contract for the user. Only one vesting per user is allowed.
     * @param _phase FSD token phase
     * @param to FSD token holder
     * @param amount Amount of FSD token to vest
     */
    function _createVestingPremine(
        IFSD.Phase _phase,
        address to,
        uint256 amount
    ) private {
        address vestingAddress = userVesting[to];
        if (vestingAddress == address(0)) {
            if (_phase == IFSD.Phase.Premine) {
                vestingAddress = vestingFactory.createVestingPRE(to, amount);
                userVesting[to] = vestingAddress;
            } else if (_phase == IFSD.Phase.KOL) {
                vestingAddress = vestingFactory.createVestingKOL(to, amount);
                userVesting[to] = vestingAddress;
            }
        } else {
            IFSDVesting(vestingAddress).updateVestedTokens(amount);
        }

        fsd.mintDirect(vestingAddress, amount);
    }

    function _onlyValidPhase(IFSD.Phase _phase) private {
        require(fsd.currentPhase() == _phase, "FSD:: Invalid Phase");
    }

    function _onlyWL(bytes memory _sig, address _user) private {
        require(_whitelist(_sig, _user), "FSD:: Not whitelisted");
    }

    /* ========== MODIFIERS ========== */

    modifier onlyValidPhase(IFSD.Phase _phase) {
        _onlyValidPhase(_phase);
        _;
    }
}
