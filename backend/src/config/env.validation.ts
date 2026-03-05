const REQUIRED_ENV_KEYS = [
  'DB_HOST',
  'DB_PORT',
  'DB_USER',
  'DB_PASSWORD',
  'DB_NAME',
  'ETHEREUM_SEPOLIA_RPC_URL',
  'BASE_SEPOLIA_RPC_URL',
] as const;

export interface AppEnv {
  NODE_ENV: string;
  APP_PORT: string;
  DB_HOST: string;
  DB_PORT: string;
  DB_USER: string;
  DB_PASSWORD: string;
  DB_NAME: string;
  DB_SSL: string;
  DB_DISABLE: string;
  ETHEREUM_SEPOLIA_RPC_URL: string;
  BASE_SEPOLIA_RPC_URL: string;
  CONTRACTS_CONFIG_DIR: string;
  ETHEREUM_SEPOLIA_START_BLOCK: string;
  BASE_SEPOLIA_START_BLOCK: string;
  INDEXER_BLOCK_WINDOW: string;
  INDEXER_CONFIRMATIONS: string;
  INDEXER_POLL_INTERVAL_MS: string;
  INDEXER_RUN_IN_API: string;
  PROJECTION_REBUILD_BATCH_SIZE: string;
  RELAY_POLL_INTERVAL_MS: string;
  RELAY_BATCH_SIZE: string;
  RELAY_MAX_ATTEMPTS: string;
  RELAY_BACKOFF_BASE_MS: string;
  RELAY_BACKOFF_MAX_MS: string;
  RELAY_COMMAND_TIMEOUT_MS: string;
  RELAY_SCAN_LIMIT: string;
  RELAY_RUNNING_STALE_MS: string;
  RELAY_SIGNER_PRIVATE_KEY: string;
  ETHEREUM_SEPOLIA_PRIVATE_KEY: string;
  BASE_SEPOLIA_PRIVATE_KEY: string;
  DEMO_WALLET_MASTER_SECRET: string;
  DEMO_WALLET_ENCRYPTION_KEY: string;
  DEMO_WALLET_DEFAULT_ETH_SEPOLIA_GAS_ETH: string;
  DEMO_WALLET_DEFAULT_BASE_SEPOLIA_GAS_ETH: string;
  DEMO_WALLET_DEFAULT_ETH_WETH: string;
  DEMO_WALLET_DEFAULT_ETH_USDC: string;
  DEMO_WALLET_DEFAULT_BASE_WETH: string;
  DEMO_WALLET_DEFAULT_BASE_USDC: string;
  DEMO_REPAY_BASE_COMPOUND_MARKET: string;
  SWAGGER_ENABLED: string;
  SWAGGER_PATH: string;
}

const assertEnv = (condition: boolean, message: string): void => {
  if (!condition) {
    throw new Error(`Invalid environment configuration: ${message}`);
  }
};

