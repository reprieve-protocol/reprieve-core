import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ChainsModule } from '../chains/chains.module';
import {
  DemoWalletBootstrapRunEntity,
  DemoWalletEntity,
  DemoWalletFundingRunEntity,
} from '../persistence/entities';
import { DemoWalletsController } from './demo-wallets.controller';
import { DemoWalletsService } from './demo-wallets.service';

@Module({
  imports: [
    ChainsModule,
    TypeOrmModule.forFeature([
      DemoWalletEntity,
      DemoWalletFundingRunEntity,
      DemoWalletBootstrapRunEntity,
    ]),
  ],
  controllers: [DemoWalletsController],
  providers: [DemoWalletsService],
  exports: [DemoWalletsService],
})
export class DemoWalletsModule {}
