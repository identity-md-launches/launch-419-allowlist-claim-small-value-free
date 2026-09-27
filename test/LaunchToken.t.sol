// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract TokenFactory {
    function deploy() external returns (LaunchToken) {
        return new LaunchToken();
    }
}

contract LaunchTokenTest is Test {
    LaunchToken private token;
    uint256 private constant SUPPLY = 10 ** 27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new LaunchToken();
    }

    function testMetadataAndWholeSupplyBelongToDeployer() public view {
        assertEq(token.name(), "Allowlist Claim");
        assertEq(token.symbol(), "ALLOW");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFactoryDeploymentMintsOnlyToFactoryAndEmitsTransfer() public {
        TokenFactory factory = new TokenFactory();
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(factory), SUPPLY);
        vm.prank(ALICE);
        LaunchToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testTransferMovesExactAmountAndEmitsEvent() public {
        uint256 amount = SUPPLY / 1000;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, amount);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransfersConserveSupply(uint256 firstSeed, uint256 secondSeed) public {
        uint256 first = bound(firstSeed, 0, SUPPLY);
        uint256 second = bound(secondSeed, 0, first);
        assertTrue(token.transfer(ALICE, first));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, second));
        assertEq(token.balanceOf(address(this)), SUPPLY - first);
        assertEq(token.balanceOf(ALICE), first - second);
        assertEq(token.balanceOf(BOB), second);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroAndSelfTransfersPreserveBalances() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInsufficientBalanceRevertsWithoutChanges() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testZeroRecipientRevertsInsteadOfBurning() public {
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApproveEmitsAndSupportsReplacementAndRevocation() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), ALICE, 100);
        assertTrue(token.approve(ALICE, 100));
        assertEq(token.allowance(address(this), ALICE), 100);
        assertTrue(token.approve(ALICE, 50));
        assertEq(token.allowance(address(this), ALICE), 50);
        assertTrue(token.approve(ALICE, 0));
        assertEq(token.allowance(address(this), ALICE), 0);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function testTransferFromConsumesFiniteAllowanceAndMovesExactAmount() public {
        token.approve(ALICE, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), BOB, 60);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 60));
        assertEq(token.allowance(address(this), ALICE), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60);
        assertEq(token.balanceOf(BOB), 60);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromPreservesInfiniteAllowance() public {
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 100));
        assertEq(token.allowance(address(this), ALICE), type(uint256).max);
        assertEq(token.balanceOf(BOB), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
    }

    function testUnapprovedAndExcessiveDelegatedTransfersRevert() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        token.transferFrom(address(this), BOB, 1);
        token.approve(ALICE, 100);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ERC20InsufficientAllowance.selector, ALICE, 100, 101));
        token.transferFrom(address(this), BOB, 101);
        assertEq(token.allowance(address(this), ALICE), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testDelegatedTransferRevertsRestoreAllowanceAndEmitNoLogs() public {
        vm.prank(ALICE);
        token.approve(address(this), 100);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ERC20InsufficientBalance.selector, ALICE, 0, 50));
        token.transferFrom(ALICE, BOB, 50);
        assertEq(token.allowance(ALICE, address(this)), 100);
        assertEq(vm.getRecordedLogs().length, 0);

        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(ALICE, address(0), 50);
        assertEq(token.allowance(ALICE, address(this)), 100);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testCommonAdminAndMintSelectorsRevertForDeployerAndOutsider() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, SUPPLY);
            (bool ok,) = address(token).call(data);
            assertFalse(ok);
            vm.prank(ALICE);
            (ok,) = address(token).call(data);
            assertFalse(ok);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testRuntimeHasNoCallsCreationOrEscapeOpcodes() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf0 && op != 0xf1 && op != 0xf2 && op != 0xf4 && op != 0xf5 && op != 0xfa && op != 0xff);
        }
    }

    function testRejectsEthAndUnknownSelectors() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (ALICE, 1)));
        assertFalse(ok);
        (ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        bytes memory init = type(LaunchToken).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(init, 32), mload(init))
        }
        assertEq(deployed, address(0));
    }
}
