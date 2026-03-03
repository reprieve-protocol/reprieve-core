import { DynamicModule, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { validateEnv } from '../../config/env.validation';
import { buildTypeOrmOptions } from './typeorm-options';

const parseBool = (input: string | undefined): boolean =>
  typeof input === 'string' && ['1', 'true', 'yes', 'on'].includes(input.toLowerCase());

@Module({})
export class PersistenceModule {
  static register(): DynamicModule {
    const dbDisabled = parseBool(process.env.DB_DISABLE);

    if (dbDisabled) {
      return {
        module: PersistenceModule,
      };
    }

    return {
      module: PersistenceModule,
      imports: [
        TypeOrmModule.forRootAsync({
          inject: [ConfigService],
          useFactory: (configService: ConfigService) => {
            const env = validateEnv({
              NODE_ENV: configService.get<string>('NODE_ENV'),
              APP_PORT: configService.get<string>('APP_PORT'),
              DB_HOST: configService.get<string>('DB_HOST'),
              DB_PORT: configService.get<string>('DB_PORT'),
              DB_USER: configService.get<string>('DB_USER'),
              DB_PASSWORD: configService.get<string>('DB_PASSWORD'),
              DB_NAME: configService.get<string>('DB_NAME'),
              DB_SSL: configService.get<string>('DB_SSL'),
              DB_DISABLE: configService.get<string>('DB_DISABLE'),
              ETHEREUM_SEPOLIA_RPC_URL: configService.get<string>('ETHEREUM_SEPOLIA_RPC_URL'),
              BASE_SEPOLIA_RPC_URL: configService.get<string>('BASE_SEPOLIA_RPC_URL'),
              CONTRACTS_CONFIG_DIR: configService.get<string>('CONTRACTS_CONFIG_DIR'),
              ETHEREUM_SEPOLIA_START_BLOCK: configService.get<string>('ETHEREUM_SEPOLIA_START_BLOCK'),
              BASE_SEPOLIA_START_BLOCK: configService.get<string>('BASE_SEPOLIA_START_BLOCK'),
              INDEXER_BLOCK_WINDOW: configService.get<string>('INDEXER_BLOCK_WINDOW'),
              INDEXER_CONFIRMATIONS: configService.get<string>('INDEXER_CONFIRMATIONS'),
              INDEXER_POLL_INTERVAL_MS: configService.get<string>('INDEXER_POLL_INTERVAL_MS'),
              PROJECTION_REBUILD_BATCH_SIZE: configService.get<string>(
                'PROJECTION_REBUILD_BATCH_SIZE',
              ),
            });

            return buildTypeOrmOptions(env, { includeMigrations: false });
          },
        }),
      ],
      exports: [TypeOrmModule],
    };
  }
}
