import { Column, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'demo_wallets' })
@Index('uq_demo_wallets_real_user_address', ['realUserAddress'], { unique: true })
@Index('uq_demo_wallets_demo_wallet_address', ['demoWalletAddress'], { unique: true })
export class DemoWalletEntity {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'real_user_address', type: 'varchar', length: 42 })
  realUserAddress!: string;

  @Column({ name: 'demo_wallet_address', type: 'varchar', length: 42 })
  demoWalletAddress!: string;

  @Column({ name: 'encrypted_private_key', type: 'text' })
  encryptedPrivateKey!: string;

  @Column({ name: 'derivation_version', type: 'varchar', length: 16, default: 'v1' })
  derivationVersion!: string;

  @Column({
    name: 'native_funded_eth_sepolia_wei',
    type: 'numeric',
    precision: 78,
    scale: 0,
    default: () => "'0'",
  })
  nativeFundedEthSepoliaWei!: string;

  @Column({
    name: 'native_funded_base_sepolia_wei',
    type: 'numeric',
    precision: 78,
    scale: 0,
    default: () => "'0'",
  })
  nativeFundedBaseSepoliaWei!: string;

  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'NOW()' })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'NOW()' })
  updatedAt!: Date;
}
