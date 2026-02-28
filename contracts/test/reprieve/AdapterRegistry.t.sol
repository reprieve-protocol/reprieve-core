// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";
import {IAdapterRegistry} from "../../src/reprieve/interfaces/IAdapterRegistry.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";

/**
 * @title AdapterRegistryTest
 * @notice Slide 2 validation: Adapter Registry and Protocol Wiring
 */
contract AdapterRegistryTest is Test {
    // Events from interface for testing
    event AdapterSet(bytes32 indexed protocolId, address adapter);
    event ProtocolSupported(bytes32 indexed protocolId, bool supported);
    
    AdapterRegistry registry;
    address owner;
    address notOwner;
    
    // Dummy adapter addresses
    address aaveAdapter = address(0xAA111);
    address compoundAdapter = address(0xBB222);
    address morphoAdapter = address(0xCC333);
    address newAaveAdapter = address(0xAA444);
    
    function setUp() public {
        owner = address(this);
        notOwner = makeAddr("notOwner");
        
        registry = new AdapterRegistry(owner);
        
        // Initialize demo protocols
        registry.initializeDemoProtocols();
    }
    
    // ============ INITIALIZATION TESTS ============
    
    function test_InitializeDemoProtocols() public view {
        // Verify all three protocols are supported
        assertTrue(registry.isSupportedProtocol(registry.AAVE_LIKE()));
        assertTrue(registry.isSupportedProtocol(registry.COMPOUND_LIKE()));
        assertTrue(registry.isSupportedProtocol(registry.MORPHO_LIKE()));
    }
    
    function test_ProtocolIdConstants() public view {
        // Verify protocol IDs match expected keccak256 hashes
        assertEq(registry.AAVE_LIKE(), keccak256("AAVE_LIKE"));
        assertEq(registry.COMPOUND_LIKE(), keccak256("COMPOUND_LIKE"));
        assertEq(registry.MORPHO_LIKE(), keccak256("MORPHO_LIKE"));
    }
    
    // ============ SET ADAPTER TESTS ============
    
    function test_SetAdapter() public {
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        
        assertEq(registry.getAdapter(registry.AAVE_LIKE()), aaveAdapter);
        assertTrue(registry.hasAdapter(registry.AAVE_LIKE()));
    }
    
    function test_SetAdapter_AllThree() public {
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        registry.setAdapter(registry.COMPOUND_LIKE(), compoundAdapter);
        registry.setAdapter(registry.MORPHO_LIKE(), morphoAdapter);
        
        assertEq(registry.getAdapter(registry.AAVE_LIKE()), aaveAdapter);
        assertEq(registry.getAdapter(registry.COMPOUND_LIKE()), compoundAdapter);
        assertEq(registry.getAdapter(registry.MORPHO_LIKE()), morphoAdapter);
        assertEq(registry.protocolCount(), 3);
    }
    
    function test_SetAdapter_ReplaceExisting() public {
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        registry.setAdapter(registry.AAVE_LIKE(), newAaveAdapter);
        
        assertEq(registry.getAdapter(registry.AAVE_LIKE()), newAaveAdapter);
        assertEq(registry.protocolCount(), 1); // Should still be 1, not 2
    }
    
    function test_SetAdapter_OnlyOwner() public {
        bytes32 aaveId = registry.AAVE_LIKE();
        vm.prank(notOwner);
        vm.expectRevert();
        registry.setAdapter(aaveId, aaveAdapter);
    }
    
    function test_SetAdapter_ZeroAddressReverts() public {
        bytes32 aaveId = registry.AAVE_LIKE();
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        registry.setAdapter(aaveId, address(0));
    }
    
    function test_SetAdapter_UnsupportedProtocolReverts() public {
        bytes32 unsupportedId = keccak256("UNSUPPORTED");
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnsupportedProtocol.selector, unsupportedId));
        registry.setAdapter(unsupportedId, aaveAdapter);
    }
    
    // ============ GET ADAPTER TESTS ============
    
    function test_GetAdapter_InvalidAdapterReverts() public {
        bytes32 nonExistentId = keccak256("NONEXISTENT");
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.InvalidAdapter.selector, nonExistentId));
        registry.getAdapter(nonExistentId);
    }
    
    // ============ SET MANY TESTS ============
    
    function test_SetMany() public {
        bytes32[] memory ids = new bytes32[](3);
        ids[0] = registry.AAVE_LIKE();
        ids[1] = registry.COMPOUND_LIKE();
        ids[2] = registry.MORPHO_LIKE();
        
        address[] memory addrs = new address[](3);
        addrs[0] = aaveAdapter;
        addrs[1] = compoundAdapter;
        addrs[2] = morphoAdapter;
        
        registry.setMany(ids, addrs);
        
        assertEq(registry.getAdapter(registry.AAVE_LIKE()), aaveAdapter);
        assertEq(registry.getAdapter(registry.COMPOUND_LIKE()), compoundAdapter);
        assertEq(registry.getAdapter(registry.MORPHO_LIKE()), morphoAdapter);
    }
    
    function test_SetMany_ArrayLengthMismatchReverts() public {
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = registry.AAVE_LIKE();
        ids[1] = registry.COMPOUND_LIKE();
        
        address[] memory addrs = new address[](3);
        addrs[0] = aaveAdapter;
        addrs[1] = compoundAdapter;
        addrs[2] = morphoAdapter;
        
        vm.expectRevert(ReprieveErrors.ArrayLengthMismatch.selector);
        registry.setMany(ids, addrs);
    }
    
    // ============ SUPPORTED PROTOCOL TESTS ============
    
    function test_SetSupportedProtocol() public {
        bytes32 newProtocol = keccak256("NEW_PROTOCOL");
        
        registry.setSupportedProtocol(newProtocol, true);
        assertTrue(registry.isSupportedProtocol(newProtocol));
        
        registry.setSupportedProtocol(newProtocol, false);
        assertFalse(registry.isSupportedProtocol(newProtocol));
    }
    
    function test_SetSupportedProtocol_OnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        registry.setSupportedProtocol(keccak256("NEW"), true);
    }
    
    // ============ EVENT TESTS ============
    
    function test_SetAdapter_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit AdapterSet(registry.AAVE_LIKE(), aaveAdapter);
        
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
    }
    
    function test_SetSupportedProtocol_EmitsEvent() public {
        bytes32 newProtocol = keccak256("NEW");
        
        vm.expectEmit(true, false, false, true);
        emit ProtocolSupported(newProtocol, true);
        
        registry.setSupportedProtocol(newProtocol, true);
    }
    
    // ============ GET ALL PROTOCOL IDS TESTS ============
    
    function test_GetAllProtocolIds() public {
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        registry.setAdapter(registry.COMPOUND_LIKE(), compoundAdapter);
        
        bytes32[] memory ids = registry.getAllProtocolIds();
        
        assertEq(ids.length, 2);
        assertEq(ids[0], registry.AAVE_LIKE());
        assertEq(ids[1], registry.COMPOUND_LIKE());
    }
    
    function test_ProtocolCount_ZeroInitially() public view {
        // Protocols are supported but no adapters set yet
        assertEq(registry.protocolCount(), 0);
    }
    
    function test_ProtocolCount_AfterSetting() public {
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        assertEq(registry.protocolCount(), 1);
        
        registry.setAdapter(registry.COMPOUND_LIKE(), compoundAdapter);
        assertEq(registry.protocolCount(), 2);
        
        registry.setAdapter(registry.MORPHO_LIKE(), morphoAdapter);
        assertEq(registry.protocolCount(), 3);
    }
    
    // ============ SIMULATED EXECUTOR FLOW TESTS ============
    
    function test_ExecutorFlow_ResolveAllAdapters() public {
        // Simulate executor resolving adapters
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        registry.setAdapter(registry.COMPOUND_LIKE(), compoundAdapter);
        registry.setAdapter(registry.MORPHO_LIKE(), morphoAdapter);
        
        // Executor queries all adapters
        address aave = registry.getAdapter(registry.AAVE_LIKE());
        address compound = registry.getAdapter(registry.COMPOUND_LIKE());
        address morpho = registry.getAdapter(registry.MORPHO_LIKE());
        
        assertEq(aave, aaveAdapter);
        assertEq(compound, compoundAdapter);
        assertEq(morpho, morphoAdapter);
    }
    
    function test_ExecutorFlow_HasAdapterCheck() public {
        // Executor checks if adapter exists before using
        assertFalse(registry.hasAdapter(registry.AAVE_LIKE()));
        
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        assertTrue(registry.hasAdapter(registry.AAVE_LIKE()));
    }
}
