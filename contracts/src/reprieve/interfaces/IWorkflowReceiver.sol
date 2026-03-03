// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";

/**
 * @title IWorkflowReceiver
 * @notice CRE report receiver interface.
 */
interface IWorkflowReceiver is IERC165 {
    /**
     * @notice Handles incoming CRE workflow reports.
     * @param metadata Metadata emitted by the CRE forwarder.
     * @param report ABI-encoded workflow payload.
     */
    function onReport(bytes calldata metadata, bytes calldata report) external;
}

