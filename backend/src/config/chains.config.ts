export type SupportedChainKey = 'ethereum-sepolia' | 'base-sepolia';

export interface SupportedChainMetadata {
  key: SupportedChainKey;
  chainId: number;
  ccipSelector: string;
  envRpcKey: 'ETHEREUM_SEPOLIA_RPC_URL' | 'BASE_SEPOLIA_RPC_URL';
  envStartBlockKey: 'ETHEREUM_SEPOLIA_START_BLOCK' | 'BASE_SEPOLIA_START_BLOCK';
}

export const SUPPORTED_CHAINS: Record<SupportedChainKey, SupportedChainMetadata> = {
  'ethereum-sepolia': {
    key: 'ethereum-sepolia',
    chainId: 11155111,
    ccipSelector: '16015286601757825753',
    envRpcKey: 'ETHEREUM_SEPOLIA_RPC_URL',
    envStartBlockKey: 'ETHEREUM_SEPOLIA_START_BLOCK',
  },
  'base-sepolia': {
    key: 'base-sepolia',
    chainId: 84532,
    ccipSelector: '10344971235874465080',
    envRpcKey: 'BASE_SEPOLIA_RPC_URL',
    envStartBlockKey: 'BASE_SEPOLIA_START_BLOCK',
  },
};

export const SUPPORTED_CHAIN_KEYS = Object.keys(
  SUPPORTED_CHAINS,
) as SupportedChainKey[];
