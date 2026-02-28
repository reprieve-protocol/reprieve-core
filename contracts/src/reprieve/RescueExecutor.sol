// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {IRescueExecutor} from "./interfaces/IRescueExecutor.sol";
import {IRescueLog} from "./interfaces/IRescueLog.sol";
import {IRescueEscrow} from "./interfaces/IRescueEscrow.sol";
import {IAdapterRegistry} from "./interfaces/IAdapterRegistry.sol";
import {IReprieveAdapter} from "../interfaces/IReprieveAdapter.sol";
import {ReprieveTypes} from "./libs/ReprieveTypes.sol";
import {ReprieveErrors} from "./libs/ReprieveErrors.sol";
import {ReprieveEvents} from "./libs/ReprieveEvents.sol";
import {CCIPClient, ICCIPRouter} from "./libs/CCIPClient.sol";

/**
 * @title RescueExecutor
 * @notice Main execution contract for rescue actions
 * @dev Executes same-chain-first withdraw/repay via adapters
 * @dev Initiates CCIP cross-chain rescue when same-chain source is insufficient
 */
contract RescueExecutor is IRescueExecutor, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /// @notice Reserve factor: max 80% of source collateral can be withdrawn (20% reserve)
    uint256 public constant SOURCE_RESERVE_FACTOR_BPS = 2000; // 20%
    
    /// @notice RescueLog contract
    IRescueLog public rescueLog;
    
    /// @notice RescueEscrow contract
    IRescueEscrow public rescueEscrow;
    
    /// @notice AdapterRegistry contract
    IAdapterRegistry public adapterRegistry;
    
    /// @notice CCIP Router address
    address public ccipRouter;
    
    /// @notice User => rescue in progress
    mapping(address => bool) public rescueInProgress;
    
    /// @notice execId => status
    mapping(bytes32 => ReprieveTypes.RescueStatus) public rescueStatus;
    
    /// @notice Authorized workflow callers (temporary until CRE integration)
    mapping(address => bool) public authorizedWorkflows;
    
    /// @notice Destination chain => allowed
    mapping(uint64 => bool) public trustedDestinationChains;
    
    /// @notice Destination chain => receiver contract address
    mapping(uint64 => address) public chainReceivers;
    
    /// @notice Destination chain => extra args (gas limit + out-of-order flag)
    mapping(uint64 => bytes) public ccipExtraArgs;
    
    /// @notice Default gas limit for CCIP destination execution
    uint256 public defaultGasLimit = 300000;
    
    /// @notice Whether to allow out of order execution by default
    bool public defaultAllowOutOfOrderExecution = true;
    
    /// @notice execId => CCIP message ID (for tracking cross-chain sends)
    mapping(bytes32 => bytes32) public ccipMessageIds;
    
    modifier onlyAuthorizedWorkflow() {
        if (!authorizedWorkflows[msg.sender] && msg.sender != owner()) {
            revert ReprieveErrors.UnauthorizedWorkflow(msg.sender);
        }
        _;
    }
    
    modifier whenNotLocked(address user) {
        if (rescueInProgress[user]) revert ReprieveErrors.RescueAlreadyInProgress(user);
        _;
    }
    
    constructor(
        address initialOwner,
        address _rescueLog,
        address _rescueEscrow,
        address _adapterRegistry
    ) Ownable(initialOwner) {
        if (_rescueLog == address(0) || _rescueEscrow == address(0) || _adapterRegistry == address(0)) {
            revert ReprieveErrors.ZeroAddress();
        }
        rescueLog = IRescueLog(_rescueLog);
        rescueEscrow = IRescueEscrow(_rescueEscrow);
        adapterRegistry = IAdapterRegistry(_adapterRegistry);
    }
    
    /**
     * @notice Set CCIP Router address
     * @param _router Router address
     */
    function setCcipRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ReprieveErrors.ZeroAddress();
        ccipRouter = _router;
        emit ReprieveEvents.CcipRouterSet(_router);
    }
    
    /**
     * @notice Authorize a workflow caller (temporary until CRE)
     * @param workflow Address to authorize
     * @param allowed True to authorize, false to revoke
     */
    function setAuthorizedWorkflow(address workflow, bool allowed) external override onlyOwner {
        if (workflow == address(0)) revert ReprieveErrors.ZeroAddress();
        authorizedWorkflows[workflow] = allowed;
        emit ReprieveEvents.WorkflowAuthorized(workflow, allowed);
    }
    
    /**
     * @notice Set trusted destination chain
     * @param destinationChainSelector Chain selector
     * @param trusted True to trust
     */
    function setTrustedDestinationChain(uint64 destinationChainSelector, bool trusted) external onlyOwner {
        trustedDestinationChains[destinationChainSelector] = trusted;
        emit ReprieveEvents.CcipDestinationAllowed(destinationChainSelector, trusted);
    }
    
    /**
     * @notice Set receiver contract for a destination chain
     * @param destinationChainSelector Chain selector
     * @param receiver Receiver contract address on destination chain
     */
    function setChainReceiver(uint64 destinationChainSelector, address receiver) external onlyOwner {
        chainReceivers[destinationChainSelector] = receiver;
        emit ReprieveEvents.CcipDestinationAllowed(destinationChainSelector, true);
    }
    
    /**
     * @notice Set CCIP extra args for a destination chain
     * @param destinationChainSelector Chain selector
     * @param extraArgs Encoded extra arguments
     */
    function setCcipExtraArgs(uint64 destinationChainSelector, bytes calldata extraArgs) external override onlyOwner {
        ccipExtraArgs[destinationChainSelector] = extraArgs;
        emit ReprieveEvents.CcipExtraArgsSet(destinationChainSelector, extraArgs);
    }
    
    /**
     * @notice Set default CCIP parameters
     * @param gasLimit Default gas limit
     * @param allowOutOfOrder Whether to allow out of order execution
     */
    function setDefaultCcipParams(uint256 gasLimit, bool allowOutOfOrder) external onlyOwner {
        defaultGasLimit = gasLimit;
        defaultAllowOutOfOrderExecution = allowOutOfOrder;
    }
    
    /**
     * @notice Execute a rescue plan
     * @param plan Complete rescue plan with ordered steps
     * @return success True if rescue completed successfully
     */
    function executeRescue(ReprieveTypes.RescuePlan calldata plan) 
        external 
        override 
        onlyAuthorizedWorkflow
        whenNotLocked(plan.user)
        nonReentrant
        returns (bool success) 
    {
        // Check deadline
        if (block.timestamp > plan.deadline) {
            revert ReprieveErrors.DeadlinePassed(plan.deadline, block.timestamp);
        }
        
        // Set lock
        rescueInProgress[plan.user] = true;
        rescueStatus[plan.execId] = ReprieveTypes.RescueStatus.InProgress;
        
        // Log initiation
        rescueLog.logRescueInitiated(plan.execId, plan.user, plan.steps.length);
        
        bool anyStepSucceeded = false;
        uint256 lastCompletedStep = 0;
        
        // Execute each step
        for (uint256 i = 0; i < plan.steps.length; i++) {
            ReprieveTypes.RescueStep memory step = plan.steps[i];
            
            // Log step start
            rescueLog.logRescueStep(
                plan.execId, 
                i, 
                plan.user, 
                string.concat("Step ", _uintToString(i), " started")
            );
            
            bool stepSuccess;
            
            if (step.isCrossChain) {
                // Cross-chain step
                stepSuccess = _initiateCrossChainStep(step, plan.user, plan.execId);
            } else {
                // Same-chain step
                stepSuccess = _executeSameChainStep(step, plan.user, plan.execId);
            }
            
            if (stepSuccess) {
                anyStepSucceeded = true;
                lastCompletedStep = i;
                
                // Log step completion
                rescueLog.logRescueStep(
                    plan.execId,
                    i,
                    plan.user,
                    string.concat("Step ", _uintToString(i), " completed")
                );
                
                emit ReprieveEvents.RescueStepCompleted(
                    plan.execId,
                    i,
                    step.sourceAdapter,
                    step.targetAdapter,
                    step.collateralAmount,
                    step.debtAmount
                );
            } else {
                // Log step failure
                rescueLog.logRescueStep(
                    plan.execId,
                    i,
                    plan.user,
                    string.concat("Step ", _uintToString(i), " failed")
                );
                
                // Continue to next source if available (fallback behavior)
                continue;
            }
        }
        
        // Determine final status
        if (anyStepSucceeded) {
            rescueStatus[plan.execId] = ReprieveTypes.RescueStatus.Completed;
            
            rescueLog.logRescueCompleted(
                plan.execId,
                plan.user,
                ReprieveTypes.RescueStatus.Completed,
                "Rescue completed"
            );
            
            emit ReprieveEvents.RescueCompleted(
                plan.execId,
                plan.user,
                ReprieveTypes.RescueStatus.Completed,
                lastCompletedStep
            );
            
            success = true;
        } else {
            rescueStatus[plan.execId] = ReprieveTypes.RescueStatus.Failed;
            
            rescueLog.logRescueFailed(
                plan.execId,
                plan.user,
                "All rescue steps failed"
            );
            
            emit ReprieveEvents.RescueFailed(
                plan.execId,
                plan.user,
                "All steps failed",
                0
            );
            
            success = false;
        }
        
        // Clear lock
        rescueInProgress[plan.user] = false;
        
        return success;
    }
    
    /**
     * @notice Execute a single rescue step (same-chain)
     * @param step Rescue step definition
     * @param user User being rescued
     * @param execId Execution ID
     * @return success True if step succeeded
     */
    function executeSameChainLeg(
        ReprieveTypes.RescueStep calldata step,
        address user,
        bytes32 execId
    ) external override onlyAuthorizedWorkflow returns (bool success) {
        return _executeSameChainStep(step, user, execId);
    }
    
    /**
     * @notice Initiate cross-chain rescue leg
     * @param destinationChainSelector Destination chain selector
     * @param receiver Receiver contract on destination
     * @param user User being rescued
     * @param execId Execution ID
     * @param collateralAsset Collateral token to transfer
     * @param collateralAmount Amount to transfer
     * @param targetAdapter Target adapter on destination
     * @param debtAsset Debt asset to repay
     * @param debtAmount Amount to repay
     * @param stepIndex Step index
     * @param feeToken Fee token (address(0) for native)
     * @return messageId CCIP message ID
     */
    function initiateCrossChainLeg(
        uint64 destinationChainSelector,
        address receiver,
        address user,
        bytes32 execId,
        address collateralAsset,
        uint256 collateralAmount,
        address targetAdapter,
        address debtAsset,
        uint256 debtAmount,
        uint256 stepIndex,
        address feeToken
    ) external onlyAuthorizedWorkflow returns (bytes32 messageId) {
        messageId = _sendCCIPMessage(
            destinationChainSelector,
            receiver,
            user,
            execId,
            collateralAsset,
            collateralAmount,
            targetAdapter,
            debtAsset,
            debtAmount,
            stepIndex,
            feeToken
        );
    }
    
    /**
     * @notice Internal function to send CCIP message (used by both external and internal calls)
     */
    function _sendCCIPMessage(
        uint64 destinationChainSelector,
        address receiver,
        address user,
        bytes32 execId,
        address collateralAsset,
        uint256 collateralAmount,
        address targetAdapter,
        address debtAsset,
        uint256 debtAmount,
        uint256 stepIndex,
        address feeToken
    ) internal returns (bytes32 messageId) {
        // Validate destination chain
        if (!trustedDestinationChains[destinationChainSelector]) {
            revert ReprieveErrors.CCIPDestinationNotAllowed(destinationChainSelector);
        }
        
        // Check router is set
        if (ccipRouter == address(0)) {
            revert ReprieveErrors.CCIPRouterNotSet();
        }
        
        // Build rescue payload
        ReprieveTypes.CCIPMessage memory rescueMessage = ReprieveTypes.CCIPMessage({
            execId: execId,
            user: user,
            targetAdapter: targetAdapter,
            asset: debtAsset,
            amount: debtAmount,
            timestamp: block.timestamp,
            deadline: block.timestamp + 1 hours
        });
        
        // Build token amounts
        CCIPClient.EVMTokenAmount[] memory tokenAmounts = new CCIPClient.EVMTokenAmount[](1);
        tokenAmounts[0] = CCIPClient.EVMTokenAmount({
            token: collateralAsset,
            amount: collateralAmount
        });
        
        // Get extra args
        bytes memory extraArgs = ccipExtraArgs[destinationChainSelector];
        if (extraArgs.length == 0) {
            extraArgs = CCIPClient.buildExtraArgs(defaultGasLimit, defaultAllowOutOfOrderExecution);
        }
        
        // Build CCIP message
        CCIPClient.EVM2AnyMessage memory message = CCIPClient.EVM2AnyMessage({
            receiver: CCIPClient.addressToBytes(receiver),
            data: abi.encode(rescueMessage),
            tokenAmounts: tokenAmounts,
            feeToken: feeToken,
            extraArgs: extraArgs
        });
        
        // Get fee
        uint256 fee = ICCIPRouter(ccipRouter).getFee(destinationChainSelector, message);
        
        // Check fee affordability
        if (feeToken == address(0)) {
            // Native fee
            if (address(this).balance < fee) {
                revert ReprieveErrors.InsufficientFeePayment(fee, address(this).balance);
            }
        } else {
            // ERC20 fee token
            if (IERC20(feeToken).balanceOf(address(this)) < fee) {
                revert ReprieveErrors.InsufficientFeePayment(fee, IERC20(feeToken).balanceOf(address(this)));
            }
            // Approve fee token
            IERC20(feeToken).approve(ccipRouter, fee);
        }
        
        // Approve collateral token for router
        IERC20(collateralAsset).approve(ccipRouter, collateralAmount);
        
        // Send via CCIP
        if (feeToken == address(0)) {
            // Pay with native
            messageId = ICCIPRouter(ccipRouter).ccipSend{value: fee}(destinationChainSelector, message);
        } else {
            // Pay with ERC20
            messageId = ICCIPRouter(ccipRouter).ccipSend(destinationChainSelector, message);
        }
        
        // Store message ID
        ccipMessageIds[execId] = messageId;
        
        // Log cross-chain initiation
        rescueLog.logRescueStep(
            execId,
            stepIndex,
            user,
            string.concat("Cross-chain initiated: ", _bytes32ToString(messageId))
        );
        
        emit ReprieveEvents.CrossChainInitiated(
            execId,
            destinationChainSelector,
            messageId,
            fee
        );
        
        return messageId;
    }
    
    /**
     * @notice Complete cross-chain rescue leg (called by CCIPReceiver)
     * @param execId Execution ID
     * @param user User being rescued
     * @param targetAdapter Target adapter address
     * @param asset Asset to repay
     * @param amount Amount to repay
     * @return success True if completion succeeded
     */
    function completeCrossChainLeg(
        bytes32 execId,
        address user,
        address targetAdapter,
        address asset,
        uint256 amount
    ) external override returns (bool success) {
        // Only CCIPReceiver can call this
        // This will be enforced by checking msg.sender against stored receiver
        
        try this._processCrossChainRepay(execId, user, targetAdapter, asset, amount) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Process cross-chain repay (internal)
     */
    function _processCrossChainRepay(
        bytes32 execId,
        address user,
        address targetAdapter,
        address asset,
        uint256 amount
    ) external returns (bool) {
        require(msg.sender == address(this), "Only self");
        
        // Approve target adapter to spend tokens
        IERC20(asset).approve(targetAdapter, amount);
        
        try IReprieveAdapter(targetAdapter).repayForRescue(user, asset, amount) {
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Quote CCIP fee for a cross-chain message
     * @param targetChain Destination chain selector
     * @param message Message to send
     * @return fee Estimated fee
     */
    function quoteCcipFee(uint64 targetChain, bytes memory message) 
        external 
        view 
        override 
        returns (uint256 fee) 
    {
        if (ccipRouter == address(0)) return 0;
        
        // Build a sample message for quoting
        CCIPClient.EVM2AnyMessage memory sampleMessage = CCIPClient.EVM2AnyMessage({
            receiver: message, // Placeholder
            data: message,
            tokenAmounts: new CCIPClient.EVMTokenAmount[](0),
            feeToken: address(0),
            extraArgs: ccipExtraArgs[targetChain].length > 0 
                ? ccipExtraArgs[targetChain] 
                : CCIPClient.buildExtraArgs(defaultGasLimit, defaultAllowOutOfOrderExecution)
        });
        
        return ICCIPRouter(ccipRouter).getFee(targetChain, sampleMessage);
    }
    
    /**
     * @notice Get rescue status for an execution
     * @param execId Execution ID
     * @return Current status
     */
    function getRescueStatus(bytes32 execId) external view override returns (ReprieveTypes.RescueStatus) {
        return rescueStatus[execId];
    }
    
    /**
     * @notice Get CCIP message ID for an execution
     * @param execId Execution ID
     * @return messageId CCIP message ID
     */
    function getCcipMessageId(bytes32 execId) external view returns (bytes32) {
        return ccipMessageIds[execId];
    }
    
    // ============ Internal Execution Functions ============
    
    function _executeSameChainStep(
        ReprieveTypes.RescueStep memory step,
        address user,
        bytes32 execId
    ) internal returns (bool) {
        // Get source adapter
        IReprieveAdapter sourceAdapter = IReprieveAdapter(step.sourceAdapter);
        
        // Check available collateral at source (with reserve factor)
        uint256 availableCollateral = sourceAdapter.availableCollateral(user, step.collateralAsset);
        uint256 maxWithdrawable = availableCollateral * (10000 - SOURCE_RESERVE_FACTOR_BPS) / 10000;
        
        if (maxWithdrawable < step.collateralAmount) {
            // Insufficient collateral, try with what's available
            if (maxWithdrawable == 0) return false;
            step.collateralAmount = maxWithdrawable;
        }
        
        // Withdraw from source - use try/catch for granular error handling
        bool withdrawSuccess;
        try sourceAdapter.withdrawForRescue(user, step.collateralAsset, step.collateralAmount, address(this)) {
            withdrawSuccess = true;
        } catch {
            return false; // Pre-withdraw failure - no funds moved
        }
        
        if (!withdrawSuccess) {
            return false;
        }
        
        // Withdraw succeeded - attempt repay
        bool repaySuccess = this._executeRepay(step, user, execId);
        
        if (!repaySuccess) {
            // Post-withdraw failure - escrow the withdrawn funds
            _escrowWithdrawnFunds(step, user, execId);
        }
        
        return repaySuccess;
    }
    
    /**
     * @notice Execute repay portion of same-chain step (external for try/catch)
     */
    function _executeRepay(
        ReprieveTypes.RescueStep memory step,
        address user,
        bytes32 execId
    ) external returns (bool) {
        require(msg.sender == address(this), "Only self");
        
        // Get target adapter
        IReprieveAdapter targetAdapter = IReprieveAdapter(step.targetAdapter);
        
        // Approve debt token for repayment
        IERC20(step.debtAsset).approve(step.targetAdapter, step.debtAmount);
        
        // Repay at target
        try targetAdapter.repayForRescue(user, step.debtAsset, step.debtAmount) {
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Escrow withdrawn funds when repay fails
     */
    function _escrowWithdrawnFunds(
        ReprieveTypes.RescueStep memory step,
        address user,
        bytes32 execId
    ) internal {
        // Generate unique escrow ID
        bytes32 escrowId = keccak256(abi.encodePacked(execId, step.stepIndex, block.timestamp));
        
        // Approve escrow to pull tokens
        IERC20(step.collateralAsset).approve(address(rescueEscrow), step.collateralAmount);
        
        // Deposit to escrow
        try rescueEscrow.depositFailedTransfer(
            escrowId,
            user,
            step.collateralAsset,
            step.collateralAmount,
            block.chainid,
            block.chainid, // Same chain failure
            execId
        ) {
            // Log escrow event
            try rescueLog.logRescueStep(
                execId,
                step.stepIndex,
                user,
                string.concat("Funds escrowed: ", _bytes32ToString(escrowId))
            ) {} catch {}
            
            emit ReprieveEvents.EscrowCreated(
                escrowId,
                user,
                step.collateralAsset,
                step.collateralAmount,
                execId
            );
        } catch {
            // If escrow fails, tokens remain in executor
            // Owner can recover via emergencyWithdraw
        }
    }
    
    function _initiateCrossChainStep(
        ReprieveTypes.RescueStep memory step,
        address user,
        bytes32 execId
    ) internal returns (bool) {
        // Get receiver for target chain
        address receiver = chainReceivers[step.targetChain];
        if (receiver == address(0)) {
            return false;
        }
        
        // Build and send CCIP message directly (internal call to avoid auth issues)
        // Note: We don't use try/catch here because it only works with external calls
        _sendCCIPMessage(
            step.targetChain,
            receiver,
            user,
            execId,
            step.collateralAsset,
            step.collateralAmount,
            step.targetAdapter,
            step.debtAsset,
            step.debtAmount,
            step.stepIndex,
            address(0) // Use native token for fees
        );
        return true;
    }
    
    // ============ Utility Functions ============
    
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    function _bytes32ToString(bytes32 value) internal pure returns (string memory) {
        bytes memory buffer = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            uint256 char = uint256(uint8(value[i]));
            uint256 hi = char / 16;
            uint256 lo = char % 16;
            buffer[i * 2] = bytes1(uint8(hi + (hi < 10 ? 48 : 87)));
            buffer[i * 2 + 1] = bytes1(uint8(lo + (lo < 10 ? 48 : 87)));
        }
        return string(buffer);
    }
    
    /**
     * @notice Emergency withdrawal by owner
     */
    function emergencyWithdraw(address asset, uint256 amount) external onlyOwner {
        IERC20(asset).safeTransfer(owner(), amount);
    }
    
    /**
     * @notice Receive native tokens for CCIP fees
     */
    receive() external payable {}
}
