// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";
import {IWorkflowReceiver} from "./IWorkflowReceiver.sol";

/**
 * @title WorkflowReceiverTemplate
 * @notice Abstract CRE receiver with forwarder + workflow identity validation.
 */
abstract contract WorkflowReceiverTemplate is IWorkflowReceiver, Ownable {
    address private s_forwarderAddress;
    address private s_expectedAuthor;
    bytes10 private s_expectedWorkflowName;
    bytes32 private s_expectedWorkflowId;

    bytes private constant HEX_CHARS = "0123456789abcdef";

    error InvalidForwarderAddress();
    error InvalidSender(address sender, address expected);
    error InvalidAuthor(address received, address expected);
    error InvalidWorkflowName(bytes10 received, bytes10 expected);
    error InvalidWorkflowId(bytes32 received, bytes32 expected);
    error WorkflowNameRequiresAuthorValidation();
    error InvalidMetadataLength(uint256 provided);

    event ForwarderAddressUpdated(address indexed previousForwarder, address indexed newForwarder);
    event ExpectedAuthorUpdated(address indexed previousAuthor, address indexed newAuthor);
    event ExpectedWorkflowNameUpdated(bytes10 indexed previousName, bytes10 indexed newName);
    event ExpectedWorkflowIdUpdated(bytes32 indexed previousId, bytes32 indexed newId);
    event SecurityWarning(string message);

    constructor(address initialOwner, address forwarderAddress) Ownable(initialOwner) {
        if (forwarderAddress == address(0)) revert InvalidForwarderAddress();
        s_forwarderAddress = forwarderAddress;
        emit ForwarderAddressUpdated(address(0), forwarderAddress);
    }

    function getForwarderAddress() external view returns (address) {
        return s_forwarderAddress;
    }

    function getExpectedAuthor() external view returns (address) {
        return s_expectedAuthor;
    }

    function getExpectedWorkflowName() external view returns (bytes10) {
        return s_expectedWorkflowName;
    }

    function getExpectedWorkflowId() external view returns (bytes32) {
        return s_expectedWorkflowId;
    }

    function onReport(bytes calldata metadata, bytes calldata report) external override {
        if (s_forwarderAddress != address(0) && msg.sender != s_forwarderAddress) {
            revert InvalidSender(msg.sender, s_forwarderAddress);
        }

        if (
            s_expectedWorkflowId != bytes32(0) ||
            s_expectedAuthor != address(0) ||
            s_expectedWorkflowName != bytes10(0)
        ) {
            (bytes32 workflowId, bytes10 workflowName, address workflowOwner) = _decodeMetadata(metadata);

            if (s_expectedWorkflowId != bytes32(0) && workflowId != s_expectedWorkflowId) {
                revert InvalidWorkflowId(workflowId, s_expectedWorkflowId);
            }
            if (s_expectedAuthor != address(0) && workflowOwner != s_expectedAuthor) {
                revert InvalidAuthor(workflowOwner, s_expectedAuthor);
            }
            if (s_expectedWorkflowName != bytes10(0)) {
                if (s_expectedAuthor == address(0)) revert WorkflowNameRequiresAuthorValidation();
                if (workflowName != s_expectedWorkflowName) {
                    revert InvalidWorkflowName(workflowName, s_expectedWorkflowName);
                }
            }
        }

        _processReport(report);
    }

    function setForwarderAddress(address forwarder) external onlyOwner {
        address previous = s_forwarderAddress;
        if (forwarder == address(0)) {
            emit SecurityWarning("Forwarder address set to zero - contract is now INSECURE");
        }
        s_forwarderAddress = forwarder;
        emit ForwarderAddressUpdated(previous, forwarder);
    }

    function setExpectedAuthor(address author) external onlyOwner {
        address previous = s_expectedAuthor;
        s_expectedAuthor = author;
        emit ExpectedAuthorUpdated(previous, author);
    }

    function setExpectedWorkflowName(string calldata name) external onlyOwner {
        bytes10 previous = s_expectedWorkflowName;
        if (bytes(name).length == 0) {
            s_expectedWorkflowName = bytes10(0);
            emit ExpectedWorkflowNameUpdated(previous, bytes10(0));
            return;
        }

        bytes32 hash = sha256(bytes(name));
        bytes memory hexString = _bytesToHexString(abi.encodePacked(hash));
        bytes memory first10 = new bytes(10);
        for (uint256 i = 0; i < 10; i++) {
            first10[i] = hexString[i];
        }

        s_expectedWorkflowName = bytes10(first10);
        emit ExpectedWorkflowNameUpdated(previous, s_expectedWorkflowName);
    }

    function setExpectedWorkflowId(bytes32 workflowId) external onlyOwner {
        bytes32 previous = s_expectedWorkflowId;
        s_expectedWorkflowId = workflowId;
        emit ExpectedWorkflowIdUpdated(previous, workflowId);
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IWorkflowReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function _processReport(bytes calldata report) internal virtual;

    function _decodeMetadata(bytes calldata metadata)
        internal
        pure
        returns (bytes32 workflowId, bytes10 workflowName, address workflowOwner)
    {
        // Metadata layout (abi.encodePacked): bytes32 workflowId | bytes10 workflowName | address workflowOwner
        if (metadata.length < 62) revert InvalidMetadataLength(metadata.length);
        assembly {
            workflowId := calldataload(metadata.offset)
            workflowName := calldataload(add(metadata.offset, 32))
            workflowOwner := shr(96, calldataload(add(metadata.offset, 42)))
        }
    }

    function _bytesToHexString(bytes memory data) private pure returns (bytes memory) {
        bytes memory hexString = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            hexString[i * 2] = HEX_CHARS[uint8(data[i] >> 4)];
            hexString[i * 2 + 1] = HEX_CHARS[uint8(data[i] & 0x0f)];
        }
        return hexString;
    }
}

