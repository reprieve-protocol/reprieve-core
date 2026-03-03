import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../../app.module';
import { PositionsService } from './positions.service';

async function main(): Promise<void> {
  const userAddress = process.argv[2];
  if (!userAddress) {
    throw new Error('Usage: npm run backend:sync -- <userAddress>');
  }

  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  try {
    const service = app.get(PositionsService);
    const result = await service.syncPositions(userAddress);
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await app.close();
  }
}

void main();
