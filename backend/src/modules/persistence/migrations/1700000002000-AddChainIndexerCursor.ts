import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddChainIndexerCursor1700000002000 implements MigrationInterface {
  name = 'AddChainIndexerCursor1700000002000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE chains
      ADD COLUMN IF NOT EXISTS indexer_enabled BOOLEAN NOT NULL DEFAULT TRUE;
    `);

    await queryRunner.query(`
      ALTER TABLE chains
      ADD COLUMN IF NOT EXISTS indexer_cursor_block BIGINT;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE chains
      DROP COLUMN IF EXISTS indexer_cursor_block;
    `);

    await queryRunner.query(`
      ALTER TABLE chains
      DROP COLUMN IF EXISTS indexer_enabled;
    `);
  }
}
