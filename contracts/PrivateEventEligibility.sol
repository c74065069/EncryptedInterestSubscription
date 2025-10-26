// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * PrivateEventEligibility (Zama FHEVM)
 * Users submit encrypted (age, country, inviteFlag).
 * Contract computes encrypted ebool "eligible":
 *    age >= minAge && country in allowlist && (requireInvite ? invite==1 : true).
 * Никаких открытых PII не хранится и не эмитится.
 *
 * Исправление: helper-функции без pure/view, т.к. вызовы FHE.* могут считаться state-modifying.
 */

import {
    FHE,
    ebool,
    euint8,
    euint16,
    externalEuint8,
    externalEuint16
} from "@fhevm/solidity/lib/FHE.sol";

import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract PrivateEventEligibility is SepoliaConfig {
    /* ─────────────── Version / Ownership ─────────────── */

    function version() external pure returns (string memory) {
        return "PrivateEventEligibility/1.0.3";
    }

    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() { owner = msg.sender; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ─────────────── Data Model ─────────────── */

    struct Policy {
        bool exists;
        uint16 minAge;
        bool requireInvite;
        uint16[] allowedCountries; // ISO numeric (e.g., 840 = US)
    }

    struct Registration {
        bool exists;
        ebool eligible; // encrypted boolean
    }

    // eventId => Policy
    mapping(bytes32 => Policy) private _policies;
    // eventId => user => Registration
    mapping(bytes32 => mapping(address => Registration)) private _regs;

    /* ─────────────── Events ─────────────── */

    event PolicySet(
        bytes32 indexed eventId,
        uint16 minAge,
        bool requireInvite,
        uint16[] allowedCountries
    );

    event Registered(
        bytes32 indexed eventId,
        address indexed user,
        bytes32 eligibleHandle
    );

    event EventMadePublic(bytes32 indexed eventId);

    /* ─────────────── Admin ─────────────── */

    function setPolicy(
        bytes32 eventId,
        uint16 minAge,
        bool requireInvite,
        uint16[] calldata allowedCountries
    ) external onlyOwner {
        require(eventId != bytes32(0), "Bad eventId");
        require(allowedCountries.length <= 16, "Too many countries");

        Policy storage P = _policies[eventId];
        P.exists = true;
        P.minAge = minAge;
        P.requireInvite = requireInvite;

        delete P.allowedCountries;
        for (uint256 i = 0; i < allowedCountries.length; i++) {
            P.allowedCountries.push(allowedCountries[i]);
        }

        emit PolicySet(eventId, minAge, requireInvite, P.allowedCountries);
    }

    function getPolicy(bytes32 eventId)
        external
        view
        returns (bool exists, uint16 minAge, bool requireInvite, uint16[] memory countries)
    {
        Policy storage P = _policies[eventId];
        exists = P.exists;
        minAge = P.minAge;
        requireInvite = P.requireInvite;
        countries = P.allowedCountries;
    }

    /* ─────────────── Internal helpers (без pure/view) ─────────────── */

    // false как (0 < 0)
    function _falseBool() internal returns (ebool) {
        return FHE.lt(FHE.asEuint16(0), FHE.asEuint16(0));
    }

    // true как (0 == 0)
    function _trueBool() internal returns (ebool) {
        return FHE.eq(FHE.asEuint8(0), FHE.asEuint8(0));
    }

    // age >= minAge
    function _checkAge(euint16 ageCt, uint16 minAge) internal returns (ebool) {
        return FHE.ge(ageCt, FHE.asEuint16(minAge));
    }

    // country ∈ allowList (OR по равенству)
    function _checkCountry(euint16 countryCt, uint16[] storage list) internal returns (ebool ok) {
        ok = _falseBool();
        uint256 n = list.length;
        for (uint256 i = 0; i < n; i++) {
            ebool matchOne = FHE.eq(countryCt, FHE.asEuint16(list[i]));
            ok = FHE.or(ok, matchOne);
        }
    }

    // invite в зависимости от флага
    function _checkInvite(euint8 inviteCt, bool requireInvite) internal returns (ebool) {
        if (!requireInvite) return _trueBool();
        return FHE.eq(inviteCt, FHE.asEuint8(1));
    }

    // eligible = ageOK & countryOK & inviteOK
    function _computeEligible(
        euint16 ageCt,
        euint16 countryCt,
        euint8 inviteCt,
        Policy storage P
    ) internal returns (ebool) {
        ebool ageOK = _checkAge(ageCt, P.minAge);
        ebool countryOK = _checkCountry(countryCt, P.allowedCountries);
        ebool inviteOK = _checkInvite(inviteCt, P.requireInvite);
        return FHE.and(ageOK, FHE.and(countryOK, inviteOK));
    }

    /* ─────────────── User flow ─────────────── */

    /**
     * @notice Submit encrypted attributes (должны быть из одного encrypt()).
     * @param eventId    идентификатор события
     * @param ageExt     externalEuint16
     * @param countryExt externalEuint16
     * @param inviteExt  externalEuint8 (0/1)
     * @param proof      общее доказательство для всех трёх значений
     */
    function register(
        bytes32 eventId,
        externalEuint16 ageExt,
        externalEuint16 countryExt,
        externalEuint8 inviteExt,
        bytes calldata proof
    ) external returns (ebool eligibleCt) {
        Policy storage P = _policies[eventId];
        require(P.exists, "Event not found");
        require(proof.length > 0, "Empty proof");

        // Deserialize encrypted inputs (общее proof)
        euint16 ageCt     = FHE.fromExternal(ageExt, proof);
        euint16 countryCt = FHE.fromExternal(countryExt, proof);
        euint8  inviteCt  = FHE.fromExternal(inviteExt, proof);

        // Compute eligibility
        ebool ok = _computeEligible(ageCt, countryCt, inviteCt, P);

        // Store per-user
        Registration storage R = _regs[eventId][msg.sender];
        R.exists = true;
        R.eligible = ok;

        // ACL
        FHE.allow(R.eligible, msg.sender); // приватная расшифровка пользователем
        FHE.allow(R.eligible, owner);      // (опционально) организатор
        FHE.allowThis(R.eligible);         // контракт может переиспользовать

        emit Registered(eventId, msg.sender, FHE.toBytes32(R.eligible));
        return ok;
    }

    /// Хэндл для самого пользователя
    function getMyEligibilityHandle(bytes32 eventId) external view returns (bytes32) {
        Registration storage R = _regs[eventId][msg.sender];
        require(R.exists, "Not registered");
        return FHE.toBytes32(R.eligible);
    }

    /// Хэндл для выбранного пользователя (только владелец)
    function getEligibilityHandle(bytes32 eventId, address user) external view onlyOwner returns (bytes32) {
        Registration storage R = _regs[eventId][user];
        require(R.exists, "No registration");
        return FHE.toBytes32(R.eligible);
    }

    /// Пользователь может сделать свой результат публично дешифруемым
    function makeMyEligibilityPublic(bytes32 eventId) external {
        Registration storage R = _regs[eventId][msg.sender];
        require(R.exists, "Not registered");
        FHE.makePubliclyDecryptable(R.eligible);
        emit EventMadePublic(eventId);
    }
}
