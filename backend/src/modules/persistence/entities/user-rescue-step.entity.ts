import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'user_rescue_steps' })
@Index('uq_user_rescue_steps_user_address', ['userAddress'], { unique: true })
export class UserRescueStepEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'user_address', type: 'varchar', length: 42 })
  userAddress!: string;

  @Column({ name: 'current_step', type: 'integer' })
  currentStep!: number;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
