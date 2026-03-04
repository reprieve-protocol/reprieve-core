import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'user_cre_registration_revisions' })
@Index('idx_user_cre_registration_revisions_user_created', ['userAddress', 'createdAt'])
@Index('idx_user_cre_registration_revisions_registration_id', ['registrationId'])
export class UserCreRegistrationRevisionEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'registration_id', type: 'integer' })
  registrationId!: number;

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

  @Column({ name: 'change_type', type: 'varchar', length: 16 })
  changeType!: string;

  @Column({ name: 'change_source', type: 'varchar', length: 32, default: 'api' })
  changeSource!: string;

  @Column({ name: 'updated_by', type: 'varchar', length: 128, nullable: true })
  updatedBy!: string | null;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;
}