export const validateEnv = (rawEnv: Record<string, unknown>): AppEnv => {
  for (const key of REQUIRED_ENV_KEYS) {
    const value = rawEnv[key];
    assertEnv(
      typeof value === 'string' && value.trim().length > 0,
      `${key} is required`,
    );
  }

  const dbPort = String(rawEnv.DB_PORT ?? '5432');
  assertEnv(!Number.isNaN(Number(dbPort)), 'DB_PORT must be numeric');

  return {
    NODE_ENV: String(rawEnv.NODE_ENV ?? 'development'),
    APP_PORT: String(rawEnv.APP_PORT ?? '3001'),
    DB_HOST: String(rawEnv.DB_HOST),
    DB_PORT: dbPort,
    DB_USER: String(rawEnv.DB_USER),
    DB_PASSWORD: String(rawEnv.DB_PASSWORD),
    DB_NAME: String(rawEnv.DB_NAME),
    DB_SSL: String(rawEnv.DB_SSL ?? 'false'),
    DB_DISABLE: String(rawEnv.DB_DISABLE ?? 'false'),
    ETHEREUM_SEPOLIA_RPC_URL: String(rawEnv.ETHEREUM_SEPOLIA_RPC_URL),
    BASE_SEPOLIA_RPC_URL: String(rawEnv.BASE_SEPOLIA_RPC_URL),
    CONTRACTS_CONFIG_DIR: String(rawEnv.CONTRACTS_CONFIG_DIR ?? './contracts-config'),
    ETHEREUM_SEPOLIA_START_BLOCK: String(rawEnv.ETHEREUM_SEPOLIA_START_BLOCK ?? '0'),
    BASE_SEPOLIA_START_BLOCK: String(rawEnv.BASE_SEPOLIA_START_BLOCK ?? '0'),
    INDEXER_BLOCK_WINDOW: String(rawEnv.INDEXER_BLOCK_WINDOW ?? '1000'),
    INDEXER_CONFIRMATIONS: String(rawEnv.INDEXER_CONFIRMATIONS ?? '0'),
    INDEXER_POLL_INTERVAL_MS: String(rawEnv.INDEXER_POLL_INTERVAL_MS ?? '15000'),
    INDEXER_RUN_IN_API: String(rawEnv.INDEXER_RUN_IN_API ?? 'true'),
    PROJECTION_REBUILD_BATCH_SIZE: String(rawEnv.PROJECTION_REBUILD_BATCH_SIZE ?? '500'),
    RELAY_POLL_INTERVAL_MS: String(rawEnv.RELAY_POLL_INTERVAL_MS ?? '15000'),
    RELAY_BATCH_SIZE: String(rawEnv.RELAY_BATCH_SIZE ?? '5'),
    RELAY_MAX_ATTEMPTS: String(rawEnv.RELAY_MAX_ATTEMPTS ?? '5'),
    RELAY_BACKOFF_BASE_MS: String(rawEnv.RELAY_BACKOFF_BASE_MS ?? '15000'),
    RELAY_BACKOFF_MAX_MS: String(rawEnv.RELAY_BACKOFF_MAX_MS ?? '300000'),
    RELAY_COMMAND_TIMEOUT_MS: String(rawEnv.RELAY_COMMAND_TIMEOUT_MS ?? '240000'),
    RELAY_SCAN_LIMIT: String(rawEnv.RELAY_SCAN_LIMIT ?? '250'),
    RELAY_RUNNING_STALE_MS: String(rawEnv.RELAY_RUNNING_STALE_MS ?? '300000'),
    RELAY_SIGNER_PRIVATE_KEY: String(rawEnv.RELAY_SIGNER_PRIVATE_KEY ?? ''),
    ETHEREUM_SEPOLIA_PRIVATE_KEY: String(rawEnv.ETHEREUM_SEPOLIA_PRIVATE_KEY ?? ''),
    BASE_SEPOLIA_PRIVATE_KEY: String(rawEnv.BASE_SEPOLIA_PRIVATE_KEY ?? ''),
    DEMO_WALLET_MASTER_SECRET: String(rawEnv.DEMO_WALLET_MASTER_SECRET ?? ''),
    DEMO_WALLET_ENCRYPTION_KEY: String(rawEnv.DEMO_WALLET_ENCRYPTION_KEY ?? ''),
    DEMO_WALLET_DEFAULT_ETH_SEPOLIA_GAS_ETH: String(
      rawEnv.DEMO_WALLET_DEFAULT_ETH_SEPOLIA_GAS_ETH ?? '0.0001',
    ),
    DEMO_WALLET_DEFAULT_BASE_SEPOLIA_GAS_ETH: String(
      rawEnv.DEMO_WALLET_DEFAULT_BASE_SEPOLIA_GAS_ETH ?? '0.0001',
    ),
    DEMO_WALLET_DEFAULT_ETH_WETH: String(rawEnv.DEMO_WALLET_DEFAULT_ETH_WETH ?? '80'),
    DEMO_WALLET_DEFAULT_ETH_USDC: String(rawEnv.DEMO_WALLET_DEFAULT_ETH_USDC ?? '90000'),
    DEMO_WALLET_DEFAULT_BASE_WETH: String(rawEnv.DEMO_WALLET_DEFAULT_BASE_WETH ?? '50'),
    DEMO_WALLET_DEFAULT_BASE_USDC: String(rawEnv.DEMO_WALLET_DEFAULT_BASE_USDC ?? '90000'),
    DEMO_REPAY_BASE_COMPOUND_MARKET: String(rawEnv.DEMO_REPAY_BASE_COMPOUND_MARKET ?? ''),
    SWAGGER_ENABLED: String(rawEnv.SWAGGER_ENABLED ?? 'true'),
    SWAGGER_PATH: String(rawEnv.SWAGGER_PATH ?? 'docs'),
  };
};
