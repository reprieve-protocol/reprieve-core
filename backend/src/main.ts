import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { GlobalHttpExceptionFilter } from './common/filters/global-http-exception.filter';
import { RescueHistoryService } from './modules/rescue-history/rescue-history.service';

async function bootstrap(): Promise<void> {
  const logger = new Logger('Bootstrap');
  const app = await NestFactory.create(AppModule);

  app.enableCors({
    origin: true,
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: '*',
    credentials: false,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.useGlobalFilters(new GlobalHttpExceptionFilter());

  const swaggerEnabled = String(process.env.SWAGGER_ENABLED ?? 'true') !== 'false';
  const swaggerPath = String(process.env.SWAGGER_PATH ?? 'docs');
  if (swaggerEnabled) {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('Reprieve Backend API')
      .setDescription('Debug and integration APIs for positions, rescues, and relay history')
      .setVersion('0.1.0')
      .build();
    const swaggerDocument = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup(swaggerPath, app, swaggerDocument, {
      jsonDocumentUrl: `${swaggerPath}-json`,
      yamlDocumentUrl: `${swaggerPath}-yaml`,
    });
  }

  const port = Number(process.env.APP_PORT ?? 3001);
  await app.listen(port);

  const runIndexerInApi = String(process.env.INDEXER_RUN_IN_API ?? 'true') !== 'false';
  if (runIndexerInApi) {
    const rescueHistoryService = app.get(RescueHistoryService);
    logger.log('INDEXER_RUN_IN_API enabled; starting indexer loop in API process');
    void rescueHistoryService.runIndexerLoop().catch((error) => {
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Indexer loop crashed in API process: ${message}`);
    });
  } else {
    logger.log('INDEXER_RUN_IN_API disabled; API process will not run indexer loop');
  }
}

void bootstrap();
