import 'reflect-metadata';
import 'dotenv/config';
import { DataSource } from 'typeorm';
import { validateEnv } from '../../config/env.validation';
import { buildTypeOrmOptions } from './typeorm-options';

export const createDataSourceFromEnv = (
  env: NodeJS.ProcessEnv,
): DataSource => {
  const validatedEnv = validateEnv(env);
  return new DataSource(buildTypeOrmOptions(validatedEnv));
};

const appDataSource = createDataSourceFromEnv(process.env);

export default appDataSource;
