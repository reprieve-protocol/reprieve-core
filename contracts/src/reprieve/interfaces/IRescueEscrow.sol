// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReprieveTypes} from "../libs/ReprieveTypes.sol";

/**
 * @title IRescueEscrow
 * @notice Holds funds when CCIP transfer or rescue fails
 */
interface IRescueEscrow {
    event EscrowCreated(bytes32 indexed escrowId, address indexed owner, address asset, uint256 amount);
    event EscrowClaimed(bytes32 indexed escrowId, address indexed claimer);
    event EscrowRetried(bytes32 indexed escrowId, uint256 retryCount);
    
    function depositFailedTransfer(
        bytes32 escrowId,
        address owner,
        address asset,
        uint256 amount,
        uint256 sourceChain,
        uint256 targetChain,
        bytes32 execId
    ) external returns (bool);
    
    function claimEscrow(bytes32 escrowId) external returns (bool);
    function retryTransfer(bytes32 escrowId, bytes calldata retryData) external returns (bool);
    
    function getEscrow(bytes32 escrowId) external view returns (ReprieveTypes.EscrowRecord memory);
    function canClaim(bytes32 escrowId, address claimer) external view returns (bool);
}
