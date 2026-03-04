import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateRescueWorkflowLogsTable1700000007000
  implements MigrationInterface
{
  name = 'CreateRescueWorkflowLogsTable1700000007000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS rescue_workflow_logs (
        id SERIAL PRIMARY KEY,
        rescue_execution_id INTEGER NOT NULL REFERENCES rescue_executions(id) ON DELETE CASCADE,
        exec_id VARCHAR(66) NOT NULL,
        workflow_id VARCHAR(64),
        run_id VARCHAR(128),
        log_text TEXT NOT NULL,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_rescue_workflow_logs_exec_id_created
      ON rescue_workflow_logs(exec_id, created_at);
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_rescue_workflow_logs_execution_id
      ON rescue_workflow_logs(rescue_execution_id);
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE IF EXISTS rescue_workflow_logs;');
  }
}
