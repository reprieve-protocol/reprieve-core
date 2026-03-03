import { ConfigService } from '@nestjs/config';
import { RescueHistoryService } from '../src/modules/rescue-history/rescue-history.service';
import { EVENT_TOPICS } from '../src/modules/rescue-history/event-topics';
import { RawRpcLog } from '../src/modules/rescue-history/types';

const uintWord = (value: bigint): string => value.toString(16).padStart(64, '0');
const addrTopic = (address: string): string =>
  `0x${'0'.repeat(24)}${address.replace(/^0x/, '').toLowerCase()}`;

describe('RescueHistoryService', () => {
  const upsertStore = new Map<string, unknown>();

  const configService = {
    get: jest.fn((key: string, fallback?: string) => {
      if (key === 'INDEXER_BLOCK_WINDOW') return '1000';
      if (key === 'INDEXER_CONFIRMATIONS') return '0';
      if (key === 'INDEXER_POLL_INTERVAL_MS') return '15000';
      return fallback;
    }),
  } as unknown as ConfigService;

  const chainRegistryService = {
    getByKey: jest.fn((key: string) => {
      if (key === 'ethereum-sepolia') {
        return {
          key,
          chainId: 11155111,
          rpcUrl: 'http://rpc-eth.example',
          startBlock: 0,
          ccipSelector: '16015286601757825753',
          envRpcKey: 'ETHEREUM_SEPOLIA_RPC_URL',
          envStartBlockKey: 'ETHEREUM_SEPOLIA_START_BLOCK',
        };
      }
      return {
        key,
        chainId: 84532,
        rpcUrl: 'http://rpc-base.example',
        startBlock: 0,
        ccipSelector: '10344971235874465080',
        envRpcKey: 'BASE_SEPOLIA_RPC_URL',
        envStartBlockKey: 'BASE_SEPOLIA_START_BLOCK',
      };
    }),
  };

  const evmRpcService = {
    getLatestBlockNumber: jest.fn(),
    getIndexedLogs: jest.fn(),
  };

  const reprieveAddressesService = {
    getIndexedContractAddresses: jest.fn(async () => [
      '0x1111111111111111111111111111111111111111',
      '0x2222222222222222222222222222222222222222',
    ]),
  };

  const positionsService = {
    syncPositions: jest.fn(),
  };

  const rescueProjectionService = {
    rebuildProjection: jest.fn(),
  };

  const chainRepository = {
    count: jest.fn(),
    save: jest.fn(),
    find: jest.fn(),
    update: jest.fn(),
  };

  const rescueEventRepository = {
    upsert: jest.fn(async (row: { chainId: number; txHash: string; logIndex: number }) => {
      const key = `${row.chainId}:${row.txHash}:${row.logIndex}`;
      upsertStore.set(key, row);
    }),
  };

  const makeService = (): RescueHistoryService =>
    new RescueHistoryService(
      configService,
      chainRegistryService as never,
      evmRpcService as never,
      reprieveAddressesService as never,
      positionsService as never,
      rescueProjectionService as never,
      chainRepository as never,
      rescueEventRepository as never,
    );

  beforeEach(() => {
    jest.clearAllMocks();
    upsertStore.clear();
  });

  it('triggers user sync when PositionUpdated event is indexed', async () => {
    const service = makeService();

    const user = '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5';
    const log: RawRpcLog = {
      address: '0x1111111111111111111111111111111111111111',
      blockNumber: '0x100',
      transactionHash: `0x${'c'.repeat(64)}`,
      logIndex: '0x2',
      topics: [EVENT_TOPICS.PositionUpdated, addrTopic(user)],
      data: `0x${uintWord(1n)}${uintWord(2n)}${uintWord(3n)}`,
    };

    const persistResult = await service.persistLogs(11155111, [log]);
    expect(persistResult.positionUpdatedUsers).toEqual([user.toLowerCase()]);
    expect(persistResult.execIds).toEqual([]);

    chainRepository.count.mockResolvedValue(1);
    chainRepository.find.mockResolvedValue([
      {
        id: 1,
        chainId: 11155111,
        key: 'ethereum-sepolia',
        rpcUrl: 'http://rpc-eth.example',
        isEnabled: true,
        indexerEnabled: true,
        indexerCursorBlock: '10',
      },
    ]);
    evmRpcService.getLatestBlockNumber.mockResolvedValue(11n);
    evmRpcService.getIndexedLogs.mockResolvedValue([log]);

    await service.runIndexerOnce();
    expect(positionsService.syncPositions).toHaveBeenCalledWith(user.toLowerCase());
  });

  it('is idempotent when persisting same logs twice', async () => {
    const service = makeService();

    const execId = `0x${'a'.repeat(64)}`;
    const user = '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5';

    const log: RawRpcLog = {
      address: '0x1111111111111111111111111111111111111111',
      blockNumber: '0x100',
      transactionHash: `0x${'b'.repeat(64)}`,
      logIndex: '0x1',
      topics: [EVENT_TOPICS.RescueInitiated, execId, addrTopic(user)],
      data: `0x${uintWord(1n)}${uintWord(999999n)}`,
    };

    await service.persistLogs(11155111, [log]);
    await service.persistLogs(11155111, [log]);

    expect(upsertStore.size).toBe(1);
    expect(rescueEventRepository.upsert).toHaveBeenCalledTimes(2);
  });

  it('indexes a chain range and advances cursor', async () => {
    const service = makeService();

    chainRepository.count.mockResolvedValue(1);
    chainRepository.find.mockResolvedValue([
      {
        id: 1,
        chainId: 11155111,
        key: 'ethereum-sepolia',
        rpcUrl: 'http://rpc-eth.example',
        isEnabled: true,
        indexerEnabled: true,
        indexerCursorBlock: '100',
      },
    ]);

    evmRpcService.getLatestBlockNumber.mockResolvedValue(150n);

    const execId = `0x${'e'.repeat(64)}`;
    const user = '0x1000000000000000000000000000000000000000';

    evmRpcService.getIndexedLogs.mockResolvedValue([
      {
        address: '0x1111111111111111111111111111111111111111',
        blockNumber: '0x65',
        transactionHash: `0x${'f'.repeat(64)}`,
        logIndex: '0x1',
        topics: [EVENT_TOPICS.RescueInitiated, execId, addrTopic(user)],
        data: `0x${uintWord(1n)}${uintWord(12345n)}`,
      },
    ]);

    const result = await service.runIndexerOnce();

    expect(result.totalChains).toBe(1);
    expect(result.totalLogsScanned).toBe(1);
    expect(result.totalLogsDecoded).toBe(1);
    expect(chainRepository.update).toHaveBeenCalledWith(
      1,
      expect.objectContaining({ indexerCursorBlock: '150' }),
    );
    expect(rescueProjectionService.rebuildProjection).toHaveBeenCalledWith(execId);
  });

  it('splits log queries when provider enforces max block range', async () => {
    const service = makeService();

    chainRepository.count.mockResolvedValue(1);
    chainRepository.find.mockResolvedValue([
      {
        id: 2,
        chainId: 84532,
        key: 'base-sepolia',
        rpcUrl: 'http://rpc-base.example',
        isEnabled: true,
        indexerEnabled: true,
        indexerCursorBlock: '0',
      },
    ]);

    evmRpcService.getLatestBlockNumber.mockResolvedValue(1000n);

    evmRpcService.getIndexedLogs.mockImplementation(
      async (
        _rpcUrl: string,
        _addresses: string[],
        fromBlock: bigint,
        toBlock: bigint,
      ) => {
        const range = toBlock - fromBlock + 1n;
        if (range > 500n) {
          throw new Error(
            'RPC eth_getLogs failed: Block range too large: maximum allowed is 500 blocks',
          );
        }
        return [];
      },
    );

    const result = await service.runIndexerOnce();

    expect(result.totalChains).toBe(1);
    expect(result.totalLogsScanned).toBe(0);
    expect(result.totalLogsDecoded).toBe(0);
    expect(result.chains[0]?.status).toBe('indexed');
    expect(evmRpcService.getIndexedLogs).toHaveBeenCalledTimes(3);
    expect(chainRepository.update).toHaveBeenCalledWith(
      2,
      expect.objectContaining({ indexerCursorBlock: '1000' }),
    );
  });
});
