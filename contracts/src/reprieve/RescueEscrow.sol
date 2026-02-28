// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IRescueEscrow} from "./interfaces/IRescueEscrow.sol";
import {IRescueLog} from "./interfaces/IRescueLog.sol";
import {ReprieveTypes} from "./libs/ReprieveTypes.sol";
import {ReprieveErrors} from "./libs/ReprieveErrors.sol";
import {ReprieveEvents} from "./libs/ReprieveEvents.sol";

/**
 * @title RescueEscrow
 * @notice Holds funds on source chain when CCIP transfer or rescue fails
 * @dev Supports user claim or protocol retry path
 */
contract RescueEscrow is IRescueEscrow, Ownable {
    using SafeERC20 for IERC20;
    
    /// @notice Maximum retry attempts before escrow becomes claim-only
    uint256 public constant MAX_RETRY_COUNT = 3;
    
    /// @notice Escrow timeout (30 days)
    uint256 public constant ESCROW_TIMEOUT = 30 days;
    
    /// @notice RescueLog contract for events
    IRescueLog public rescueLog;
    
    /// @notice Escrow ID => EscrowRecord
    mapping(bytes32 => ReprieveTypes.EscrowRecord) public escrows;
    
    /// @notice User => Escrow IDs
    mapping(address => bytes32[]) public userEscrows;
    
    /// @notice Authorized depositors (executor, receiver)
    mapping(address => bool) public authorizedDepositors;
    
    modifier onlyAuthorizedDepositor() {
        if (!authorizedDepositors[msg.sender]) revert ReprieveErrors.UnauthorizedWorkflow(msg.sender);
        _;
    }
    
    modifier onlyPendingEscrow(bytes32 escrowId) {
        if (escrows[escrowId].status != ReprieveTypes.EscrowStatus.Pending) {
            revert ReprieveErrors.EscrowNotClaimable(escrowId);
        }
        _;
    }
    
    constructor(address initialOwner, address _rescueLog) Ownable(initialOwner) {
        if (_rescueLog == address(0)) revert ReprieveErrors.ZeroAddress();
        rescueLog = IRescueLog(_rescueLog);
    }
    
    /**
     * @notice Authorize a contract to deposit into escrow
     * @param depositor Address to authorize
     * @param allowed True to authorize, false to revoke
     */
    function setAuthorizedDepositor(address depositor, bool allowed) external onlyOwner {
        if (depositor == address(0)) revert ReprieveErrors.ZeroAddress();
        authorizedDepositors[depositor] = allowed;
    }
    
    /**
     * @notice Deposit failed transfer into escrow
     * @param escrowId Unique escrow ID
     * @param owner Original user who owns the funds
     * @param asset Token address
     * @param amount Amount to escrow
     * @param sourceChain Source chain ID
     * @param targetChain Target chain ID
     * @param execId Related rescue execution ID
     */
    function depositFailedTransfer(
        bytes32 escrowId,
        address owner,
        address asset,
        uint256 amount,
        uint256 sourceChain,
        uint256 targetChain,
        bytes32 execId
    ) external override onlyAuthorizedDepositor returns (bool) {
        if (escrows[escrowId].status != ReprieveTypes.EscrowStatus.None) {
            revert ReprieveErrors.EscrowAlreadyClaimed(escrowId);
        }
        if (owner == address(0) || asset == address(0)) revert ReprieveErrors.ZeroAddress();
        if (amount == 0) revert ReprieveErrors.ZeroAmount();
        
        // Transfer tokens to escrow
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        
        // Create escrow record
        escrows[escrowId] = ReprieveTypes.EscrowRecord({
            escrowId: escrowId,
            owner: owner,
            asset: asset,
            amount: amount,
            sourceChain: sourceChain,
            targetChain: targetChain,
            status: ReprieveTypes.EscrowStatus.Pending,
            createdAt: block.timestamp,
            retryCount: 0,
            relatedExecId: execId
        });
        
        userEscrows[owner].push(escrowId);
        
        // Log the deposit
        _logEscrowEvent(execId, escrowId, owner, "Escrow deposited");
        
        emit ReprieveEvents.EscrowCreated(escrowId, owner, asset, amount, execId);
        
        return true;
    }
    
    /**
     * @notice Claim escrowed funds
     * @param escrowId Unique escrow ID
     */
    function claimEscrow(bytes32 escrowId) 
        external 
        override 
        onlyPendingEscrow(escrowId) 
        returns (bool) 
    {
        ReprieveTypes.EscrowRecord storage record = escrows[escrowId];
        
        if (!_canClaim(escrowId, msg.sender)) {
            revert ReprieveErrors.EscrowNotClaimable(escrowId);
        }
        
        // Check timeout
        if (block.timestamp > record.createdAt + ESCROW_TIMEOUT) {
            record.status = ReprieveTypes.EscrowStatus.Expired;
            revert ReprieveErrors.EscrowExpired(escrowId);
        }
        
        // Update status
        record.status = ReprieveTypes.EscrowStatus.Claimed;
        
        // Transfer funds
        IERC20(record.asset).safeTransfer(record.owner, record.amount);
        
        // Log the claim
        _logEscrowEvent(record.relatedExecId, escrowId, record.owner, "Escrow claimed");
        
        emit ReprieveEvents.EscrowClaimed(escrowId, record.owner, record.amount);
        
        return true;
    }
    
    /**
     * @notice Retry a failed transfer from escrow
     * @param escrowId Unique escrow ID
     * @param retryData Encoded retry parameters
     */
    function retryTransfer(bytes32 escrowId, bytes calldata retryData) 
        external 
        override 
        onlyAuthorizedDepositor
        onlyPendingEscrow(escrowId) 
        returns (bool) 
    {
        ReprieveTypes.EscrowRecord storage record = escrows[escrowId];
        
        // Check max retry count
        if (record.retryCount >= MAX_RETRY_COUNT) {
            revert ReprieveErrors.EscrowNotRetriable(escrowId);
        }
        
        // Increment retry count
        record.retryCount++;
        
        // Mark as retried (new attempt will create new escrow if needed)
        record.status = ReprieveTypes.EscrowStatus.Retried;
        
        // Transfer funds back to authorized depositor for retry
        IERC20(record.asset).safeTransfer(msg.sender, record.amount);
        
        // Log the retry
        _logEscrowEvent(record.relatedExecId, escrowId, record.owner, "Escrow retried");
        
        emit ReprieveEvents.EscrowRetried(escrowId, record.retryCount, record.relatedExecId);
        
        // Execute retry (delegated to caller)
        // retryData contains encoded call for the depositor to execute
        
        return true;
    }
    
    /**
     * @notice Get escrow record
     * @param escrowId Unique escrow ID
     * @return EscrowRecord struct
     */
    function getEscrow(bytes32 escrowId) 
        external 
        view 
        override 
        returns (ReprieveTypes.EscrowRecord memory) 
    {
        return escrows[escrowId];
    }
    
    /**
     * @notice Check if claimer can claim escrow
     * @param escrowId Unique escrow ID
     * @param claimer Address attempting to claim
     * @return True if claimable
     */
    function canClaim(bytes32 escrowId, address claimer) 
        external 
        view 
        override 
        returns (bool) 
    {
        return _canClaim(escrowId, claimer);
    }
    
    /**
     * @notice Get all escrow IDs for a user
     * @param user User address
     * @return Array of escrow IDs
     */
    function getUserEscrows(address user) external view returns (bytes32[] memory) {
        return userEscrows[user];
    }
    
    /**
     * @notice Get count of escrows for a user
     * @param user User address
     * @return Count
     */
    function getUserEscrowCount(address user) external view returns (uint256) {
        return userEscrows[user].length;
    }
    
    /**
     * @notice Check if escrow is expired
     * @param escrowId Unique escrow ID
     * @return True if expired
     */
    function isExpired(bytes32 escrowId) external view returns (bool) {
        ReprieveTypes.EscrowRecord memory record = escrows[escrowId];
        if (record.status != ReprieveTypes.EscrowStatus.Pending) return false;
        return block.timestamp > record.createdAt + ESCROW_TIMEOUT;
    }
    
    /**
     * @notice Emergency withdrawal by owner (for stuck tokens)
     * @param asset Token address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address asset, uint256 amount) external onlyOwner {
        IERC20(asset).safeTransfer(owner(), amount);
    }
    
    // ============ Internal Functions ============
    
    function _canClaim(bytes32 escrowId, address claimer) internal view returns (bool) {
        ReprieveTypes.EscrowRecord memory record = escrows[escrowId];
        
        // Only owner can claim
        if (record.owner != claimer) return false;
        
        // Must be pending
        if (record.status != ReprieveTypes.EscrowStatus.Pending) return false;
        
        // Must not be expired
        if (block.timestamp > record.createdAt + ESCROW_TIMEOUT) return false;
        
        return true;
    }
    
    function _logEscrowEvent(bytes32 execId, bytes32 escrowId, address owner, string memory details) internal {
        // Log via rescueLog if execId is valid
        if (execId != bytes32(0) && address(rescueLog) != address(0)) {
            try rescueLog.logRescueStep(execId, 0, owner, details) {} catch {}
        }
    }
}
