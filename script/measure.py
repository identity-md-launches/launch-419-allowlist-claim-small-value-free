#!/usr/bin/env python3
"""Reproduce the report using a fresh, local Cancun Anvil instance (no external RPC)."""

import json
from pathlib import Path
import socket
import subprocess
import time
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[1]


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def keccak(data):
    return command("cast", "keccak", "0x" + data.hex())


def pair(a, b):
    return keccak(bytes.fromhex("".join(sorted([a[2:], b[2:]]))))


def main():
    subprocess.run(["forge", "build", "--quiet"], cwd=ROOT, check=True)
    artifact = json.loads((ROOT / "out/AllowlistClaim.sol/AllowlistClaim.json").read_text())
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    node = subprocess.Popen(
        [
            "anvil", "--silent", "--host", "127.0.0.1", "--port", str(port),
            "--hardfork", "cancun", "--chain-id", "31337",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    def rpc(method, *params):
        payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}", payload, {"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            result = json.load(response)
        if "error" in result:
            raise RuntimeError(result["error"])
        return result["result"]

    def transact(tx):
        tx_hash = rpc("eth_sendTransaction", {**tx, "gas": hex(2_000_000)})
        for _ in range(100):
            receipt = rpc("eth_getTransactionReceipt", tx_hash)
            if receipt:
                if int(receipt["status"], 16) != 1:
                    raise RuntimeError(f"Local transaction reverted: {tx_hash}")
                return receipt
            time.sleep(0.05)
        raise RuntimeError("Local transaction did not receive a receipt")

    try:
        for _ in range(100):
            if node.poll() is not None:
                raise RuntimeError("Anvil exited before becoming ready")
            try:
                accounts = rpc("eth_accounts")
                break
            except (urllib.error.URLError, TimeoutError):
                time.sleep(0.05)
        else:
            raise RuntimeError("Anvil did not start")

        members = accounts[:4]
        leaves = [keccak(bytes.fromhex(account[2:])) for account in members]
        right = pair(leaves[2], leaves[3])
        root = pair(pair(leaves[0], leaves[1]), right)
        proof = [leaves[1], right]
        proof_arg = "[" + ",".join(proof) + "]"
        creation = artifact["bytecode"]["object"]
        deployment = transact({"from": members[0], "data": creation + root[2:]})
        address = deployment["contractAddress"]
        runtime = rpc("eth_getCode", address, "latest")

        allowed_data = command("cast", "calldata", "isAllowed(address,bytes32[])", members[0], proof_arg)
        assert int(rpc("eth_call", {"to": address, "data": allowed_data}, "latest"), 16) == 1
        claim_data = command("cast", "calldata", "claim(bytes32[])", proof_arg)
        receipt = transact({"from": members[0], "to": address, "data": claim_data})
        claimed_data = command("cast", "calldata", "claimed(address)", members[0])
        assert int(rpc("eth_call", {"to": address, "data": claimed_data}, "latest"), 16) == 1
        assert len(receipt["logs"]) == 1
        assert receipt["logs"][0]["topics"] == [
            keccak(b"Claimed(address)"), "0x" + members[0][2:].rjust(64, "0")
        ]
        calldata = bytes.fromhex(claim_data[2:])
        intrinsic = 21_000 + sum(4 if byte == 0 else 16 for byte in calldata)
        gas = int(receipt["gasUsed"], 16)
        report = {
            "network": "local Anvil; not a Sepolia deployment",
            "hardfork": "cancun",
            "compiler": "0.8.26",
            "optimizer_runs": 1,
            "via_ir": True,
            "metadata": "no CBOR trailer",
            "forge": command("forge", "--version").splitlines()[0],
            "runtime_bytes": (len(runtime) - 2) // 2,
            "creation_bytes_without_arguments": (len(creation) - 2) // 2,
            "constructor_root": root,
            "members": members,
            "claimant": members[0],
            "proof": proof,
            "proof_depth": len(proof),
            "claim_transaction_gas": gas,
            "claim_intrinsic_gas": intrinsic,
            "claim_execution_gas": gas - intrinsic,
            "claim_calldata": claim_data,
        }
        print(json.dumps(report, indent=2))
    finally:
        node.terminate()
        try:
            node.wait(timeout=5)
        except subprocess.TimeoutExpired:
            node.kill()
            node.wait()


if __name__ == "__main__":
    main()
