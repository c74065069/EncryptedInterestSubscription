// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Secret Bonus Payout (Zama FHEVM)
 *
 * Spec:
 * - Employer stores encrypted KPI thresholds and two encrypted bonus amounts:
 *      - minQuality (u8), minVelocity (u8), minImpact (u8)
 *      - bonusYes (u32)  → paid if all thresholds are met
 *      - bonusNo  (u32)  → otherwise
 * - Employee submits encrypted KPIs (quality/velocity/impact as u8).
 * - Contract computes encrypted bonus and grants decrypt rights only to the employee.
 *
 * Notes:
 * - Uses only official Zama FHE library & SepoliaConfig.
 * - Avoid FHE ops in view/pure.
 */

import {
    FHE,
    ebool,
    euint8,
    euint32,
    externalEuint8,
    externalEuint32
} from "@fhevm/solidity/lib/FHE.sol";

import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract SecretBonusPayout is SepoliaConfig {
    /* ─────────── Ownable ─────────── */

    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() { owner = msg.sender; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ─────────── Encrypted Policy (global) ─────────── */

    euint8  private _minQuality;
    euint8  private _minVelocity;
    euint8  private _minImpact;
    euint32 private _bonusYes;
    euint32 private _bonusNo;

    bool    private _policyExists;

    /* ─────────── Events ─────────── */

    event PolicyUpdated(
        bytes32 minQualityH,
        bytes32 minVelocityH,
        bytes32 minImpactH,
        bytes32 bonusYesH,
        bytes32 bonusNoH
    );

    /// @dev Emitted on each KPI evaluation; bonusHandle is an encrypted uint32.
    event BonusComputed(address indexed employee, bytes32 bonusHandle);

    /* ─────────── Admin: set policy ─────────── */

    /// @notice Set encrypted KPI policy (Relayer SDK proof for all inputs).
    function setPolicyEncrypted(
        externalEuint8  minQualityExt,
        externalEuint8  minVelocityExt,
        externalEuint8  minImpactExt,
        externalEuint32 bonusYesExt,
        externalEuint32 bonusNoExt,
        bytes calldata  proof
    ) external onlyOwner {
        euint8  q  = FHE.fromExternal(minQualityExt,  proof);
        euint8  v  = FHE.fromExternal(minVelocityExt, proof);
        euint8  i  = FHE.fromExternal(minImpactExt,   proof);
        euint32 by = FHE.fromExternal(bonusYesExt,    proof);
        euint32 bn = FHE.fromExternal(bonusNoExt,     proof);

        _minQuality = q;
        _minVelocity = v;
        _minImpact   = i;
        _bonusYes    = by;
        _bonusNo     = bn;
        _policyExists = true;

        FHE.allowThis(_minQuality);
        FHE.allowThis(_minVelocity);
        FHE.allowThis(_minImpact);
        FHE.allowThis(_bonusYes);
        FHE.allowThis(_bonusNo);

        emit PolicyUpdated(
            FHE.toBytes32(_minQuality),
            FHE.toBytes32(_minVelocity),
            FHE.toBytes32(_minImpact),
            FHE.toBytes32(_bonusYes),
            FHE.toBytes32(_bonusNo)
        );
    }

    /// @notice DEV ONLY: set plain policy (converted to ciphertexts on-chain).
    function setPolicyPlain(
        uint8  minQuality,
        uint8  minVelocity,
        uint8  minImpact,
        uint32 bonusYes,
        uint32 bonusNo
    ) external onlyOwner {
        _minQuality = FHE.asEuint8(minQuality);
        _minVelocity = FHE.asEuint8(minVelocity);
        _minImpact   = FHE.asEuint8(minImpact);
        _bonusYes    = FHE.asEuint32(bonusYes);
        _bonusNo     = FHE.asEuint32(bonusNo);
        _policyExists = true;

        FHE.allowThis(_minQuality);
        FHE.allowThis(_minVelocity);
        FHE.allowThis(_minImpact);
        FHE.allowThis(_bonusYes);
        FHE.allowThis(_bonusNo);

        emit PolicyUpdated(
            FHE.toBytes32(_minQuality),
            FHE.toBytes32(_minVelocity),
            FHE.toBytes32(_minImpact),
            FHE.toBytes32(_bonusYes),
            FHE.toBytes32(_bonusNo)
        );
    }

    /// @notice Optional: expose encrypted handles for audit/demo.
    function getPolicyHandles()
        external
        view
        returns (
            bytes32 minQualityH,
            bytes32 minVelocityH,
            bytes32 minImpactH,
            bytes32 bonusYesH,
            bytes32 bonusNoH,
            bool exists
        )
    {
        return (
            FHE.toBytes32(_minQuality),
            FHE.toBytes32(_minVelocity),
            FHE.toBytes32(_minImpact),
            FHE.toBytes32(_bonusYes),
            FHE.toBytes32(_bonusNo),
            _policyExists
        );
    }

    /// @notice Optional demo: mark policy as publicly decryptable.
    function makePolicyPublic() external onlyOwner {
        require(_policyExists, "Policy not set");
        FHE.makePubliclyDecryptable(_minQuality);
        FHE.makePubliclyDecryptable(_minVelocity);
        FHE.makePubliclyDecryptable(_minImpact);
        FHE.makePubliclyDecryptable(_bonusYes);
        FHE.makePubliclyDecryptable(_bonusNo);
    }

    /* ─────────── Employee flow ─────────── */

    /**
     * @notice Employee submits encrypted KPIs; contract returns encrypted bonus.
     *         cond = (q>=minQ) && (v>=minV) && (i>=minI)
     *         bonus = cond ? bonusYes : bonusNo
     */
    function evaluateKPIs(
        externalEuint8 qualityExt,
        externalEuint8 velocityExt,
        externalEuint8 impactExt,
        bytes calldata proof
    ) external returns (euint32 bonusCt) {
        require(_policyExists, "Policy not set");

        // Build condition in a scoped way to keep stack shallow
        ebool cond;
        {
            euint8 q = FHE.fromExternal(qualityExt, proof);
            ebool qOk = FHE.ge(q, _minQuality);

            euint8 v = FHE.fromExternal(velocityExt, proof);
            ebool vOk = FHE.ge(v, _minVelocity);

            euint8 i = FHE.fromExternal(impactExt, proof);
            ebool iOk = FHE.ge(i, _minImpact);

            cond = FHE.and(FHE.and(qOk, vOk), iOk);
        }

        // Select encrypted amount using FHE.select (supported in the official lib)
        euint32 bonus = FHE.select(cond, _bonusYes, _bonusNo);

        // ACL: only employee can decrypt
        FHE.allow(bonus, msg.sender);
        FHE.allowThis(bonus);

        emit BonusComputed(msg.sender, FHE.toBytes32(bonus));
        return bonus;
    }

    function version() external pure returns (string memory) {
        return "SecretBonusPayout/1.0.1";
    }
}
