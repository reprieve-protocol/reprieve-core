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
    address public admin;
    mapping(address => bool) public bridgeBurners;
    mapping(address => bool) public bridgeMinters;
    
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event MinterUpdated(address indexed newMinter);
    event AdminUpdated(address indexed newAdmin);
    event BridgeBurnerSet(address indexed account, bool allowed);
    event BridgeMinterSet(address indexed account, bool allowed);
    event BridgeBurn(address indexed burner, address indexed from, uint256 amount);
    event BridgeMint(address indexed minter, address indexed to, uint256 amount);
    
    modifier onlyMinter() {
        require(msg.sender == minter, "MockERC20: caller is not minter");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "MockERC20: caller is not admin");
        _;
    }

    modifier onlyBridgeBurner() {
        require(bridgeBurners[msg.sender], "MockERC20: caller is not bridge burner");
        _;
    }

    modifier onlyBridgeMinter() {
        require(bridgeMinters[msg.sender], "MockERC20: caller is not bridge minter");
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
        admin = minter_;
        emit MinterUpdated(minter_);
        emit AdminUpdated(minter_);
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
     * @notice Update admin address (admin only)
     * @param newAdmin New admin address
     */
    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "MockERC20: admin cannot be zero address");
        admin = newAdmin;
        emit AdminUpdated(newAdmin);
    }

    /**
     * @notice Set bridge burner role (admin only)
     * @param account Address to update
     * @param allowed True to allow
     */
    function setBridgeBurner(address account, bool allowed) external onlyAdmin {
        require(account != address(0), "MockERC20: bridge burner zero address");
        bridgeBurners[account] = allowed;
        emit BridgeBurnerSet(account, allowed);
    }

    /**
     * @notice Set bridge minter role (admin only)
     * @param account Address to update
     * @param allowed True to allow
     */
    function setBridgeMinter(address account, bool allowed) external onlyAdmin {
        require(account != address(0), "MockERC20: bridge minter zero address");
        bridgeMinters[account] = allowed;
        emit BridgeMinterSet(account, allowed);
    }

    /**
     * @notice Burn on source chain as bridge operation
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function bridgeBurn(address from, uint256 amount) external onlyBridgeBurner {
        require(from != address(0), "MockERC20: bridge burn from zero address");
        require(amount > 0, "MockERC20: bridge burn amount must be > 0");
        _burn(from, amount);
        emit BridgeBurn(msg.sender, from, amount);
    }

    /**
     * @notice Mint on destination chain as bridge operation
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function bridgeMint(address to, uint256 amount) external onlyBridgeMinter {
        require(to != address(0), "MockERC20: bridge mint to zero address");
        require(amount > 0, "MockERC20: bridge mint amount must be > 0");
        _mint(to, amount);
        emit BridgeMint(msg.sender, to, amount);
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
