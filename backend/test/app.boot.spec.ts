import { Test } from '@nestjs/testing';
import { ConfigModule } from '@nestjs/config';
import { ApiModule } from '../src/modules/api/api.module';
import { ChainsModule } from '../src/modules/chains/chains.module';
import { validateEnv } from '../src/config/env.validation';

describe('AppModule boot', () => {
  beforeAll(() => {
    process.env.DB_HOST = '127.0.0.1';
    process.env.DB_PORT = '5432';
    process.env.DB_USER = 'reprieve';
    process.env.DB_PASSWORD = 'reprieve';
    process.env.DB_NAME = 'reprieve_backend';
    process.env.ETHEREUM_SEPOLIA_RPC_URL = 'http://localhost:8545';
    process.env.BASE_SEPOLIA_RPC_URL = 'http://localhost:8546';
  });

  it('compiles root module', async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [
        ConfigModule.forRoot({
          isGlobal: true,
          validate: validateEnv,
        }),
        ChainsModule,
        ApiModule,
      ],
    }).compile();

    expect(moduleRef).toBeDefined();
  });
});
