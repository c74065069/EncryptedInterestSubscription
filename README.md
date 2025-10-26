# Private Event Eligibility (FHEVM)

Privacy‑preserving event registration on **Zama FHEVM**: users encrypt their age, country (ISO‑3166 numeric), and invite flag in a single shot. The smart contract stores **only encrypted eligibility** (a boolean handle) and per‑event policy. No raw personal data or individual plaintext values are kept on‑chain.

> Frontend entry: `frontend/public/index.html`

---

## ✨ What it does

* **Private registration:** age, country, and invite flag are encrypted client‑side via Zama Relayer SDK. The contract receives the external ciphertext handles plus proof and evaluates eligibility entirely under FHE.
* **Policy control:** the owner sets per‑event policy: min age, invite required (true/false), and an allow‑list of countries.
* **Privacy by design:** the chain only holds encrypted eligibility handles. Clear‑text PII is never emitted or stored.
* **Flexible decryption:**

  * **Public decrypt** (optional): owner may mark specific values public (e.g., for audits/demos).
  * **User decrypt**: authorized users can EIP‑712 sign a request for relayer‑assisted decrypt of their own handle.

---

## 📦 Repository layout

```
frontend/
  public/
    index.html        # Single‑file app (ethers v6 + Relayer SDK 0.2.x)
contracts/
  PrivateEventEligibility.sol
scripts/
  deploy.ts | deploy.js
hardhat.config.ts | .js
.env.example
```

---

## 🔐 Smart contract (overview)

**`PrivateEventEligibility.sol`**

* Stores per‑event policy:

  * `minAge` (uint16), `requireInvite` (bool), `allowCountries[]` (uint16 ISO numeric)
* Accepts a single external encrypted input (age, country, invite) and computes **`eligible = (age >= minAge) && (country in allow) && (inviteOK)`**
* Emits no PII, keeps only encrypted handles
* Utility methods to expose encrypted handles for user/public decrypt

> Compiled against Solidity 0.8.x with `@fhevm/solidity` library. See contract for exact API.

---

## 🖥️ Frontend (single file)

* Pure HTML/JS app under `frontend/public/index.html`
* Uses **ethers v6** and **Relayer SDK 0.2.x** from CDN
* Minimal state management; robust network handling (recreates provider/contract on `chainChanged`/`accountsChanged`)
* Buttons:

  * **Submit Encrypted** – registers user
  * **Set Policy** – owner‑only policy update
  * **Make My Eligibility Public** – optional public decrypt
  * **Get Handle / Public Decrypt / User Decrypt** – read & decrypt own eligibility

---

## 🚀 Quick start

### Prerequisites

* Node 18+
* MetaMask (Sepolia)
* Sepolia ETH for gas

### Install

```bash
npm i
```

### Environment

Copy `.env.example` → `.env` and fill values (RPC, private key, relayer URL if different).

### Compile & deploy (Hardhat)

```bash
npx hardhat clean
npx hardhat compile
npx hardhat deploy --network sepolia
```

Grab the deployed contract address and paste it into the **CONFIG** block inside `frontend/public/index.html`:

```js
window.CONFIG = {
  NETWORK_NAME: 'Sepolia',
  CHAIN_ID_HEX: '0xaa36a7',
  CONTRACT_ADDRESS: '0x…',
  RELAYER_URL: 'https://relayer.testnet.zama.cloud'
};
```

### Serve the frontend

Open `frontend/public/index.html` directly in the browser or host it with any static server (e.g. VSCode Live Server).

---

## 🛠️ Development notes

* **Relayer SDK**: initialized once after wallet connect; re‑initialized on network/account change.
* **Ethers v6**: use `new BrowserProvider(window.ethereum, 'any')` to avoid cached chainId; always rebuild provider/contract on `chainChanged`.
* **Network**: app enforces Sepolia (11155111). If the wallet is on another network, it prompts a switch and rebuilds connections.

---


## 📄 License

MIT — see `LICENSE`.

