import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'rescue_workflow_logs' })
@Index('idx_rescue_workflow_logs_exec_id_created', ['execId', 'createdAt'])
@Index('idx_rescue_workflow_logs_execution_id', ['rescueExecutionId'])
export class RescueWorkflowLogEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'rescue_execution_id', type: 'integer' })
  rescueExecutionId!: number;

  @Column({ name: 'exec_id', type: 'varchar', length: 66 })
  execId!: string;

  @Column({ name: 'workflow_id', type: 'varchar', length: 64, nullable: true })
  workflowId!: string | null;

  @Column({ name: 'run_id', type: 'varchar', length: 128, nullable: true })
  runId!: string | null;

  @Column({ name: 'log_text', type: 'text' })
  logText!: string;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  metadata!: Record<string, unknown>;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;
}
