import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateUserCreRegistrationTables1700000006000
  implements MigrationInterface
{
  name = 'CreateUserCreRegistrationTables1700000006000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS user_cre_registrations (
        id SERIAL PRIMARY KEY,
        user_address VARCHAR(42) NOT NULL,
        workflow_id VARCHAR(64) NOT NULL,
        hf_threshold_bps INTEGER NOT NULL,
        queue_priority VARCHAR(32) NOT NULL,
        budget_cap_usd NUMERIC(20, 2) NOT NULL,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS uq_user_cre_registrations_user_address
      ON user_cre_registrations(user_address);
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS user_cre_registration_revisions (
        id SERIAL PRIMARY KEY,
        registration_id INTEGER NOT NULL REFERENCES user_cre_registrations(id) ON DELETE CASCADE,
        user_address VARCHAR(42) NOT NULL,
        workflow_id VARCHAR(64) NOT NULL,
        hf_threshold_bps INTEGER NOT NULL,
        queue_priority VARCHAR(32) NOT NULL,
        budget_cap_usd NUMERIC(20, 2) NOT NULL,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        change_type VARCHAR(16) NOT NULL,
        change_source VARCHAR(32) NOT NULL DEFAULT 'api',
        updated_by VARCHAR(128),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_user_cre_registration_revisions_user_created
      ON user_cre_registration_revisions(user_address, created_at);
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_user_cre_registration_revisions_registration_id
      ON user_cre_registration_revisions(registration_id);
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE IF EXISTS user_cre_registration_revisions;');
    await queryRunner.query('DROP TABLE IF EXISTS user_cre_registrations;');
  }
}
