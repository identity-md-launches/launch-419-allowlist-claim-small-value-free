// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {AllowlistClaim} from "../src/AllowlistClaim.sol";

contract ScriptCaller {
    function deploy(Deploy script, bytes32 root) external returns (AllowlistClaim) {
        return script.run(root);
    }
}

contract DeployTest is Test {
    function testDeploymentUsesExplicitRootAndWorksForAnyCaller() public {
        vm.chainId(11155111);
        Deploy script = new Deploy();
        address member = address(0xCAFE);
        ScriptCaller caller = new ScriptCaller();
        AllowlistClaim deployed = caller.deploy(script, keccak256(abi.encodePacked(member)));
        bytes32[] memory proof = new bytes32[](0);
        assertTrue(deployed.isAllowed(member, proof));
        assertFalse(deployed.isAllowed(address(0xBEEF), proof));
        vm.prank(member);
        deployed.claim(proof);
        assertTrue(deployed.claimed(member));
    }

    function testDeploymentRejectsOtherChains() public {
        vm.chainId(1);
        Deploy script = new Deploy();
        vm.expectRevert("Sepolia only");
        script.run(bytes32(0));
    }
}
