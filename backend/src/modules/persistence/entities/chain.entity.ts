import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'chains' })
export class ChainEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Index({ unique: true })
  @Column({ type: 'varchar', length: 64 })
  key!: string;

  @Index({ unique: true })
  @Column({ name: 'chain_id', type: 'integer' })
  chainId!: number;

  @Column({ name: 'rpc_url', type: 'text' })
  rpcUrl!: string;

  @Column({ name: 'is_enabled', type: 'boolean', default: true })
  isEnabled!: boolean;

  @Column({ name: 'indexer_enabled', type: 'boolean', default: true })
  indexerEnabled!: boolean;

  @Column({ name: 'indexer_cursor_block', type: 'bigint', nullable: true })
  indexerCursorBlock!: string | null;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
