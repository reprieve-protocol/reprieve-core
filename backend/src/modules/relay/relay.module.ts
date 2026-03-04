import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ChainsModule } from '../chains/chains.module';
import {
  RelayJobEntity,
  RescueEventEntity,
  RescueExecutionEntity,
} from '../persistence/entities';
import { RelayController } from './relay.controller';
import { RelayService } from './relay.service';

@Module({
  imports: [
    ChainsModule,
    TypeOrmModule.forFeature([RelayJobEntity, RescueEventEntity, RescueExecutionEntity]),
  ],
  controllers: [RelayController],
  providers: [RelayService],
  exports: [RelayService],
})
export class RelayModule {}
