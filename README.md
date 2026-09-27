# Allowlist Claim

A value-free Solidity 0.8.26 contract that records one claim per allowlisted
address. The deployed allowlist runtime is **435 bytes**. The allowlist has no token
integration, owner, administration, setter, upgrade mechanism, external call, or
payable entry point. The repository also supplies the separate `LaunchToken`
artifact required by the contributor network's launch checks.

`new AllowlistClaim(bytes32 root)` embeds the supplied root immutably in runtime
code. `isAllowed(address account, bytes32[] proof)` verifies membership without
changing state. `claim(bytes32[] proof)` verifies **msg.sender**, records its first
claim, and emits `Claimed(address indexed account)`. Invalid proofs and repeat
claims revert with empty revert data. `claimed(address)` reports the stored flag.
Membership remains true after a successful claim.

## Merkle format and assumptions

Compute each leaf as `keccak256(abi.encodePacked(account))`: a **single hash of
exactly 20 address bytes**. Starting at that leaf, process siblings in proof order
from leaf to root. At each step, compare the two `bytes32` values and hash the
64-byte concatenation `min || max`. This is the OpenZeppelin MerkleProof
sorted-pair convention. Leaf positions do not need direction bits; the proof
array itself must retain its bottom-up order.

Do not use the default double-hashed, ABI-padded address leaves of
`StandardMerkleTree`. An empty proof is valid for a single-leaf tree whose root
equals the address leaf. Any constructor root, including zero, is accepted; zero
does not act as a wildcard. Duplicate addresses in the tree still get only one
claim. Account types are unrestricted; contracts can claim for their own address.
The zero address is not specially excluded, though it has no ordinary signer.

The allowlist publisher chooses the tree shape, generates the root and proofs,
and makes proofs available to members. Tree construction must use the same
shape throughout; this contract only folds the supplied sibling path. Membership
relies on Keccak-256 collision/preimage resistance. Proofs are public, but copying
someone else's proof does not authorize a different caller. Claims are per
deployment and have no deadline or cross-chain replay restriction.

## Build and tests

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity **0.8.26**, the Cancun EVM target, the IR compiler
pipeline, optimizer runs **1**, and disables the CBOR metadata trailer. FFI and
filesystem cheatcode access are disabled. Foundry and the pinned compiler must
already be installed for offline verification. The complete test/tooling
dependency, forge-std v1.9.7, is vendored in `lib/forge-std/` with its licenses;
there are no submodules or package downloads during build/test. The deployed
contract has no library dependency.

The allowlist and deployment tests cover valid and invalid proofs, the indexed event, unauthorized
callers, double claims, independent claimants, rollback after failure, empty
proofs, equal siblings, duplicate addresses, zero roots, incorrect leaf formats,
an independent fixed vector, reversed proof order, malformed ABI input, ETH
rejection, and a runtime opcode/size check. Fuzz tests cover leaf position in
trees of 1–64 leaves, arbitrary sibling paths against a high-level reference,
and arbitrary claimant addresses. Deployment-script tests exercise the supplied
root and wrong-chain rejection. Tests require no RPC, environment variables,
keys, or filesystem reads and work in parallel.

Token tests cover factory deployment, metadata and fixed supply, exact transfers,
transfer events, supply conservation under fuzzing, zero and self transfers,
allowance replacement/revocation, finite and unlimited delegated transfers,
insufficient balances/allowances, rollback, invalid recipients, ETH rejection,
and absence of common administrative entry points and forbidden runtime opcodes.
All **34 project tests** pass. The supplied protected checks require deployment
parameters and are not part of the ordinary project test suite. For this repair,
all **8 protected checks** also passed locally using the compiled creation
bytecode, a simulated CREATE2 factory, and the report's demo Merkle root. This
checks local deployment behavior; it is not evidence of a Sepolia transaction.

## Separate launch token

`src/LaunchToken.sol:LaunchToken` is a standalone ERC-20 named **Allowlist Claim**
with symbol **ALLOW**, **18 decimals**, and exactly **1,000,000,000 tokens**
(**10^27 minor units**). Its nonpayable constructor takes **no arguments** and
mints the entire supply to `msg.sender`, emitting the standard mint `Transfer`
event. When the launch factory deploys it, the factory receives the entire supply.
There is no subsequent mint, burn, owner, fee, pause, blocklist, upgrade path, or
external call. Transfers preserve supply and reject the zero recipient.

