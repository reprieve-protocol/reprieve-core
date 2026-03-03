import { MigrationInterface, QueryRunner } from 'typeorm';

export class InitFoundation1700000000000 implements MigrationInterface {
  name = 'InitFoundation1700000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS chains (
        id SERIAL PRIMARY KEY,
        key VARCHAR(64) NOT NULL UNIQUE,
        chain_id INTEGER NOT NULL UNIQUE,
        rpc_url TEXT NOT NULL,
        is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE IF EXISTS chains;');
  }
}
