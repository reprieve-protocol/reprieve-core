import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateUserRescueStepsTable1700000008000
  implements MigrationInterface
{
  name = 'CreateUserRescueStepsTable1700000008000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS user_rescue_steps (
        id SERIAL PRIMARY KEY,
        user_address VARCHAR(42) NOT NULL UNIQUE,
        current_step INTEGER NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_user_rescue_steps_current_step_range CHECK (current_step >= 0 AND current_step <= 4)
      );
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE IF EXISTS user_rescue_steps;');
  }
}
