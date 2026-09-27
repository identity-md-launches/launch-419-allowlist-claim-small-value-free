// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice A permanent, value-free record of claims against an immutable address allowlist.
contract AllowlistClaim {
    bytes32 private immutable merkleRoot;

    /// @notice Whether this address has already claimed.
    /// @dev The address itself is the storage slot. This contract has no other mutable state.
    function claimed(address account) external view returns (bool) {
        assembly ("memory-safe") {
            mstore(0, sload(account))
            return(0, 32)
        }
    }

    event Claimed(address indexed account);

    constructor(bytes32 root) {
        merkleRoot = root;
    }

    /// @notice Verify a single-hashed, packed address leaf using sorted pairs.
    function isAllowed(address account, bytes32[] calldata proof) external view returns (bool) {
        bool allowed = _verify(account, proof);
        assembly ("memory-safe") {
            mstore(0, allowed)
            return(0, 32)
        }
    }

    function _verify(address account, bytes32[] calldata proof) private view returns (bool allowed) {
        bytes32 root = merkleRoot;
        assembly ("memory-safe") {
            // An address leaf is exactly 20 bytes, not a padded ABI word.
            mstore(0, account)
            let node := keccak256(12, 20)
            let cursor := proof.offset
            for { let count := proof.length } count { count := sub(count, 1) } {
                let sibling := calldataload(cursor)
                // Put the smaller bytes32 first; only use the 64-byte scratch space.
                let order := shl(5, gt(node, sibling))
                mstore(order, node)
                mstore(xor(order, 32), sibling)
                node := keccak256(0, 64)
                cursor := add(cursor, 32)
            }
            allowed := eq(node, root)
        }
    }

    /// @notice Claim once for the caller. Invalid and repeated claims revert without data.
    function claim(bytes32[] calldata proof) external {
        // Verifying first shares the check path and minimizes bytecode.
        bool allowed = _verify(msg.sender, proof);
        assembly ("memory-safe") {
            if or(sload(caller()), iszero(allowed)) { revert(0, 0) }
            sstore(caller(), 1)
        }
        // Verification is internal; the runtime opcode test also checks that no calls exist.
        // forge-lint: disable-next-line(reentrancy-events)
        emit Claimed(msg.sender);
    }
}
