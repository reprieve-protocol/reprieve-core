import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ChainsModule } from '../chains/chains.module';
import {
  ChainEntity,
  PositionSnapshotEntity,
  ProtocolAdapterEntity,
} from '../persistence/entities';
import { AdapterReaderService } from './adapter-reader.service';
import { PositionsController } from './positions.controller';
import { PositionsService } from './positions.service';

@Module({
  imports: [
    ChainsModule,
    TypeOrmModule.forFeature([
      ChainEntity,
      ProtocolAdapterEntity,
      PositionSnapshotEntity,
    ]),
  ],
  controllers: [PositionsController],
  providers: [PositionsService, AdapterReaderService],
  exports: [PositionsService],
})
export class PositionsModule {}
