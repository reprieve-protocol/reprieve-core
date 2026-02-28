// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockCToken
 * @notice Compound-style cToken for Reprieve demo
 * @dev Minimal receipt token for position tracking + approval flow
 */
contract MockCToken is ERC20 {
    using SafeERC20 for IERC20;
    
    address public immutable underlying;
    address public immutable market;
    uint8 private immutable _decimals;
    
    modifier onlyMarket() {
        require(msg.sender == market, "MockCToken: only market");
        _;
    }
    
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address underlying_,
        address market_
    ) ERC20(name_, symbol_) {
        underlying = underlying_;
        market = market_;
        _decimals = decimals_;
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint cTokens (market only)
     * @param amount Amount to mint
     */
    function mint(uint256 amount) external onlyMarket {
        _mint(address(this), amount);
    }
    
    /**
     * @notice Redeem cTokens for underlying (market only)
     * @param amount Amount to redeem
     */
    function redeem(uint256 amount) external onlyMarket {
        _burn(address(this), amount);
    }
    
    /**
     * @notice Transfer underlying from market to recipient
     * @param to Recipient
     * @param amount Amount
     */
    function transferUnderlying(address to, uint256 amount) external onlyMarket {
        IERC20(underlying).safeTransfer(to, amount);
    }
}
