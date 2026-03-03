import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'rescue_executions' })
@Index('uq_rescue_executions_exec_id', ['execId'], { unique: true })
@Index('idx_rescue_executions_user_status', ['userAddress', 'status'])
export class RescueExecutionEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'exec_id', type: 'varchar', length: 66 })
  execId!: string;

  @Column({ name: 'user_address', type: 'varchar', length: 42 })
  userAddress!: string;

  @Column({ name: 'source_chain_id', type: 'integer', nullable: true })
  sourceChainId!: number | null;

  @Column({ name: 'mode', type: 'varchar', length: 16, nullable: true })
  mode!: string | null;

  @Column({ name: 'status', type: 'varchar', length: 24 })
  status!: string;

  @Column({ name: 'ccip_message_id', type: 'varchar', length: 66, nullable: true })
  ccipMessageId!: string | null;

  @Column({ name: 'source_tx_hash', type: 'varchar', length: 66, nullable: true })
  sourceTxHash!: string | null;

  @Column({ name: 'destination_chain_id', type: 'integer', nullable: true })
  destinationChainId!: number | null;

  @Column({ name: 'last_event_at', type: 'timestamptz', nullable: true })
  lastEventAt!: Date | null;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
