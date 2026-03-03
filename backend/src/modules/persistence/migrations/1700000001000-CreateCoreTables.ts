import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateCoreTables1700000001000 implements MigrationInterface {
  name = 'CreateCoreTables1700000001000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS protocol_adapters (
        id SERIAL PRIMARY KEY,
        chain_id INTEGER NOT NULL REFERENCES chains(chain_id) ON DELETE CASCADE,
        protocol VARCHAR(32) NOT NULL,
        adapter_address VARCHAR(42) NOT NULL,
        market_address VARCHAR(42) NOT NULL,
        collateral_asset VARCHAR(42) NOT NULL,
        debt_asset VARCHAR(42) NOT NULL,
        is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_protocol_adapters_chain_adapter
      ON protocol_adapters(chain_id, adapter_address);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS position_snapshots (
        id SERIAL PRIMARY KEY,
        user_address VARCHAR(42) NOT NULL,
        chain_id INTEGER NOT NULL REFERENCES chains(chain_id) ON DELETE CASCADE,
        protocol VARCHAR(32) NOT NULL,
        adapter_address VARCHAR(42) NOT NULL,
        collateral_asset VARCHAR(42) NOT NULL,
        debt_asset VARCHAR(42) NOT NULL,
        collateral_amount_raw NUMERIC(78, 0) NOT NULL,
        debt_amount_raw NUMERIC(78, 0) NOT NULL,
        health_factor_wad NUMERIC(78, 0) NOT NULL,
        ltv_bps INTEGER,
        max_ltv_bps INTEGER,
        liquidation_threshold_bps INTEGER,
        synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_position_snapshots_user_chain_adapter_assets
      ON position_snapshots(user_address, chain_id, adapter_address, collateral_asset, debt_asset);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS position_sync_jobs (
        id SERIAL PRIMARY KEY,
        user_address VARCHAR(42) NOT NULL,
        trigger VARCHAR(24) NOT NULL,
        status VARCHAR(24) NOT NULL,
        requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        started_at TIMESTAMPTZ,
        finished_at TIMESTAMPTZ,
        error TEXT
      );
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_position_sync_jobs_user_requested_at
      ON position_sync_jobs(user_address, requested_at);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS rescue_events (
        id SERIAL PRIMARY KEY,
        chain_id INTEGER NOT NULL REFERENCES chains(chain_id) ON DELETE CASCADE,
        block_number BIGINT NOT NULL,
        tx_hash VARCHAR(66) NOT NULL,
        log_index INTEGER NOT NULL,
        contract_address VARCHAR(42) NOT NULL,
        event_name VARCHAR(96) NOT NULL,
        exec_id VARCHAR(66),
        user_address VARCHAR(42),
        message_id VARCHAR(66),
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        indexed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_rescue_events_chain_tx_log
      ON rescue_events(chain_id, tx_hash, log_index);
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_rescue_events_exec_id
      ON rescue_events(exec_id);
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_rescue_events_message_id
      ON rescue_events(message_id);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS rescue_executions (
        id SERIAL PRIMARY KEY,
        exec_id VARCHAR(66) NOT NULL,
        user_address VARCHAR(42) NOT NULL,
        source_chain_id INTEGER,
        mode VARCHAR(16),
        status VARCHAR(24) NOT NULL,
        ccip_message_id VARCHAR(66),
        source_tx_hash VARCHAR(66),
        destination_chain_id INTEGER,
        last_event_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_rescue_executions_exec_id
      ON rescue_executions(exec_id);
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_rescue_executions_user_status
      ON rescue_executions(user_address, status);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS relay_jobs (
        id SERIAL PRIMARY KEY,
        message_id VARCHAR(66) NOT NULL,
        source_chain_id INTEGER NOT NULL,
        destination_chain_id INTEGER NOT NULL,
        exec_id VARCHAR(66),
        status VARCHAR(24) NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TIMESTAMPTZ,
        last_error TEXT,
        last_stdout TEXT,
        last_stderr TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_relay_jobs_message_id
      ON relay_jobs(message_id);
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_relay_jobs_status_next_attempt
      ON relay_jobs(status, next_attempt_at);
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE IF EXISTS relay_jobs;');
    await queryRunner.query('DROP TABLE IF EXISTS rescue_executions;');
    await queryRunner.query('DROP TABLE IF EXISTS rescue_events;');
    await queryRunner.query('DROP TABLE IF EXISTS position_sync_jobs;');
    await queryRunner.query('DROP TABLE IF EXISTS position_snapshots;');
    await queryRunner.query('DROP TABLE IF EXISTS protocol_adapters;');
  }
}
