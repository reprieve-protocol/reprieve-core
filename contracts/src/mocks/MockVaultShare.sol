// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockVaultShare
 * @notice Minimal Morpho-style vault share for Reprieve demo
 * @dev ERC4626-like receipt token
 */
contract MockVaultShare is ERC20 {
    using SafeERC20 for IERC20;
    
    address public immutable asset;
    address public immutable market;
    uint8 private immutable _decimals;
    
    uint256 public totalAssets;
    
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    
    modifier onlyMarket() {
        require(msg.sender == market, "MockVaultShare: only market");
        _;
    }
    
    constructor(
        string memory name_,
        string memory symbol_,
        address asset_,
        address market_
    ) ERC20(name_, symbol_) {
        asset = asset_;
        market = market_;
        _decimals = ERC20(asset_).decimals();
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 || totalAssets == 0 ? assets : (assets * supply) / totalAssets;
    }
    
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : (shares * totalAssets) / supply;
    }
    
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
        totalAssets += assets;
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }
    
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = convertToShares(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        totalAssets -= assets;
        IERC20(asset).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }
}
