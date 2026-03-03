import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ChainsModule } from '../chains/chains.module';
import {
  ChainEntity,
  RescueEventEntity,
  RescueExecutionEntity,
} from '../persistence/entities';
import { PositionsModule } from '../positions/positions.module';
import { EvmRpcService } from './evm-rpc.service';
import { ReprieveAddressesService } from './reprieve-addresses.service';
import { RescueProjectionService } from './rescue-projection.service';
import { RescueHistoryService } from './rescue-history.service';
import { RescuesController } from './rescues.controller';

@Module({
  imports: [
    ChainsModule,
    PositionsModule,
    TypeOrmModule.forFeature([ChainEntity, RescueEventEntity, RescueExecutionEntity]),
  ],
  controllers: [RescuesController],
  providers: [
    RescueHistoryService,
    RescueProjectionService,
    EvmRpcService,
    ReprieveAddressesService,
  ],
  exports: [RescueHistoryService, RescueProjectionService],
})
export class RescueHistoryModule {}
