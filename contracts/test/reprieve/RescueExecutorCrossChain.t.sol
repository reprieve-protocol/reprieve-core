// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";
import {CCIPClient} from "../../src/reprieve/libs/CCIPClient.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";

/**
 * @title RescueExecutorCrossChainTest
 * @notice Tests for RescueExecutor cross-chain CCIP functionality
 */
contract RescueExecutorCrossChainTest is Test {
    
    RescueExecutor executor;
    RescueEscrow rescueEscrow;
    RescueLog rescueLog;
    AdapterRegistry adapterRegistry;
    MockERC20 collateral;
    MockERC20 debt;
    
    address owner;
    address workflow;
    address ccipRouter;
    address user;
    address receiver;
    address minter;
    
    uint64 constant DEST_CHAIN_SELECTOR = 10344971235874465080; // Base Sepolia
    bytes32 constant EXEC_ID = keccak256("cross-chain-exec");
    
    function setUp() public {
        owner = address(this);
        workflow = makeAddr("workflow");
        ccipRouter = makeAddr("ccipRouter");
        user = makeAddr("user");
        receiver = makeAddr("receiver");
        minter = makeAddr("minter");
        
        // Deploy tokens
        collateral = new MockERC20("WETH", "WETH", 18, minter);
        debt = new MockERC20("USDC", "USDC", 6, minter);
        
        // Deploy Reprieve contracts
        rescueLog = new RescueLog(owner);
        rescueEscrow = new RescueEscrow(owner, address(rescueLog));
        adapterRegistry = new AdapterRegistry(owner);
        adapterRegistry.initializeDemoProtocols();
        
        executor = new RescueExecutor(owner, address(rescueLog), address(rescueEscrow), address(adapterRegistry));
        
        // Authorizations
        executor.setAuthorizedWorkflow(workflow, true);
        executor.setCcipRouter(ccipRouter);
        executor.setTrustedDestinationChain(DEST_CHAIN_SELECTOR, true);
        rescueLog.setAuthorizedWriter(address(executor), true);
        
        // Fund executor with tokens
        vm.prank(minter);
        collateral.mint(address(executor), 10000 ether);
        vm.prank(minter);
        debt.mint(address(executor), 10000 ether);
    }
    
    // ============ CCIP ROUTER CONFIGURATION TESTS ============
    
    function test_SetCcipRouter() public {
        address newRouter = makeAddr("newRouter");
        executor.setCcipRouter(newRouter);
        assertEq(executor.ccipRouter(), newRouter);
    }
    
    function test_SetCcipRouter_OnlyOwner() public {
        vm.prank(workflow);
        vm.expectRevert();
        executor.setCcipRouter(address(0));
    }
    
    function test_SetTrustedDestinationChain() public {
        uint64 newChain = 3478487238524512106; // Arbitrum Sepolia
        executor.setTrustedDestinationChain(newChain, true);
        assertTrue(executor.trustedDestinationChains(newChain));
    }
    
    function test_SetTrustedDestinationChain_OnlyOwner() public {
        vm.prank(workflow);
        vm.expectRevert();
        executor.setTrustedDestinationChain(DEST_CHAIN_SELECTOR, false);
    }
    
    // ============ CCIP EXTRA ARGS TESTS ============
    
    function test_SetCcipExtraArgs() public {
        bytes memory extraArgs = CCIPClient.buildExtraArgs(500000, true);
        executor.setCcipExtraArgs(DEST_CHAIN_SELECTOR, extraArgs);
        assertEq(executor.ccipExtraArgs(DEST_CHAIN_SELECTOR), extraArgs);
    }
    
    function test_SetDefaultCcipParams() public {
        executor.setDefaultCcipParams(400000, false);
        assertEq(executor.defaultGasLimit(), 400000);
        assertFalse(executor.defaultAllowOutOfOrderExecution());
    }
    
    // ============ CCIP INITIATE TESTS ============
    
    function test_InitiateCrossChainLeg_RevertsWhenRouterNotSet() public {
        // Deploy new executor without router
        RescueExecutor newExecutor = new RescueExecutor(
            owner,
            address(rescueLog),
            address(rescueEscrow),
            address(adapterRegistry)
        );
        newExecutor.setAuthorizedWorkflow(workflow, true);
        newExecutor.setTrustedDestinationChain(DEST_CHAIN_SELECTOR, true);
        
        vm.prank(workflow);
        vm.expectRevert(ReprieveErrors.CCIPRouterNotSet.selector);
        newExecutor.initiateCrossChainLeg(
            DEST_CHAIN_SELECTOR,
            receiver,
            user,
            EXEC_ID,
            address(collateral),
            1000 ether,
            address(0),
            address(debt),
            1000e6,
            0,
            address(0)
        );
    }
    
    function test_InitiateCrossChainLeg_RevertsWhenDestinationNotTrusted() public {
        uint64 untrustedChain = 999999;
        
        vm.prank(workflow);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.CCIPDestinationNotAllowed.selector, untrustedChain));
        executor.initiateCrossChainLeg(
            untrustedChain,
            receiver,
            user,
            EXEC_ID,
            address(collateral),
            1000 ether,
            address(0),
            address(debt),
            1000e6,
            0,
            address(0)
        );
    }
    
    // ============ QUOTE FEE TESTS ============
    
    function test_QuoteCcipFee_ReturnsZeroWhenRouterNotSet() public {
        // Deploy new executor without router
        RescueExecutor newExecutor = new RescueExecutor(
            owner,
            address(rescueLog),
            address(rescueEscrow),
            address(adapterRegistry)
        );
        
        uint256 fee = newExecutor.quoteCcipFee(DEST_CHAIN_SELECTOR, "");
        assertEq(fee, 0);
    }
    
    // ============ CCIP MESSAGE ID TESTS ============
    
    function test_GetCcipMessageId() public {
        // Initially should be zero
        assertEq(executor.getCcipMessageId(EXEC_ID), bytes32(0));
    }
    
    // ============ RECEIVE NATIVE TESTS ============
    
    function test_ReceiveNative() public {
        // Executor should accept native tokens for CCIP fees
        (bool success, ) = address(executor).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(executor).balance, 1 ether);
    }
}
