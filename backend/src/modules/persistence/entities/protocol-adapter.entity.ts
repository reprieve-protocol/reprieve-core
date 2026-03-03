import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'protocol_adapters' })
@Index('uq_protocol_adapters_chain_adapter', ['chainId', 'adapterAddress'], {
  unique: true,
})
export class ProtocolAdapterEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'chain_id', type: 'integer' })
  chainId!: number;

  @Column({ type: 'varchar', length: 32 })
  protocol!: string;

  @Column({ name: 'adapter_address', type: 'varchar', length: 42 })
  adapterAddress!: string;

  @Column({ name: 'market_address', type: 'varchar', length: 42 })
  marketAddress!: string;

  @Column({ name: 'collateral_asset', type: 'varchar', length: 42 })
  collateralAsset!: string;

  @Column({ name: 'debt_asset', type: 'varchar', length: 42 })
  debtAsset!: string;

  @Column({ name: 'is_enabled', type: 'boolean', default: true })
  isEnabled!: boolean;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
