// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Encrypted Interest Subscription (Zama FHEVM)
 *
 * - Users register encrypted interest tags as a 32-bit bitmask (euint32).
 * - Creators post content with encrypted (or dev-plain) tag masks.
 * - Matching is private: match = (userMask & contentMask) != 0, computed on ciphertexts.
 * - The contract returns an encrypted boolean verdict (1/0) and emits its handle for user-decrypt.
 *
 * Notes:
 * - Uses ONLY Zama official Solidity FHE library.
 * - Avoids FHE ops in view/pure.
 * - Uses FHE.allow/FHE.allowThis for ACL; FHE.makePubliclyDecryptable for demos.
 */

import {
    FHE,
    ebool,
    euint32,
    externalEuint32
} from "@fhevm/solidity/lib/FHE.sol";

import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedInterestSubscription is SepoliaConfig {
    /* ─────────────────────────── Meta ─────────────────────────── */

    function version() external pure returns (string memory) {
        return "EncryptedInterestSubscription/1.0.0";
    }

    /* ─────────────────────────── Ownable ─────────────────────────── */

    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ───────────────────── User encrypted tag storage ───────────────────── */

    /// @dev Per-user encrypted bitmask of interests (up to 32 tags).
    struct UserProfile {
        bool exists;
        euint32 tagsEnc;
    }
    mapping(address => UserProfile) private _user;

    event UserTagsUpdated(address indexed user, bytes32 tagsHandle);
    event UserTagsCleared(address indexed user);

    /// @notice Set/update user's encrypted interest mask (Relayer SDK proof).
    function setMyTagsEncrypted(
        externalEuint32 tagsExt,
        bytes calldata proof
    ) external {
        euint32 tags = FHE.fromExternal(tagsExt, proof);

        // Persist & ACL for reuse
        _user[msg.sender].exists = true;
        _user[msg.sender].tagsEnc = tags;
        FHE.allowThis(_user[msg.sender].tagsEnc);

        emit UserTagsUpdated(msg.sender, FHE.toBytes32(_user[msg.sender].tagsEnc));
    }

    /// @notice Dev-only plain setter (DON'T USE IN PROD).
    function setMyTagsPlain(uint32 bitmask) external {
        _user[msg.sender].exists = true;
        _user[msg.sender].tagsEnc = FHE.asEuint32(bitmask);
        FHE.allowThis(_user[msg.sender].tagsEnc);

        emit UserTagsUpdated(msg.sender, FHE.toBytes32(_user[msg.sender].tagsEnc));
    }

    /// @notice Reset tags to zero (without delete on euint32).
    function clearMyTags() external {
        require(_user[msg.sender].exists, "No tags");
        _user[msg.sender].tagsEnc = FHE.asEuint32(0);
        FHE.allowThis(_user[msg.sender].tagsEnc);
        emit UserTagsCleared(msg.sender);
    }

    /// @notice Optional audit helper: return your encrypted handle.
    function myTagsHandle() external view returns (bytes32) {
        if (!_user[msg.sender].exists) return bytes32(0);
        return FHE.toBytes32(_user[msg.sender].tagsEnc);
    }

    /// @notice Owner can choose to make a specific user's tags publicly decryptable (demo).
    function makeUserTagsPublic(address userAddr) external onlyOwner {
        require(_user[userAddr].exists, "No tags");
        FHE.makePubliclyDecryptable(_user[userAddr].tagsEnc);
    }

    /* ───────────────────── Content encrypted tag storage ───────────────────── */

    struct Content {
        address author;
        bool exists;
        bool isPlain;      // true => use plainMask (dev), else encMask
        uint32 plainMask;  // dev/demo only
        euint32 encMask;   // encrypted content tag mask
    }

    uint256 private _nextContentId = 1;
    mapping(uint256 => Content) private _content;

    event ContentCreated(uint256 indexed contentId, address indexed author, bool encrypted, uint32 plainMaskIfAny);
    event ContentUpdated(uint256 indexed contentId, bool encrypted, uint32 plainMaskIfAny);
    event ContentCleared(uint256 indexed contentId);

    /// @notice Create content with encrypted tag mask.
    function createContentEncrypted(
        externalEuint32 maskExt,
        bytes calldata proof
    ) external returns (uint256 contentId) {
        euint32 m = FHE.fromExternal(maskExt, proof);
        contentId = _nextContentId++;
        _content[contentId] = Content({
            author: msg.sender,
            exists: true,
            isPlain: false,
            plainMask: 0,
            encMask: m
        });
        FHE.allowThis(_content[contentId].encMask);
        emit ContentCreated(contentId, msg.sender, true, 0);
    }

    /// @notice Create content with plain tag mask (dev/demo only).
    function createContentPlain(uint32 mask) external returns (uint256 contentId) {
        require(mask <= type(uint32).max, "Bad mask");
        contentId = _nextContentId++;
        _content[contentId] = Content({
            author: msg.sender,
            exists: true,
            isPlain: true,
            plainMask: mask,
            encMask: FHE.asEuint32(0) // unused
        });
        emit ContentCreated(contentId, msg.sender, false, mask);
    }

    /// @notice Update your content with encrypted mask.
    function updateContentEncrypted(
        uint256 contentId,
        externalEuint32 maskExt,
        bytes calldata proof
    ) external {
        Content storage c = _content[contentId];
        require(c.exists, "Content not found");
        require(c.author == msg.sender, "Not author");
        euint32 m = FHE.fromExternal(maskExt, proof);

        c.isPlain = false;
        c.plainMask = 0;
        c.encMask = m;
        FHE.allowThis(c.encMask);

        emit ContentUpdated(contentId, true, 0);
    }

    /// @notice Update your content with plain mask (dev/demo only).
    function updateContentPlain(uint256 contentId, uint32 mask) external {
        Content storage c = _content[contentId];
        require(c.exists, "Content not found");
        require(c.author == msg.sender, "Not author");

        c.isPlain = true;
        c.plainMask = mask;
        // keep encMask as-is (unused)
        emit ContentUpdated(contentId, false, mask);
    }

    /// @notice Remove content (logical clear; can't delete euint).
    function clearContent(uint256 contentId) external {
        Content storage c = _content[contentId];
        require(c.exists, "Content not found");
        require(c.author == msg.sender || msg.sender == owner, "Not allowed");

        c.exists = false;
        c.isPlain = false;
        c.plainMask = 0;
        // encMask remains allocated but unused
        emit ContentCleared(contentId);
    }

    /// @notice Return encrypted handle for content mask (0 if plain or not exists).
    function contentHandle(uint256 contentId) external view returns (bytes32) {
        Content storage c = _content[contentId];
        if (!c.exists || c.isPlain) return bytes32(0);
        return FHE.toBytes32(c.encMask);
    }

    /// @notice Owner can mark a content encrypted mask as publicly decryptable (demo).
    function makeContentMaskPublic(uint256 contentId) external onlyOwner {
        Content storage c = _content[contentId];
        require(c.exists && !c.isPlain, "No enc mask");
        FHE.makePubliclyDecryptable(c.encMask);
    }

    /* ─────────────────────────── Matching ─────────────────────────── */

    /// @notice Emitted on match check; `verdictHandle` is an ebool (1=match, 0=not).
    event ContentMatched(address indexed user, uint256 indexed contentId, bytes32 verdictHandle);

    /**
     * @notice Private match: does user's encrypted tags intersect with content's tags?
     * @dev    match = (userMask & contentMask) != 0
     *         - If content is plain, we lift plainMask to FHE.asEuint32 on-the-fly.
     *         - Returns encrypted ebool and emits its handle for userDecrypt.
     *         - Grants decrypt rights to msg.sender only (private).
     */
    function matchContent(uint256 contentId) external returns (ebool verdict) {
        UserProfile storage up = _user[msg.sender];
        require(up.exists, "No user tags");

        Content storage c = _content[contentId];
        require(c.exists, "Content not found");

        // content mask (encrypted)
        euint32 contentMask = c.isPlain ? FHE.asEuint32(c.plainMask) : c.encMask;

        // intersection = user & content
        // NOTE: FHE.and on integers acts as bitwise AND in the FHEVM library.
        euint32 inter = FHE.and(up.tagsEnc, contentMask);

        // verdict = (intersection > 0)
        ebool nonZero = FHE.gt(inter, FHE.asEuint32(0));

        // ACL: allow caller to decrypt, and contract to reuse
        FHE.allow(nonZero, msg.sender);
        FHE.allowThis(nonZero);

        emit ContentMatched(msg.sender, contentId, FHE.toBytes32(nonZero));
        return nonZero;
    }

    /* ─────────────────────────── View helpers ─────────────────────────── */

    function hasUser(address u) external view returns (bool) {
        return _user[u].exists;
    }

    function getContentMeta(uint256 contentId)
        external
        view
        returns (bool exists, address author, bool isPlain, uint32 plainMaskIfAny)
    {
        Content storage c = _content[contentId];
        return (c.exists, c.author, c.isPlain, c.plainMask);
    }
}
