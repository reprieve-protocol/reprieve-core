// ==========================================================================
// EVM Interaction Helpers
// ==========================================================================

import { cre, type Runtime, getNetwork, hexToBase64 } from "@chainlink/cre-sdk";
import { encodeFunctionData, parseAbi } from "viem";
import type { Config, EvmConfig } from "../types";

// ========================================
// Retry Utility
// ========================================

export const withRetry = async <T>(
  fn: () => Promise<T>,
  maxRetries = 3
): Promise<T> => {
  let lastError: Error | undefined;
  
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      // Continue to next retry (no delay in CRE WASM environment)
    }
  }
  
  throw lastError;
};

// ========================================
// EVM Client Setup
// ========================================

export const createEvmClient = (evmConfig: EvmConfig) => {
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: evmConfig.chainSelectorName,
    isTestnet: evmConfig.chainSelectorName.includes("testnet"),
  });

  if (!network) {
    throw new Error(`Network not found: ${evmConfig.chainSelectorName}`);
  }

  return new cre.capabilities.EVMClient(network.chainSelector.selector);
};

// ========================================
// Generic Contract Write Helper
// ========================================

export interface ContractWriteParams {
  contractAddress: string;
  abi: string[];
  functionName: string;
  args: unknown[];
  gasLimit?: string;
}

export const writeContract = (
  runtime: Runtime<Config>,
  evmConfig: EvmConfig,
  params: ContractWriteParams
): string => {
  const evmClient = createEvmClient(evmConfig);
  const abi = parseAbi(params.abi);

  const calldata = encodeFunctionData({
    abi,
    functionName: params.functionName,
    args: params.args,
  });

  runtime.log(`Calling ${params.functionName} on ${params.contractAddress}`);

  const result = evmClient.write(
    {
      contractAddress: hexToBase64(params.contractAddress),
      calldata: hexToBase64(calldata),
    },
    {
      gasLimit: params.gasLimit || evmConfig.gasLimit || "500000",
    }
  );

  const txHash = result.transactionHash;
  
  if (!txHash) {
    throw new Error("Transaction failed: no transaction hash returned");
  }

  // Convert base64 txHash to hex
  const txHashHex = "0x" + Buffer.from(txHash, "base64").toString("hex");
  runtime.log(`Transaction submitted: ${txHashHex}`);

  return txHashHex;
};

// ========================================
// Add Your Contract-Specific Functions Below
// ========================================

// Example:
// export const submitMyReport = (
//   runtime: Runtime<Config>,
//   evmConfig: EvmConfig,
//   data: MyReportData
// ): string => {
//   return writeContract(runtime, evmConfig, {
//     contractAddress: evmConfig.contractAddress,
//     abi: ["function submitReport(uint256 value) returns (bool)"],
//     functionName: "submitReport",
//     args: [data.value],
//     gasLimit: "500000",
//   });
// };
