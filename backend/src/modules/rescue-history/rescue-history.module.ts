import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ChainsModule } from '../chains/chains.module';
import {
  ChainEntity,
  RescueEventEntity,
  RescueExecutionEntity,
  RescueWorkflowLogEntity,
} from '../persistence/entities';
import { PositionsModule } from '../positions/positions.module';
import { EvmRpcService } from './evm-rpc.service';
import { ReprieveAddressesService } from './reprieve-addresses.service';
import { RescueProjectionService } from './rescue-projection.service';
import { RescueWorkflowLogsService } from './rescue-workflow-logs.service';
import { RescueHistoryService } from './rescue-history.service';
import { RescuesController } from './rescues.controller';

@Module({
  imports: [
    ChainsModule,
    PositionsModule,
    TypeOrmModule.forFeature([
      ChainEntity,
      RescueEventEntity,
      RescueExecutionEntity,
      RescueWorkflowLogEntity,
    ]),
  ],
  controllers: [RescuesController],
  providers: [
    RescueHistoryService,
    RescueProjectionService,
    RescueWorkflowLogsService,
    EvmRpcService,
    ReprieveAddressesService,
  ],
  exports: [RescueHistoryService, RescueProjectionService, RescueWorkflowLogsService],
})
export class RescueHistoryModule {}
