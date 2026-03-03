import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'position_snapshots' })
@Index(
  'uq_position_snapshots_user_chain_adapter_assets',
  ['userAddress', 'chainId', 'adapterAddress', 'collateralAsset', 'debtAsset'],
  { unique: true },
)
export class PositionSnapshotEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'user_address', type: 'varchar', length: 42 })
  userAddress!: string;

  @Column({ name: 'chain_id', type: 'integer' })
  chainId!: number;

  @Column({ type: 'varchar', length: 32 })
  protocol!: string;

  @Column({ name: 'adapter_address', type: 'varchar', length: 42 })
  adapterAddress!: string;

  @Column({ name: 'collateral_asset', type: 'varchar', length: 42 })
  collateralAsset!: string;

  @Column({ name: 'debt_asset', type: 'varchar', length: 42 })
  debtAsset!: string;

  @Column({ name: 'collateral_amount_raw', type: 'numeric', precision: 78, scale: 0 })
  collateralAmountRaw!: string;

  @Column({ name: 'debt_amount_raw', type: 'numeric', precision: 78, scale: 0 })
  debtAmountRaw!: string;

  @Column({ name: 'health_factor_wad', type: 'numeric', precision: 78, scale: 0 })
  healthFactorWad!: string;

  @Column({ name: 'ltv_bps', type: 'integer', nullable: true })
  ltvBps!: number | null;

  @Column({ name: 'max_ltv_bps', type: 'integer', nullable: true })
  maxLtvBps!: number | null;

  @Column({ name: 'liquidation_threshold_bps', type: 'integer', nullable: true })
  liquidationThresholdBps!: number | null;

  @Column({ name: 'synced_at', type: 'timestamptz', default: () => 'NOW()' })
  syncedAt!: Date;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
