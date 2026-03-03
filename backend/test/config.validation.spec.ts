import { validateEnv } from '../src/config/env.validation';

describe('validateEnv', () => {
  it('accepts valid config', () => {
    const env = validateEnv({
      DB_HOST: '127.0.0.1',
      DB_PORT: '5432',
      DB_USER: 'reprieve',
      DB_PASSWORD: 'reprieve',
      DB_NAME: 'reprieve_backend',
      ETHEREUM_SEPOLIA_RPC_URL: 'https://eth.example',
      BASE_SEPOLIA_RPC_URL: 'https://base.example',
    });

    expect(env.DB_PORT).toBe('5432');
    expect(env.ETHEREUM_SEPOLIA_RPC_URL).toContain('https://');
  });

  it('throws when rpc url is missing', () => {
    expect(() =>
      validateEnv({
        DB_HOST: '127.0.0.1',
        DB_PORT: '5432',
        DB_USER: 'reprieve',
        DB_PASSWORD: 'reprieve',
        DB_NAME: 'reprieve_backend',
        ETHEREUM_SEPOLIA_RPC_URL: 'https://eth.example',
      }),
    ).toThrow(/BASE_SEPOLIA_RPC_URL is required/);
  });

  it('throws when DB_PORT is invalid', () => {
    expect(() =>
      validateEnv({
        DB_HOST: '127.0.0.1',
        DB_PORT: 'abc',
        DB_USER: 'reprieve',
        DB_PASSWORD: 'reprieve',
        DB_NAME: 'reprieve_backend',
        ETHEREUM_SEPOLIA_RPC_URL: 'https://eth.example',
        BASE_SEPOLIA_RPC_URL: 'https://base.example',
      }),
    ).toThrow(/DB_PORT must be numeric/);
  });
});
