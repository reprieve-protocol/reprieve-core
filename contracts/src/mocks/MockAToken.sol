// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

/**
 * @title MockAToken
 * @notice Minimal Aave-style aToken for Reprieve demo
 * @dev Receipt token for position tracking + approval flow
 */
contract MockAToken is ERC20 {
    address public immutable underlying;
    address public immutable pool;
    uint8 private immutable _decimals;
    
    modifier onlyPool() {
        require(msg.sender == pool, "MockAToken: only pool");
        _;
    }
    
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address underlying_,
        address pool_
    ) ERC20(name_, symbol_) {
        underlying = underlying_;
        pool = pool_;
        _decimals = decimals_;
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address, address onBehalfOf, uint256 amount, uint256) external onlyPool {
        _mint(onBehalfOf, amount);
    }
    
    function burn(address from, address, uint256 amount, uint256) external onlyPool {
        _burn(from, amount);
    }
}
