import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'relay_jobs' })
@Index('uq_relay_jobs_message_id', ['messageId'], { unique: true })
@Index('idx_relay_jobs_status_next_attempt', ['status', 'nextAttemptAt'])
export class RelayJobEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'message_id', type: 'varchar', length: 66 })
  messageId!: string;

  @Column({ name: 'source_chain_id', type: 'integer' })
  sourceChainId!: number;

  @Column({ name: 'destination_chain_id', type: 'integer' })
  destinationChainId!: number;

  @Column({ name: 'exec_id', type: 'varchar', length: 66, nullable: true })
  execId!: string | null;

  @Column({ type: 'varchar', length: 24 })
  status!: string;

  @Column({ name: 'attempt_count', type: 'integer', default: 0 })
  attemptCount!: number;

  @Column({ name: 'next_attempt_at', type: 'timestamptz', nullable: true })
  nextAttemptAt!: Date | null;

  @Column({ name: 'last_error', type: 'text', nullable: true })
  lastError!: string | null;

  @Column({ name: 'last_stdout', type: 'text', nullable: true })
  lastStdout!: string | null;

  @Column({ name: 'last_stderr', type: 'text', nullable: true })
  lastStderr!: string | null;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
