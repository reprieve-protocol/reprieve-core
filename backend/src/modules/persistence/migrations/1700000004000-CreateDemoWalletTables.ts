import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateDemoWalletTables1700000004000 implements MigrationInterface {
  name = 'CreateDemoWalletTables1700000004000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS demo_wallets (
        id SERIAL PRIMARY KEY,
        real_user_address VARCHAR(42) NOT NULL,
        demo_wallet_address VARCHAR(42) NOT NULL,
        encrypted_private_key TEXT NOT NULL,
        derivation_version VARCHAR(16) NOT NULL DEFAULT 'v1',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_demo_wallets_real_user_address
      ON demo_wallets(real_user_address);
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_demo_wallets_demo_wallet_address
      ON demo_wallets(demo_wallet_address);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS demo_wallet_funding_runs (
        id SERIAL PRIMARY KEY,
        demo_wallet_id INTEGER NOT NULL REFERENCES demo_wallets(id) ON DELETE CASCADE,
        status VARCHAR(24) NOT NULL,
        request_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        result_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        error_message TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_demo_wallet_funding_runs_wallet_created
      ON demo_wallet_funding_runs(demo_wallet_id, created_at);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS demo_wallet_bootstrap_runs (
        id SERIAL PRIMARY KEY,
        demo_wallet_id INTEGER NOT NULL REFERENCES demo_wallets(id) ON DELETE CASCADE,
        rescue_mode VARCHAR(16) NOT NULL,
        status VARCHAR(24) NOT NULL,
        request_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        result_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        error_message TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_demo_wallet_bootstrap_runs_wallet_mode_created
      ON demo_wallet_bootstrap_runs(demo_wallet_id, rescue_mode, created_at);
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE IF EXISTS demo_wallet_bootstrap_runs;');
    await queryRunner.query('DROP TABLE IF EXISTS demo_wallet_funding_runs;');
    await queryRunner.query('DROP TABLE IF EXISTS demo_wallets;');
  }
}
