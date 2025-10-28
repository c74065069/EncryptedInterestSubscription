# Encrypted Interest Subscription · Zama FHEVM

**Private, personalized content using encrypted interest tags.** Users save their interests as an encrypted 32‑bit bitmask (`euint32`). Creators tag content (encrypted or plain for dev). Matching is done **privately on ciphertext**: `match = (userMask & contentMask) != 0`. The contract returns an **encrypted boolean**; only the requester can decrypt it with the Relayer SDK.

---

## ✨ Highlights

* **Encrypted user profiles** — Users store interests as `euint32` (32 tags). No plaintext leakage.
* **Encrypted/Plain content tags** — Post content with encrypted masks (prod) or plain masks (dev/demo).
* **Private matching** — `(user & content) != 0` computed under FHE; verdict is an encrypted `ebool`.
* **Caller‑only decryption** — Use `userDecrypt` (Relayer SDK 0.2.0) to reveal only your own verdict.
* **Auditability** — Bytes32 **handles** for ciphertexts; optional `make*Public()` for demos.

---

## 🧱 Smart Contract (overview)

Contract name: **`EncryptedInterestSubscription`**

**User functions**

* `setMyTagsEncrypted(externalEuint32 tagsExt, bytes proof)` — Save encrypted interests (Relayer SDK input + proof).
* `setMyTagsPlain(uint32 bitmask)` — Dev‑only plain setter (do **not** use in prod).
* `clearMyTags()` — Reset to zero (no `delete` on `euint`).
* `myTagsHandle() → bytes32` — Your encrypted handle for audits/tests.
* `makeUserTagsPublic(address user)` — Owner may mark a user mask publicly decryptable (demo).

**Content functions**

* `createContentEncrypted(externalEuint32, bytes) → contentId` — New content with encrypted tags.
* `createContentPlain(uint32) → contentId` — Dev/demo plain content.
* `updateContentEncrypted(uint256, externalEuint32, bytes)` — Update to encrypted mask.
* `updateContentPlain(uint256, uint32)` — Dev/demo update to plain mask.
* `clearContent(uint256)` — Logical remove (cannot `delete` an `euint`).
* `contentHandle(uint256) → bytes32` — Ciphertext handle if encrypted.
* `makeContentMaskPublic(uint256)` — Owner may expose a content mask for public decryption (demo).

**Matching**

* `matchContent(uint256 contentId) → ebool` — Emits `ContentMatched(user, contentId, verdictHandle)`; the caller decrypts privately with Relayer SDK.

> **Tag map:** 32 labels → bits `0..31`. The UI defines labels; the contract treats masks as a 32‑bit set.

---

## 🖥️ Frontend (single‑file)

* Location: **`frontend/public/index.html`** (copy to any static host).
* **Wallet**: Ethers v6 (`BrowserProvider`).
* **FHE**: Relayer SDK **0.2.0** for creating encrypted inputs and `userDecrypt`.
* **Panels**: User Interests, Content, Private Match (+ dev shortcuts: plain setters).

---

## ⚙️ Installation & Run

> Requirements: Node 18+, MetaMask (or compatible), Internet access to Zama test relayer.

```bash
# 1) (Optional) install any repo deps you use
npm i

# 2) Serve the static frontend (choose one)
# a) http-server
npx http-server ./frontend/public -p 8080

# b) Vite as a static server
npx vite --root frontend/public --port 5173 --strictPort

# 3) Open in the browser
http://localhost:8080/   # or the Vite URL
```

## 🚀 Quick Usage

1. **Connect** — Open `frontend/public/index.html`, click **Connect** (ensure Sepolia).
2. **Set interests (user)** — Click tags → **Protect & Save** (encrypted) or **Quick Save (dev)**. Your **handle** appears below.
3. **Create content (author)** — Click tags → **Publish Encrypted** (prod) or **Publish Plain (dev)**. Note the **contentId**.
4. **Private match (user)** — Enter `contentId` → **Test Private Match**. The app will decrypt the `verdictHandle` (YES/NO) only for you.

---

* Solidity (Zama FHEVM): `@fhevm/solidity` (official library)
* Relayer SDK: `relayer-sdk-js@0.2.0`
* Ethers v6

---

## 📁 Structure

```
frontend/
  public/
    index.html        # single‑file UI
contracts/
  EncryptedInterestSubscription.sol
hardhat.config.ts | .js
scripts/
```

---

## 📄 License

MIT — see `LICENSE`.

