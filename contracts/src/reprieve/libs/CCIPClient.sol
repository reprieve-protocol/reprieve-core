// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CCIPClient
 * @notice Minimal CCIP Client library for message building
 * @dev Based on Chainlink CCIP Client library structure
 */
library CCIPClient {
    
    /// @notice EVM2Any message structure for CCIP send
    struct EVM2AnyMessage {
        bytes receiver;                 // Destination contract address (abi.encode)
        bytes data;                     // Payload data
        EVMTokenAmount[] tokenAmounts;  // Tokens to transfer
        address feeToken;               // Fee token (address(0) for native)
        bytes extraArgs;                // Extra arguments (gas limit, etc.)
    }
    
    /// @notice Token amount for CCIP transfers
    struct EVMTokenAmount {
        address token;      // Token address
        uint256 amount;     // Amount
    }
    
    /// @notice Any2EVM message structure for CCIP receive
    struct Any2EVMMessage {
        bytes32 messageId;          // Unique message ID
        uint64 sourceChainSelector; // Source chain selector
        bytes sender;               // Sender address (abi.encode)
        bytes data;                 // Payload data
        EVMTokenAmount[] destTokenAmounts; // Received tokens
    }
    
    /// @notice Chain selectors for supported chains
    /// Arbitrum Sepolia
    uint64 public constant ARBITRUM_SEPOLIA = 3478487238524512106;
    /// Base Sepolia  
    uint64 public constant BASE_SEPOLIA = 10344971235874465080;
    /// Ethereum Sepolia
    uint64 public constant ETHEREUM_SEPOLIA = 16015286601757825753;
    
    /// @notice Build extra args for CCIP message
    /// @param gasLimit Gas limit for destination execution
    /// @param allowOutOfOrderExecution Whether to allow out of order execution
    function buildExtraArgs(
        uint256 gasLimit,
        bool allowOutOfOrderExecution
    ) internal pure returns (bytes memory) {
        // Encoding: selector + gasLimit + allowOutOfOrderExecution
        // Client standard encoding: 0x97a657c9 + uint256 gasLimit + bool allowOutOfOrder
        return abi.encodeWithSelector(
            bytes4(0x97a657c9),
            gasLimit,
            allowOutOfOrderExecution
        );
    }
    
    /// @notice Encode address to bytes
    function addressToBytes(address a) internal pure returns (bytes memory) {
        return abi.encode(a);
    }
    
    /// @notice Decode address from bytes
    function bytesToAddress(bytes memory data) internal pure returns (address) {
        require(data.length == 20 || data.length == 32, "Invalid address length");
        if (data.length == 20) {
            address addr;
            assembly {
                addr := mload(add(data, 20))
            }
            return addr;
        } else {
            return abi.decode(data, (address));
        }
    }
}

/**
 * @title ICCIPRouter
 * @notice Interface for CCIP Router contract
 */
interface ICCIPRouter {
    /// @notice Get fee for a message
    function getFee(uint64 destinationChainSelector, CCIPClient.EVM2AnyMessage memory message) 
        external 
        view 
        returns (uint256 fee);
    
    /// @notice Send a message
    function ccipSend(uint64 destinationChainSelector, CCIPClient.EVM2AnyMessage memory message) 
        external 
        payable 
        returns (bytes32);
}
