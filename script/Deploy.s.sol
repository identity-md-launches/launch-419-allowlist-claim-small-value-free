// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {AllowlistClaim} from "../src/AllowlistClaim.sol";

/// @notice Pass the reviewed root explicitly; the CLI supplies the signing account.
contract Deploy is Script {
    function run(bytes32 root) external returns (AllowlistClaim deployed) {
        require(block.chainid == 11155111, "Sepolia only");
        vm.startBroadcast();
        deployed = new AllowlistClaim(root);
        vm.stopBroadcast();
    }
}
