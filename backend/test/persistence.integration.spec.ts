import { DataSource } from 'typeorm';
import { createDataSourceFromEnv } from '../src/modules/persistence/data-source';
import { CreateCoreTables1700000001000 } from '../src/modules/persistence/migrations/1700000001000-CreateCoreTables';

const shouldRun = process.env.RUN_DB_TESTS === '1';
const runIfDb = shouldRun ? it : it.skip;

describe('Persistence integration (RUN_DB_TESTS=1)', () => {
  let dataSource: DataSource;

  beforeAll(async () => {
    if (!shouldRun) {
      return;
    }

    process.env.DB_HOST ??= '127.0.0.1';
    process.env.DB_PORT ??= '5432';
    process.env.DB_USER ??= 'reprieve';
    process.env.DB_PASSWORD ??= 'reprieve';
    process.env.DB_NAME ??= 'reprieve_backend';
    process.env.ETHEREUM_SEPOLIA_RPC_URL ??= 'http://localhost:8545';
    process.env.BASE_SEPOLIA_RPC_URL ??= 'http://localhost:8546';

    dataSource = createDataSourceFromEnv(process.env);
    await dataSource.initialize();
    await dataSource.runMigrations();
  });

  afterAll(async () => {
    if (dataSource?.isInitialized) {
      await dataSource.destroy();
    }
  });

  runIfDb('applies migrations and creates core tables', async () => {
    const rows = await dataSource.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema='public'
    `);

    const names = rows.map((row: { table_name: string }) => row.table_name);

    expect(names).toEqual(
      expect.arrayContaining([
        'chains',
        'protocol_adapters',
        'position_snapshots',
        'rescue_events',
        'rescue_executions',
        'relay_jobs',
      ]),
    );
  });

  runIfDb('supports repository CRUD and unique constraints', async () => {
    const chainRepo = dataSource.getRepository('chains');
    const adapterRepo = dataSource.getRepository('protocol_adapters');
    const rescueEventRepo = dataSource.getRepository('rescue_events');
    const relayJobRepo = dataSource.getRepository('relay_jobs');

    const uniqueSuffix = Date.now().toString();

    const chain = await chainRepo.save({
      key: `ethereum-sepolia-${uniqueSuffix}`,
      chainId: Number(`11${uniqueSuffix.slice(-6)}`),
      rpcUrl: 'http://localhost:8545',
      isEnabled: true,
    });

    const adapter = await adapterRepo.save({
      chainId: chain.chainId,
      protocol: 'AAVE',
      adapterAddress: `0x${'1'.repeat(38)}${uniqueSuffix.slice(-2)}`,
      marketAddress: `0x${'2'.repeat(38)}${uniqueSuffix.slice(-2)}`,
      collateralAsset: `0x${'3'.repeat(38)}${uniqueSuffix.slice(-2)}`,
      debtAsset: `0x${'4'.repeat(38)}${uniqueSuffix.slice(-2)}`,
      isEnabled: true,
    });

    expect(adapter.id).toBeGreaterThan(0);

    const txHash = `0x${'a'.repeat(64)}`;
    await rescueEventRepo.insert({
      chainId: chain.chainId,
      blockNumber: '12345',
      txHash,
      logIndex: 1,
      contractAddress: `0x${'5'.repeat(40)}`,
      eventName: 'RescueInitiated',
      payload: { test: true },
    });

    await expect(
      rescueEventRepo.insert({
        chainId: chain.chainId,
        blockNumber: '12345',
        txHash,
        logIndex: 1,
        contractAddress: `0x${'5'.repeat(40)}`,
        eventName: 'RescueInitiated',
        payload: {},
      }),
    ).rejects.toThrow();

    const messageId = `0x${'d'.repeat(64)}`;
    await relayJobRepo.insert({
      messageId,
      sourceChainId: 11155111,
      destinationChainId: 84532,
      status: 'pending',
      attemptCount: 0,
    });

    await expect(
      relayJobRepo.insert({
        messageId,
        sourceChainId: 11155111,
        destinationChainId: 84532,
        status: 'pending',
        attemptCount: 0,
      }),
    ).rejects.toThrow();
  });

  runIfDb('exercises migration down path in transaction', async () => {
    const queryRunner = dataSource.createQueryRunner();
    await queryRunner.connect();
    await queryRunner.startTransaction();

    try {
      const coreMigration = new CreateCoreTables1700000001000();
      await coreMigration.down(queryRunner);

      const rows = await queryRunner.query(`
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema='public' AND table_name='relay_jobs'
      `);

      expect(rows).toHaveLength(0);

      await queryRunner.rollbackTransaction();
    } finally {
      await queryRunner.release();
    }
  });
});
