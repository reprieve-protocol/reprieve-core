import { ConfigService } from '@nestjs/config';
import { DemoWalletsService } from '../src/modules/demo-wallets/demo-wallets.service';
import { DemoWalletEntity } from '../src/modules/persistence/entities';

describe('DemoWalletsService', () => {
  const configService = {
    get: jest.fn((key: string, fallback?: string) => {
      if (key === 'DEMO_WALLET_MASTER_SECRET') return 'demo-master-secret-0123456789';
      if (key === 'DEMO_WALLET_ENCRYPTION_KEY') {
        return '0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      }
      return fallback;
    }),
  } as unknown as ConfigService;

  const chainRegistryService = {
    getByKey: jest.fn(),
  };

  const artifactAddressLoaderService = {
    getConfigPath: jest.fn(),
  };

  const demoWalletRepository = {
    findOne: jest.fn(),
    save: jest.fn(),
  };

  const demoWalletFundingRunRepository = {
    save: jest.fn(),
    update: jest.fn(),
    findOne: jest.fn(),
  };

  const demoWalletBootstrapRunRepository = {
    save: jest.fn(),
    update: jest.fn(),
    findOne: jest.fn(),
  };

  const makeService = (): DemoWalletsService =>
    new DemoWalletsService(
      configService,
      chainRegistryService as never,
      artifactAddressLoaderService as never,
      demoWalletRepository as never,
      demoWalletFundingRunRepository as never,
      demoWalletBootstrapRunRepository as never,
    );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('creates deterministic demo wallet and returns existing mapping on repeated requests', async () => {
    const service = makeService();
    const realUserAddress = '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5';
    let stored: DemoWalletEntity | null = null;

    demoWalletRepository.findOne.mockImplementation(
      ({ where }: { where: { realUserAddress?: string } }) => {
        if (!where.realUserAddress) {
          return null;
        }
        return stored && stored.realUserAddress === where.realUserAddress ? stored : null;
      },
    );

    demoWalletRepository.save.mockImplementation(
      async (input: Partial<DemoWalletEntity>) => {
        stored = {
          id: 1,
          realUserAddress: String(input.realUserAddress),
          demoWalletAddress: String(input.demoWalletAddress),
          encryptedPrivateKey: String(input.encryptedPrivateKey),
          derivationVersion: String(input.derivationVersion ?? 'v1'),
          createdAt: new Date(),
          updatedAt: new Date(),
        };
        return stored;
      },
    );

    const first = await service.generateDemoWallet(realUserAddress);
    expect(first.created).toBe(true);
    expect(typeof first.demoWalletAddress).toBe('string');

    const second = await service.generateDemoWallet(realUserAddress);
    expect(second.created).toBe(false);
    expect(second.demoWalletAddress).toBe(first.demoWalletAddress);
  });
});
