// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for Reprieve demo lending protocols
 * @dev Supports mint/burn for test setup and standard ERC20 operations
 */
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;
    address public minter;
    
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event MinterUpdated(address indexed newMinter);
    
    modifier onlyMinter() {
        require(msg.sender == minter, "MockERC20: caller is not minter");
        _;
    }
    
    /**
     * @notice Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Token decimals
     * @param minter_ Address with mint/burn privileges
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address minter_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
        minter = minter_;
        emit MinterUpdated(minter_);
    }
    
    /**
     * @notice Returns the number of decimals used for token amounts
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint tokens to an address (minter only)
     * @param to The address to mint to
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "MockERC20: mint to zero address");
        require(amount > 0, "MockERC20: mint amount must be > 0");
        _mint(to, amount);
        emit Mint(to, amount);
    }
    
    /**
     * @notice Burn tokens from an address (minter only)
     * @param from The address to burn from
     * @param amount The amount to burn
     */
    function burn(address from, uint256 amount) external onlyMinter {
        require(from != address(0), "MockERC20: burn from zero address");
        require(amount > 0, "MockERC20: burn amount must be > 0");
        require(balanceOf(from) >= amount, "MockERC20: burn amount exceeds balance");
        _burn(from, amount);
        emit Burn(from, amount);
    }
    
    /**
     * @notice Batch mint tokens to multiple addresses (minter only)
     * @param recipients Array of addresses to mint to
     * @param amounts Array of amounts to mint
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyMinter {
        require(recipients.length == amounts.length, "MockERC20: length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "MockERC20: mint to zero address");
            require(amounts[i] > 0, "MockERC20: mint amount must be > 0");
            _mint(recipients[i], amounts[i]);
            emit Mint(recipients[i], amounts[i]);
        }
    }
    
    /**
     * @notice Update the minter address (current minter only)
     * @param newMinter The new minter address
     */
    function setMinter(address newMinter) external onlyMinter {
        require(newMinter != address(0), "MockERC20: minter cannot be zero address");
        minter = newMinter;
        emit MinterUpdated(newMinter);
    }
    
    /**
     * @notice Get total minted supply
     * @return Total supply of tokens
     */
    function totalMinted() external view returns (uint256) {
        return totalSupply();
    }
    
    /**
     * @notice Approve and call in a single transaction (ERC677-like)
     * @param spender The address authorized to spend
     * @param amount The max amount they can spend
     * @param data Extra data passed to the spender
     * @return success Whether the approval succeeded
     */
    function approveAndCall(
        address spender,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success) {
        require(spender != address(0), "MockERC20: approve to zero address");
        _approve(msg.sender, spender, amount);
        
        // Call the spender's receiveApproval function if it exists
        (bool callSuccess, ) = spender.call(
            abi.encodeWithSignature(
                "receiveApproval(address,uint256,address,bytes)",
                msg.sender,
                amount,
                address(this),
                data
            )
        );
        
        // Don't revert if receiveApproval fails (like ERC677 behavior)
        return callSuccess;
    }
}
