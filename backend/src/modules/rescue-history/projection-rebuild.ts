import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../../app.module';
import { RescueProjectionService } from './rescue-projection.service';

async function main(): Promise<void> {
  const execIdArg = process.argv[2];

  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });

  try {
    const service = app.get(RescueProjectionService);
    const result = await service.rebuildProjection(execIdArg);
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await app.close();
  }
}

void main();
