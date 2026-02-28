// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";

/**
 * @title SeedPrimitives
 * @notice Seeding script for Slide 1: Core Primitives
 * @dev Mints initial token balances to test actors
 */
contract SeedPrimitives is Script {
    
    struct SeedConfig {
        address collateralToken;
        address debtToken;
        address oracle;
        address[] actors;
        uint256 collateralAmount;
        uint256 debtAmount;
    }
    
    event ActorsSeeded(
        address indexed collateralToken,
        address indexed debtToken,
        uint256 actorCount,
        uint256 collateralPerActor,
        uint256 debtPerActor
    );
    
    /**
     * @notice Mint tokens to test actors
     * @param collateral MockERC20 collateral token
     * @param debt MockERC20 debt token
     * @param actors Array of actor addresses to seed
     * @param collateralAmount Amount of collateral per actor
     * @param debtAmount Amount of debt tokens per actor
     */
    function seedActors(
        MockERC20 collateral,
        MockERC20 debt,
        address[] memory actors,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal {
        require(address(collateral) != address(0), "SeedPrimitives: invalid collateral");
        require(address(debt) != address(0), "SeedPrimitives: invalid debt");
        require(actors.length > 0, "SeedPrimitives: no actors");
        
        console.log("========================================");
        console.log("Seeding Actors");
        console.log("========================================");
        console.log("Collateral per actor:", collateralAmount);
        console.log("Debt per actor:", debtAmount);
        console.log("Actor count:", actors.length);
        
        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];
            require(actor != address(0), "SeedPrimitives: zero address actor");
            
            // Mint collateral
            if (collateralAmount > 0) {
                collateral.mint(actor, collateralAmount);
                console.log("Minted", collateralAmount, "collateral to:", actor);
            }
            
            // Mint debt tokens
            if (debtAmount > 0) {
                debt.mint(actor, debtAmount);
                console.log("Minted", debtAmount, "debt to:", actor);
            }
        }
        
        emit ActorsSeeded(
            address(collateral),
            address(debt),
            actors.length,
            collateralAmount,
            debtAmount
        );
        
        console.log("========================================");
        console.log("Seeding Complete");
        console.log("========================================");
    }
    
    /**
     * @notice Run seeding with predefined test actors
     */
    function run() external {
        // These would normally come from config or environment
        address collateralToken = vm.envOr("COLLATERAL_TOKEN", address(0));
        address debtToken = vm.envOr("DEBT_TOKEN", address(0));
        
        require(collateralToken != address(0), "SeedPrimitives: COLLATERAL_TOKEN not set");
        require(debtToken != address(0), "SeedPrimitives: DEBT_TOKEN not set");
        
        MockERC20 collateral = MockERC20(collateralToken);
        MockERC20 debt = MockERC20(debtToken);
        
        // Define test actors
        address[] memory actors = new address[](5);
        actors[0] = makeAddr("actor1");
        actors[1] = makeAddr("actor2");
        actors[2] = makeAddr("actor3");
        actors[3] = makeAddr("actor4");
        actors[4] = makeAddr("actor5");
        
        vm.startBroadcast();
        
        seedActors(
            collateral,
            debt,
            actors,
            100 ether,  // 100 WETH per actor
            100000e6    // 100,000 USDC per actor
        );
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Run seeding with custom parameters
     * @param collateralToken Collateral token address
     * @param debtToken Debt token address
     * @param collateralAmount Amount per actor
     * @param debtAmount Amount per actor
     */
    function runCustom(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) external {
        require(collateralToken != address(0), "SeedPrimitives: invalid collateral");
        require(debtToken != address(0), "SeedPrimitives: invalid debt");
        
        MockERC20 collateral = MockERC20(collateralToken);
        MockERC20 debt = MockERC20(debtToken);
        
        // Define test actors
        address[] memory actors = new address[](3);
        actors[0] = makeAddr("testActor1");
        actors[1] = makeAddr("testActor2");
        actors[2] = makeAddr("testActor3");
        
        vm.startBroadcast();
        
        seedActors(collateral, debt, actors, collateralAmount, debtAmount);
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Seed a single actor (useful for quick tests)
     * @param collateralToken Collateral token address
     * @param debtToken Debt token address
     * @param actor Address to seed
     * @param collateralAmount Amount of collateral
     * @param debtAmount Amount of debt tokens
     */
    function runSingle(
        address collateralToken,
        address debtToken,
        address actor,
        uint256 collateralAmount,
        uint256 debtAmount
    ) external {
        require(actor != address(0), "SeedPrimitives: invalid actor");
        
        MockERC20 collateral = MockERC20(collateralToken);
        MockERC20 debt = MockERC20(debtToken);
        
        address[] memory actors = new address[](1);
        actors[0] = actor;
        
        vm.startBroadcast();
        
        seedActors(collateral, debt, actors, collateralAmount, debtAmount);
        
        vm.stopBroadcast();
    }
}
