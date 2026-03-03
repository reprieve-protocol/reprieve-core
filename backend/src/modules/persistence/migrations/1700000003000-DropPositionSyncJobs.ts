import { MigrationInterface, QueryRunner } from 'typeorm';

export class DropPositionSyncJobs1700000003000 implements MigrationInterface {
  name = 'DropPositionSyncJobs1700000003000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      'DROP INDEX IF EXISTS idx_position_sync_jobs_user_requested_at;',
    );
    await queryRunner.query('DROP TABLE IF EXISTS position_sync_jobs;');
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS position_sync_jobs (
        id SERIAL PRIMARY KEY,
        user_address VARCHAR(42) NOT NULL,
        trigger VARCHAR(24) NOT NULL,
        status VARCHAR(24) NOT NULL,
        requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        started_at TIMESTAMPTZ NULL,
        finished_at TIMESTAMPTZ NULL,
        error TEXT NULL
      );
    `);

    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_position_sync_jobs_user_requested_at
      ON position_sync_jobs(user_address, requested_at);
    `);
  }
}
