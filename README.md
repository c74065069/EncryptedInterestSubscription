# Secret Bonus Payout · Zama FHEVM

Privacy-preserving bonus allocation on-chain. Employees submit **encrypted KPIs**; the contract returns an **encrypted bonus amount** that only the employee can decrypt via Zama’s Relayer SDK. Policy thresholds and bonus values are kept encrypted on-chain.

> **Network**: Sepolia
> **Contract (deployed)**: `0x13274eA87Db740ca19f1d85B8c0c6aDf90a0a4EB`
> **Frontend entry**: `frontend/public/bonus.html`
> **Relayer SDK**: `@zama-fhe/relayer-sdk` v0.2.0
> **Solidity**: `0.8.24` (recommended: `viaIR: true`, optimizer enabled)

---

## Overview

**Secret Bonus Payout** implements a private bonus workflow on Zama FHEVM:

* **Owner** uploads a global **encrypted policy**: `minQuality (u8)`, `minVelocity (u8)`, `minImpact (u8)`, `bonusYes (u32)`, `bonusNo (u32)`.
* **Employee** submits encrypted KPIs (`quality`, `velocity`, `impact`).
* Contract computes: `cond = (q≥minQ) && (v≥minV) && (i≥minI)` → `bonus = cond ? bonusYes : bonusNo`.
* Only the **employee (msg.sender)** gets decrypt rights to the encrypted `bonus` using **userDecrypt (EIP‑712)**.

---

## Core Features

* 🔒 All sensitive values are encrypted (`euint8`, `euint32`) using official Zama Solidity library.
* 🎯 Binary policy check with private result; no KPIs or thresholds are revealed.
* 🔐 Access control via `FHE.allow` (employee-only decryption) and `FHE.allowThis` for reuse.
* 🧪 Dev helpers: plain policy setter and public decrypt flags (for demos).

---

## Contract

**File**: `contracts/SecretBonusPayout.sol`

**Key storage**

```solidity
// thresholds
 euint8  _minQuality;
 euint8  _minVelocity;
 euint8  _minImpact;
// bonus amounts
 euint32 _bonusYes;
 euint32 _bonusNo;
 bool    _policyExists;
```

**Main functions**

* `setPolicyEncrypted(minQ, minV, minI, bonusYes, bonusNo, proof)` — owner sets **encrypted** policy using Relayer SDK handles + proof.
* `setPolicyPlain(minQ, minV, minI, bonusYes, bonusNo)` — converts clear values to encrypted on-chain (dev only).
* `makePolicyPublic()` — optional demo: mark policy ciphertexts publicly decryptable.
* `getPolicyHandles()` — return `bytes32` handles for audits/UI.
* `evaluateKPIs(quality, velocity, impact, proof)` — returns encrypted `u32` bonus; **only employee** can decrypt.

**Events**

* `PolicyUpdated(minQualityH, minVelocityH, minImpactH, bonusYesH, bonusNoH)`
* `BonusComputed(employee, bonusHandle)`

**Implementation notes**

* Conditional selection uses `FHE.select(cond, _bonusYes, _bonusNo)` (no `cmux`).
* Avoid FHE ops in view/pure. Expose only handles via `FHE.toBytes32`.

---

## Usage Guide

### Admin (Owner)

1. **Connect** wallet (Sepolia). The app will bootstrap Relayer.
2. Enter thresholds and bonus values. Click **Set Encrypted Policy**.
3. Optionally call **Make Policy Public** for demo/audit.
4. Use **Policy handles** section for visibility/debug.

### Employee

1. **Connect** with your wallet.
2. Enter your KPIs (Quality, Velocity, Impact).
3. Click **Submit Encrypted KPIs**. The UI will:

   * Encrypt inputs (`createEncryptedInput → add8/add8/add8 → encrypt`).
   * Send handles + `proof` to `evaluateKPIs`.
   * Read `BonusComputed` event, pick `bonusHandle`.
   * Request **userDecrypt** with EIP‑712 signature → display `$ bonus`.

---

## Environment Variables

For Hardhat:

```bash
SEPOLIA_RPC=https://sepolia.infura.io/v3/<key>
DEPLOYER_PK=0x<private_key>
ETHERSCAN_API_KEY=<optional>
```

If you move to a bundled frontend (Vite/React), add:

```bash
VITE_RELAYER_URL=https://relayer.testnet.zama.cloud
VITE_CONTRACT_ADDRESS=0x13274eA87Db740ca19f1d85B8c0c6aDf90a0a4EB
```

---

## Troubleshooting

* **`Policy not set`** — call `setPolicyEncrypted` (or `setPolicyPlain` for dev) as **owner** first.
* **WASM/Relayer errors** — ensure COOP/COEP meta tags are present and call `await initSDK()` before `createInstance(...)`.
* **Decryption fails** — only the **employee (msg.sender)** can decrypt. Confirm your address and the EIP‑712 signature parameters (contract list includes this contract address).
* **Compilation issues** — enable `viaIR: true` and optimizer; avoid adding FHE ops in view/pure.

---

## Security

* Do not log plaintext KPI/bonus data in the UI.
* Keep `@zama-fhe/relayer-sdk` pinned to `0.2.0` for reproducibility.
* Review and audit before production use.

---

## License

MIT — see `LICENSE`.
