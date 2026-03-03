import { DataSourceOptions } from 'typeorm';
import { AppEnv } from '../../config/env.validation';
import { PERSISTENCE_ENTITIES } from './entities';

const parseBool = (input: string): boolean =>
  ['1', 'true', 'yes', 'on'].includes(input.toLowerCase());

export interface TypeOrmOptionsOverrides {
  includeMigrations?: boolean;
}

export const buildTypeOrmOptions = (
  env: AppEnv,
  overrides?: TypeOrmOptionsOverrides,
): DataSourceOptions => {
  const includeMigrations = overrides?.includeMigrations ?? true;

  return {
    type: 'postgres',
    host: env.DB_HOST,
    port: Number(env.DB_PORT),
    username: env.DB_USER,
    password: env.DB_PASSWORD,
    database: env.DB_NAME,
    ssl: parseBool(env.DB_SSL) ? { rejectUnauthorized: false } : false,
    entities: PERSISTENCE_ENTITIES,
    migrations: includeMigrations
      ? ['src/modules/persistence/migrations/*.ts']
      : [],
    synchronize: false,
    migrationsRun: false,
    logging: false,
  };
};
