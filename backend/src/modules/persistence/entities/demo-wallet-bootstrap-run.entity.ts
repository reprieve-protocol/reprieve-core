import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'demo_wallet_bootstrap_runs' })
@Index('idx_demo_wallet_bootstrap_runs_wallet_mode_created', [
  'demoWalletId',
  'rescueMode',
  'createdAt',
])
export class DemoWalletBootstrapRunEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'demo_wallet_id', type: 'integer' })
  demoWalletId!: number;

  @Column({ name: 'rescue_mode', type: 'varchar', length: 16 })
  rescueMode!: string;

  @Column({ name: 'status', type: 'varchar', length: 24 })
  status!: string;

  @Column({ name: 'request_payload', type: 'jsonb', default: () => "'{}'::jsonb" })
  requestPayload!: Record<string, unknown>;

  @Column({ name: 'result_payload', type: 'jsonb', default: () => "'{}'::jsonb" })
  resultPayload!: Record<string, unknown>;

  @Column({ name: 'error_message', type: 'text', nullable: true })
  errorMessage!: string | null;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
