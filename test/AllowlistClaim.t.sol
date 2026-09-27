// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AllowlistClaim} from "../src/AllowlistClaim.sol";

contract AllowlistClaimTest is Test {
    AllowlistClaim private allowlist;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant OUTSIDER = address(0xBAD);

    event Claimed(address indexed account);

    function setUp() public {
        allowlist = new AllowlistClaim(_pair(_leaf(ALICE), _leaf(BOB)));
    }

    function testValidProofAndClaimEvent() public {
        bytes32[] memory proof = _proof(_leaf(BOB));
        assertTrue(allowlist.isAllowed(ALICE, proof));
        assertFalse(allowlist.claimed(ALICE));
        vm.expectEmit(true, false, false, true, address(allowlist));
        emit Claimed(ALICE);
        vm.prank(ALICE);
        allowlist.claim(proof);
        assertTrue(allowlist.claimed(ALICE));
        assertFalse(allowlist.claimed(BOB));
        // Membership remains true after claiming; it is independent of claim status.
        assertTrue(allowlist.isAllowed(ALICE, proof));
    }

    function testInvalidProofRevertsWithoutStateOrLogs() public {
        bytes32[] memory proof = _proof(bytes32(uint256(123)));
        assertFalse(allowlist.isAllowed(ALICE, proof));
        vm.recordLogs();
        vm.prank(ALICE);
        vm.expectRevert();
        allowlist.claim(proof);
        assertFalse(allowlist.claimed(ALICE));
        assertEq(vm.getRecordedLogs().length, 0);
        // A failed attempt does not consume the claim.
        vm.prank(ALICE);
        allowlist.claim(_proof(_leaf(BOB)));
        assertTrue(allowlist.claimed(ALICE));
    }

    function testProofCannotBeUsedByAnotherCaller() public {
        bytes32[] memory proof = _proof(_leaf(BOB));
        assertFalse(allowlist.isAllowed(OUTSIDER, proof));
        vm.prank(OUTSIDER);
        vm.expectRevert();
        allowlist.claim(proof);
        assertFalse(allowlist.claimed(OUTSIDER));
        assertFalse(allowlist.claimed(ALICE));
    }

    function testDoubleClaimReverts() public {
        bytes32[] memory proof = _proof(_leaf(BOB));
        vm.startPrank(ALICE);
        allowlist.claim(proof);
        vm.expectRevert();
        allowlist.claim(proof);
        vm.stopPrank();
        assertTrue(allowlist.claimed(ALICE));
    }

    function testBothSortedPairOrdersAndIndependentClaims() public {
        vm.prank(ALICE);
        allowlist.claim(_proof(_leaf(BOB)));
        vm.prank(BOB);
        allowlist.claim(_proof(_leaf(ALICE)));
        assertTrue(allowlist.claimed(ALICE));
        assertTrue(allowlist.claimed(BOB));
    }

    function testSingleLeafUsesEmptyProof() public {
        AllowlistClaim single = new AllowlistClaim(_leaf(ALICE));
        bytes32[] memory empty = new bytes32[](0);
        assertTrue(single.isAllowed(ALICE, empty));
        assertFalse(single.isAllowed(BOB, empty));
        vm.prank(ALICE);
        single.claim(empty);
        assertTrue(single.claimed(ALICE));
        assertFalse(single.isAllowed(ALICE, _proof(_leaf(BOB))));
    }

    function testFixedTwoLevelVectorAndProofOrder() public {
        // Generated independently with cast keccak; also used by script/measure.py.
        address member = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        AllowlistClaim vector = new AllowlistClaim(0xd4453790033a2bd762f526409b7f358023773723d9e9bc42487e4996869162b6);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0x00314e565e0574cb412563df634608d76f5c59d9f817e85966100ec1d48005c0;
        proof[1] = 0x7e0eefeb2d8740528b8f598997a219669f0842302d3c573e9bb7262be3387e63;
        assertTrue(vector.isAllowed(member, proof));
        (proof[0], proof[1]) = (proof[1], proof[0]);
        assertFalse(vector.isAllowed(member, proof));
        vm.prank(member);
        vm.expectRevert();
        vector.claim(proof);
        (proof[0], proof[1]) = (proof[1], proof[0]);
        vm.prank(member);
        vector.claim(proof);
        assertTrue(vector.claimed(member));
    }

    function testZeroRootIsAcceptedButDoesNotAuthorizeAnEmptyProof() public {
        AllowlistClaim zeroRoot = new AllowlistClaim(bytes32(0));
        bytes32[] memory empty = new bytes32[](0);
        assertFalse(zeroRoot.isAllowed(ALICE, empty));
        vm.prank(ALICE);
        vm.expectRevert();
        zeroRoot.claim(empty);
    }

    function testLeavesArePackedSingleHashes() public {
        bytes32[] memory empty = new bytes32[](0);
        AllowlistClaim padded = new AllowlistClaim(keccak256(abi.encode(ALICE)));
        AllowlistClaim doubleHashed = new AllowlistClaim(keccak256(abi.encodePacked(_leaf(ALICE))));
        assertFalse(padded.isAllowed(ALICE, empty));
        assertFalse(doubleHashed.isAllowed(ALICE, empty));
    }

    function testEqualSiblingsAndDuplicateAddressesStillClaimOnlyOnce() public {
        bytes32 leaf = _leaf(ALICE);
        AllowlistClaim duplicates = new AllowlistClaim(_pair(leaf, leaf));
        bytes32[] memory proof = _proof(leaf);
        assertTrue(duplicates.isAllowed(ALICE, proof));
        vm.startPrank(ALICE);
        duplicates.claim(proof);
        vm.expectRevert();
        duplicates.claim(proof);
        vm.stopPrank();
    }

    function testUnknownSelectorsEmptyCalldataAndValueRevert() public {
        (bool ok,) = address(allowlist).call("");
        assertFalse(ok);
        (ok,) = address(allowlist).call(hex"deadbeef");
        assertFalse(ok);
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (ok,) = address(allowlist).call{value: 1}(abi.encodeCall(allowlist.claim, (_proof(_leaf(BOB)))));
        assertFalse(ok);
        assertFalse(allowlist.claimed(ALICE));
        assertEq(address(allowlist).balance, 0);
    }

    function testConstructorRejectsValue() public {
        vm.deal(address(this), 1 ether);
        bytes memory init = abi.encodePacked(type(AllowlistClaim).creationCode, abi.encode(_leaf(ALICE)));
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(init, 32), mload(init))
        }
        assertEq(deployed, address(0));
    }

    function testMalformedAbiReverts() public {
        // Missing address, missing proof offset, truncated array, overflowed offset and length.
        _assertMalformed(abi.encodePacked(allowlist.claimed.selector));
        _assertMalformed(abi.encodePacked(allowlist.isAllowed.selector, bytes32(uint256(uint160(ALICE)))));
        _assertMalformed(abi.encodePacked(allowlist.claim.selector, uint256(32), uint256(1)));
        _assertMalformed(abi.encodePacked(allowlist.claim.selector, type(uint256).max));
        _assertMalformed(abi.encodePacked(allowlist.claim.selector, uint256(32), type(uint256).max));
        // Dirty high address bits must not alias a valid address.
        _assertMalformed(abi.encodePacked(allowlist.claimed.selector, uint256(1) << 160));
    }

    function testRuntimeIsSmallAndContainsNoCallsOrEscapeOpcodes() public view {
        bytes memory code = address(allowlist).code;
        assertLe(code.length, 435);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(
                op != 0xf0 && op != 0xf1 && op != 0xf2 && op != 0xf4 && op != 0xf5 && op != 0xfa && op != 0xff,
                "creation, external call or escape opcode"
            );
        }
    }

    function testFuzzLeafPosition(uint160 seed, uint8 depthSeed, uint256 positionSeed) public {
        uint256 depth = depthSeed % 7;
        uint256 width = uint256(1) << depth;
        uint256 position = positionSeed % width;
        // This high-level reference implementation shares no assembly with the contract.
        bytes32[] memory tree = new bytes32[](2 * width);
        for (uint256 i; i < width; ++i) {
            tree[width + i] = _leaf(_account(seed, i));
        }
        for (uint256 i = width - 1; i > 0; --i) {
            tree[i] = _pair(tree[2 * i], tree[2 * i + 1]);
        }
        bytes32[] memory proof = new bytes32[](depth);
        uint256 cursor = width + position;
        for (uint256 i; i < depth; ++i) {
            proof[i] = tree[cursor ^ 1];
            cursor /= 2;
        }
        address account = _account(seed, position);
        AllowlistClaim target = new AllowlistClaim(tree[1]);
        assertTrue(target.isAllowed(account, proof));
        assertFalse(target.claimed(account));
        assertFalse(target.isAllowed(_account(seed, width), proof));
        if (depth != 0) {
            proof[0] ^= bytes32(uint256(1));
            assertFalse(target.isAllowed(account, proof));
            vm.prank(account);
            vm.expectRevert();
            target.claim(proof);
            assertFalse(target.claimed(account));
            proof[0] ^= bytes32(uint256(1));
        }
        vm.startPrank(account);
        target.claim(proof);
        assertTrue(target.claimed(account));
        vm.expectRevert();
        target.claim(proof);
        vm.stopPrank();
    }

    function testFuzzArbitraryProofMatchesReference(address account, bytes32[] memory proof, bytes32 randomRoot)
        public
    {
        bytes32 node = _leaf(account);
        for (uint256 i; i < proof.length; ++i) {
            node = _pair(node, proof[i]);
        }
        AllowlistClaim matching = new AllowlistClaim(node);
        assertTrue(matching.isAllowed(account, proof));
        AllowlistClaim random = new AllowlistClaim(randomRoot);
        assertEq(random.isAllowed(account, proof), node == randomRoot);
    }

    function testFuzzSingleLeafAndClaimedStorage(address account) public {
        AllowlistClaim single = new AllowlistClaim(_leaf(account));
        bytes32[] memory empty = new bytes32[](0);
        assertTrue(single.isAllowed(account, empty));
        assertFalse(single.claimed(account));
        vm.prank(account);
        single.claim(empty);
        assertTrue(single.claimed(account));
        assertFalse(single.claimed(address(uint160(account) ^ 1)));
    }

    function _assertMalformed(bytes memory data) private {
        (bool ok,) = address(allowlist).call(data);
        assertFalse(ok);
    }

    function _account(uint160 seed, uint256 offset) private pure returns (address) {
        unchecked {
            return address(seed + uint160(offset));
        }
    }

    function _leaf(address account) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(account));
    }

    function _pair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }

    function _proof(bytes32 sibling) private pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = sibling;
    }
}
