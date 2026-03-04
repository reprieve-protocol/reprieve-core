import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ApiModule } from './modules/api/api.module';
import { ChainsModule } from './modules/chains/chains.module';
import { DemoWalletsModule } from './modules/demo-wallets/demo-wallets.module';
import { PersistenceModule } from './modules/persistence/persistence.module';
import { PositionsModule } from './modules/positions/positions.module';
import { RelayModule } from './modules/relay/relay.module';
import { RescueHistoryModule } from './modules/rescue-history/rescue-history.module';
import { validateEnv } from './config/env.validation';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      validate: validateEnv,
    }),
    PersistenceModule.register(),
    ChainsModule,
    DemoWalletsModule,
    PositionsModule,
    RelayModule,
    RescueHistoryModule,
    ApiModule,
  ],
})
export class AppModule {}
