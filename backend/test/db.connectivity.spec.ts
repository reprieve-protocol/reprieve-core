import { DataSource } from 'typeorm';

describe('DB connectivity (docker postgres)', () => {
  let dataSource: DataSource | null = null;

  const shouldRun = process.env.RUN_DB_TESTS === '1';

  it('connects to postgres when RUN_DB_TESTS=1', async () => {
    if (!shouldRun) {
      expect(true).toBe(true);
      return;
    }

    process.env.DB_HOST ??= '127.0.0.1';
    process.env.DB_PORT ??= '5432';
    process.env.DB_USER ??= 'reprieve';
    process.env.DB_PASSWORD ??= 'reprieve';
    process.env.DB_NAME ??= 'reprieve_backend';
    process.env.ETHEREUM_SEPOLIA_RPC_URL ??= 'http://localhost:8545';
    process.env.BASE_SEPOLIA_RPC_URL ??= 'http://localhost:8546';

    const { createDataSourceFromEnv } = await import(
      '../src/modules/persistence/data-source'
    );

    dataSource = createDataSourceFromEnv(process.env);
    await dataSource.initialize();

    expect(dataSource.isInitialized).toBe(true);
  });

  afterAll(async () => {
    if (dataSource?.isInitialized) {
      await dataSource.destroy();
    }
  });
});
