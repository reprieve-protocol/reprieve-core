import { ConfigService } from '@nestjs/config';
import { PositionsService } from '../src/modules/positions/positions.service';

describe('PositionsService', () => {
  const chainRegistryService = {
    getByKey: jest.fn((key: string) => {
      if (key === 'ethereum-sepolia') {
        return {
          key,
          chainId: 11155111,
          rpcUrl: 'http://rpc-eth.example',
          ccipSelector: '16015286601757825753',
          envRpcKey: 'ETHEREUM_SEPOLIA_RPC_URL',
          envStartBlockKey: 'ETHEREUM_SEPOLIA_START_BLOCK',
          startBlock: 0,
        };
      }

      return {
        key,
        chainId: 84532,
        rpcUrl: 'http://rpc-base.example',
        ccipSelector: '10344971235874465080',
        envRpcKey: 'BASE_SEPOLIA_RPC_URL',
        envStartBlockKey: 'BASE_SEPOLIA_START_BLOCK',
        startBlock: 0,
      };
    }),
  };

  const adapterReaderService = {
    discoverPositions: jest.fn(),
  };

  const chainRepository = {
    count: jest.fn(),
    save: jest.fn(),
    find: jest.fn(),
  };

  const protocolAdapterRepository = {
    count: jest.fn(),
    upsert: jest.fn(),
    find: jest.fn(),
  };

  const positionSnapshotRepository = {
    upsert: jest.fn(),
    find: jest.fn(),
  };

  const configService = {
    get: jest.fn((_key: string, fallback?: string) => fallback),
  } as unknown as ConfigService;

  const makeService = (): PositionsService =>
    new PositionsService(
      chainRegistryService as never,
      adapterReaderService as never,
      configService,
      chainRepository as never,
      protocolAdapterRepository as never,
      positionSnapshotRepository as never,
    );

  beforeEach(() => {
    jest.clearAllMocks();
    chainRepository.count.mockResolvedValue(1);
    protocolAdapterRepository.count.mockResolvedValue(1);
    chainRepository.find.mockResolvedValue([
      {
        id: 1,
        key: 'ethereum-sepolia',
        chainId: 11155111,
        rpcUrl: 'http://rpc-eth.example',
        isEnabled: true,
      },
    ]);
    protocolAdapterRepository.find.mockResolvedValue([
      {
        chainId: 11155111,
        protocol: 'AAVE',
        adapterAddress: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        isEnabled: true,
      },
    ]);
  });

  it('syncs positions and returns success', async () => {
    adapterReaderService.discoverPositions.mockResolvedValue({
      positions: [
        {
          protocol: '0x1111111111111111111111111111111111111111',
          collateralAsset: '0x2222222222222222222222222222222222222222',
          debtAsset: '0x3333333333333333333333333333333333333333',
          collateralAmount: '1000',
          debtAmount: '500',
          healthFactor: '2000000000000000000',
          ltvBps: '7000',
          maxLtvBps: '7500',
          liquidationThresholdBps: '8000',
        },
      ],
    });

    const service = makeService();
    const result = await service.syncPositions(
      '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
    );

    expect(result.status).toBe('success');
    expect(result.errors).toHaveLength(0);
    expect(result.snapshotsUpserted).toBe(1);
    expect(positionSnapshotRepository.upsert).toHaveBeenCalledTimes(1);
  });

  it('returns failed when some adapters fail but continues syncing', async () => {
    protocolAdapterRepository.find.mockResolvedValue([
      {
        chainId: 11155111,
        protocol: 'AAVE',
        adapterAddress: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        isEnabled: true,
      },
      {
        chainId: 11155111,
        protocol: 'COMPOUND',
        adapterAddress: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        isEnabled: true,
      },
    ]);

    adapterReaderService.discoverPositions
      .mockResolvedValueOnce({
        positions: [
          {
            protocol: '0x1111111111111111111111111111111111111111',
            collateralAsset: '0x2222222222222222222222222222222222222222',
            debtAsset: '0x3333333333333333333333333333333333333333',
            collateralAmount: '1000',
            debtAmount: '500',
            healthFactor: '2000000000000000000',
            ltvBps: '7000',
            maxLtvBps: '7500',
            liquidationThresholdBps: '8000',
          },
        ],
      })
      .mockRejectedValueOnce(new Error('rpc timeout'));

    const service = makeService();
    const result = await service.syncPositions(
      '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
    );

    expect(result.status).toBe('failed');
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0].reason).toContain('rpc timeout');
    expect(result.snapshotsUpserted).toBe(1);
  });

  it('returns stored positions metadata from postgres', async () => {
    const service = makeService();

    positionSnapshotRepository.find.mockResolvedValue([
      {
        syncedAt: new Date(Date.now() - 60_000),
      },
    ]);

    const result = await service.getPositions(
      '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
    );
    expect(result.user).toBe('0x7fbbc4abd42f91a6e3861d33a67dec13558658b5');
    expect(typeof result.syncedAt).toBe('string');
  });
});