`approve` sets an allowance, including zero to revoke; `transferFrom` reduces finite
allowances and preserves `type(uint256).max` as unlimited approval. Replacing a
nonzero allowance requires care: the holder should revoke it and wait for
confirmation before granting a different amount if the spender is untrusted.
The launch operator is responsible for the factory deployment and supply
distribution. The deployer receives tokens but no administrative privileges.
Allowlist claims confer no token entitlement, and the allowlist never references
this token. The existing `Deploy` script deploys only `AllowlistClaim`; a launch
system must deploy the token separately with zero ETH and no constructor arguments.

## Gas and size report

Measured with Foundry 1.8.3 and the pinned configuration on a fresh local Anvil
instance running Cancun:

| Measurement | Result |
| --- | ---: |
| Deployed runtime | **435 bytes** |
| Creation bytecode, excluding constructor argument | 547 bytes |
| Successful `claim()` transaction, proof depth 2 | **46,359 gas** |
| Of that: transaction base cost and calldata | 22,356 gas |
| Of that: EVM execution | 24,003 gas |

The measurement is a real local transaction receipt, with an initially unclaimed
address, a cold storage slot, no access list, and zero ETH value. It includes the
event and the first storage write. Gas varies with proof depth and calldata;
these figures are not a Sepolia receipt. The exact four-member tree, root,
claimant, proof and calldata are in [`reports/gas-and-size.json`](reports/gas-and-size.json).
Those members are Anvil demo accounts, not a proposed live allowlist.

Reproduce the measurements with Foundry and Python 3 (standard library only):

```sh
forge build --sizes
python3 script/measure.py
```

The Python tool starts and stops its own local node and never uses an external
RPC or a real wallet. It verifies membership, transaction success, stored claim
status and the emitted event before printing the report.

Size comparisons under the same compiler settings: a Solidity boolean mapping
version was 519 bytes; a uint256 mapping was 505 bytes; direct address slots with
separate claim checks were 447 bytes; combining checks and using scratch-memory
returns and a decrementing proof loop produced 435 bytes. The legacy compiler
pipeline was larger. This is the smallest measured implementation here, not a
proof of the theoretical minimum.

To keep the code small, the root has no getter, errors have no strings, proof
hashing uses only 64 bytes of scratch memory, and claim flags live at storage slot
`uint256(uint160(account))`. No other mutable state exists, so these slots cannot
collide with another variable. The root resides in code, not storage. Only 0 and
1 can occur in claim slots. This layout must not be combined with inheritance
that adds storage. Proof verification runs before the duplicate check, favoring
bytecode size over the gas cost of repeated attempts. Solidity's ABI decoder
still rejects truncated proofs and malformed addresses.

## Sepolia deployment and operation

**Deployment is pending:** no intended live root, funded signer, or deployment
transaction was provided. There is no claimed Sepolia contract address or
transaction hash. A tested deployment script is included at `script/Deploy.s.sol`.

Deployment parameters:

| Parameter | Value |
| --- | --- |
| Network | Sepolia, chain ID **11155111** |
| Contract | `src/AllowlistClaim.sol:AllowlistClaim` |
| Constructor | One `bytes32 root`, chosen by the publisher |
| Transaction value | **0 wei** |
| Post-deployment initialization | None |
| Privileged deployer rights | None |

After selecting the reviewed root and a funded signing account, replace the
three placeholders below. The script takes the root as a function argument and
rejects other chains; it reads no environment variables. The signing account is
selected by Foundry's CLI and is not embedded in source.

```sh
forge script script/Deploy.s.sol:Deploy \
  --sig 'run(bytes32)' <ROOT_HEX> \
  --rpc-url <SEPOLIA_RPC_URL> --account <KEYSTORE_ACCOUNT> --broadcast
```

The publisher is responsible for checking the addresses, root and representative
proofs before signing, retaining the original root/constructor argument, and
publishing the contract address, chain ID, transaction hash and proof source.
After deployment, compare the returned runtime with the compiler artifact with
the immutable root patched, confirm its 435-byte length, and call `isAllowed`
with a known member and a known nonmember. Record the mined transaction and
contract address; source verification must use the pinned compiler settings and
the ABI-encoded constructor root. There is no root getter, so retain the
deployment record for later verification.

Claimants submit their own proof and pay network gas. Operators cannot reset
claims, alter the allowlist, transfer claims, recover a mistaken root, or withdraw
anything. Corrections require a new deployment and publishing its address. The
contract rejects ETH sent through its entry points; EVM mechanisms can still
force ETH to any address, and such ETH would remain inaccessible. Claims confer
no token, money, ownership, or other built-in entitlement.
