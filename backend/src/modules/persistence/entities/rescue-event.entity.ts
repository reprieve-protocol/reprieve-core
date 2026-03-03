import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'rescue_events' })
@Index('uq_rescue_events_chain_tx_log', ['chainId', 'txHash', 'logIndex'], {
  unique: true,
})
@Index('idx_rescue_events_exec_id', ['execId'])
@Index('idx_rescue_events_message_id', ['messageId'])
export class RescueEventEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'chain_id', type: 'integer' })
  chainId!: number;

  @Column({ name: 'block_number', type: 'bigint' })
  blockNumber!: string;

  @Column({ name: 'tx_hash', type: 'varchar', length: 66 })
  txHash!: string;

  @Column({ name: 'log_index', type: 'integer' })
  logIndex!: number;

  @Column({ name: 'contract_address', type: 'varchar', length: 42 })
  contractAddress!: string;

  @Column({ name: 'event_name', type: 'varchar', length: 96 })
  eventName!: string;

  @Column({ name: 'exec_id', type: 'varchar', length: 66, nullable: true })
  execId!: string | null;

  @Column({ name: 'user_address', type: 'varchar', length: 42, nullable: true })
  userAddress!: string | null;

  @Column({ name: 'message_id', type: 'varchar', length: 66, nullable: true })
  messageId!: string | null;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  payload!: Record<string, unknown>;

  @Column({ name: 'indexed_at', type: 'timestamptz', default: () => 'NOW()' })
  indexedAt!: Date;
}
