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
  PROJECTION_REBUILD_BATCH_SIZE: string;
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
    CONTRACTS_CONFIG_DIR: String(rawEnv.CONTRACTS_CONFIG_DIR ?? '../contracts/config'),
    ETHEREUM_SEPOLIA_START_BLOCK: String(rawEnv.ETHEREUM_SEPOLIA_START_BLOCK ?? '0'),
    BASE_SEPOLIA_START_BLOCK: String(rawEnv.BASE_SEPOLIA_START_BLOCK ?? '0'),
    INDEXER_BLOCK_WINDOW: String(rawEnv.INDEXER_BLOCK_WINDOW ?? '1000'),
    INDEXER_CONFIRMATIONS: String(rawEnv.INDEXER_CONFIRMATIONS ?? '0'),
    INDEXER_POLL_INTERVAL_MS: String(rawEnv.INDEXER_POLL_INTERVAL_MS ?? '15000'),
    PROJECTION_REBUILD_BATCH_SIZE: String(rawEnv.PROJECTION_REBUILD_BATCH_SIZE ?? '500'),
    SWAGGER_ENABLED: String(rawEnv.SWAGGER_ENABLED ?? 'true'),
    SWAGGER_PATH: String(rawEnv.SWAGGER_PATH ?? 'docs'),
  };
};
