// ==========================================================================
// Workflow Types
// ==========================================================================

import { z } from "zod";

// ========================================
// EVM Configuration
// ========================================

export const evmConfigSchema = z.object({
  chainSelectorName: z.string(),
  chainId: z.number(),
  contractAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  gasLimit: z.string().optional(),
});

export type EvmConfig = z.infer<typeof evmConfigSchema>;

// ========================================
// Main Config
// ========================================

export const configSchema = z.object({
  appApiBaseUrl: z.string().url(),
  evms: z.array(evmConfigSchema),
});

export type Config = z.infer<typeof configSchema>;

// ========================================
// Helper: Get EVM Config
// ========================================

export const getEvmConfig = (config: Config): EvmConfig => {
  if (config.evms.length === 0) {
    throw new Error("No EVM configuration found");
  }
  return config.evms[0];
};

// ========================================
// Add Your Types Below
// ========================================

// Example:
// export interface MyData {
//   id: string;
//   value: bigint;
// }
