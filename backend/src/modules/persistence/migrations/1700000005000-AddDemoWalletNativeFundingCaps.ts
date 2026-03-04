import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddDemoWalletNativeFundingCaps1700000005000
  implements MigrationInterface
{
  name = 'AddDemoWalletNativeFundingCaps1700000005000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE demo_wallets
      ADD COLUMN IF NOT EXISTS native_funded_eth_sepolia_wei NUMERIC(78, 0) NOT NULL DEFAULT 0;
    `);
    await queryRunner.query(`
      ALTER TABLE demo_wallets
      ADD COLUMN IF NOT EXISTS native_funded_base_sepolia_wei NUMERIC(78, 0) NOT NULL DEFAULT 0;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE demo_wallets
      DROP COLUMN IF EXISTS native_funded_base_sepolia_wei;
    `);
    await queryRunner.query(`
      ALTER TABLE demo_wallets
      DROP COLUMN IF EXISTS native_funded_eth_sepolia_wei;
    `);
  }
}
