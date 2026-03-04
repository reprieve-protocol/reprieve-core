import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../../app.module';
import { RescueHistoryService } from './rescue-history.service';

const envBool = (value: string | undefined, defaultValue: boolean): boolean => {
  if (!value) return defaultValue;
  const normalized = value.trim().toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  return defaultValue;
};

async function main(): Promise<void> {
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  try {
    const service = app.get(RescueHistoryService);
    const result = await service.resetIndexedRescueData({
      resetChainCursor: envBool(process.env.RESET_CHAIN_CURSOR, true),
      clearRelayJobs: envBool(process.env.CLEAR_RELAY_JOBS, false),
    });

    console.log(JSON.stringify(result, null, 2));
  } finally {
    await app.close();
  }
}

void main();
