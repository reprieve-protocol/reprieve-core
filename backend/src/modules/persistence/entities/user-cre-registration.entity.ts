import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'user_cre_registrations' })
@Index('uq_user_cre_registrations_user_address', ['userAddress'], { unique: true })
export class UserCreRegistrationEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'user_address', type: 'varchar', length: 42 })
  userAddress!: string;

  @Column({ name: 'workflow_id', type: 'varchar', length: 64 })
  workflowId!: string;

  @Column({ name: 'hf_threshold_bps', type: 'integer' })
  hfThresholdBps!: number;

  @Column({ name: 'queue_priority', type: 'varchar', length: 32 })
  queuePriority!: string;

  @Column({
    name: 'budget_cap_usd',
    type: 'numeric',
    precision: 20,
    scale: 2,
  })
  budgetCapUsd!: string;

  @Column({ name: 'is_active', type: 'boolean', default: true })
  isActive!: boolean;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
