import { RescueProjectionService } from '../src/modules/rescue-history/rescue-projection.service';

const mkDate = (seconds: number): Date => new Date(seconds * 1000);

interface MockEvent {
  chainId: number;
  blockNumber: string;
  txHash: string;
  logIndex: number;
  eventName: string;
  execId: string;
  userAddress: string | null;
  messageId: string | null;
  payload: Record<string, unknown>;
  indexedAt: Date;
}

const event = (
  partial: Partial<MockEvent> & Pick<MockEvent, 'eventName' | 'execId'>,
): MockEvent => ({
  chainId: partial.chainId ?? 11155111,
  blockNumber: partial.blockNumber ?? '1',
  txHash:
    partial.txHash ??
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  logIndex: partial.logIndex ?? 0,
  eventName: partial.eventName,
  execId: partial.execId,
  userAddress: partial.userAddress ?? null,
  messageId: partial.messageId ?? null,
  payload: partial.payload ?? {},
  indexedAt: partial.indexedAt ?? mkDate(1),
});

describe('RescueProjectionService', () => {
  const chainRegistryService = {
    getByKey: jest.fn((key: string) => {
      if (key === 'ethereum-sepolia') {
        return {
          key,
          chainId: 11155111,
          ccipSelector: '16015286601757825753',
          rpcUrl: 'http://rpc-eth.example',
          startBlock: 0,
          envRpcKey: 'ETHEREUM_SEPOLIA_RPC_URL',
          envStartBlockKey: 'ETHEREUM_SEPOLIA_START_BLOCK',
        };
      }

      return {
        key,
        chainId: 84532,
        ccipSelector: '10344971235874465080',
        rpcUrl: 'http://rpc-base.example',
        startBlock: 0,
        envRpcKey: 'BASE_SEPOLIA_RPC_URL',
        envStartBlockKey: 'BASE_SEPOLIA_START_BLOCK',
      };
    }),
  };

  const rescueEventRepository = {
    find: jest.fn(),
    createQueryBuilder: jest.fn(),
  };

  const rescueExecutionRepository = {
    upsert: jest.fn(),
    findOne: jest.fn(),
    createQueryBuilder: jest.fn(),
  };

  const makeService = (): RescueProjectionService =>
    new RescueProjectionService(
      chainRegistryService as never,
      rescueEventRepository as never,
      rescueExecutionRepository as never,
    );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('projects same-chain success as completed', async () => {
    const service = makeService();
    const execId = '0x1111111111111111111111111111111111111111111111111111111111111111';

    rescueEventRepository.find.mockResolvedValue([
      event({
        eventName: 'RescueInitiated',
        execId,
        userAddress: '0x7fbbc4abd42f91a6e3861d33a67dec13558658b5',
        indexedAt: mkDate(10),
      }),
      event({
        eventName: 'RescueCompleted',
        execId,
        userAddress: '0x7fbbc4abd42f91a6e3861d33a67dec13558658b5',
        indexedAt: mkDate(20),
      }),
    ]);

    await service.rebuildProjection(execId);

    expect(rescueExecutionRepository.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        execId,
        status: 'completed',
        sourceChainId: 11155111,
      }),
      expect.any(Object),
    );
  });

  it('projects cross-chain dispatched as in_progress until destination finalization', async () => {
    const service = makeService();
    const execId = '0x2222222222222222222222222222222222222222222222222222222222222222';

    rescueEventRepository.find.mockResolvedValue([
      event({
        eventName: 'RescueInitiated',
        execId,
        userAddress: '0x7fbbc4abd42f91a6e3861d33a67dec13558658b5',
        indexedAt: mkDate(10),
      }),
      event({
        eventName: 'RescueCompleted',
        execId,
        userAddress: '0x7fbbc4abd42f91a6e3861d33a67dec13558658b5',
        indexedAt: mkDate(11),
      }),
      event({
        eventName: 'CrossChainInitiated',
        execId,
        messageId:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        payload: { targetChain: '10344971235874465080', feePaid: '10000000000000000' },
        indexedAt: mkDate(12),
      }),
    ]);

    await service.rebuildProjection(execId);

    expect(rescueExecutionRepository.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        execId,
        status: 'in_progress',
        ccipMessageId:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        destinationChainId: 84532,
      }),
      expect.any(Object),
    );
  });

  it('projects cross-chain completion and failure transitions correctly', async () => {
    const service = makeService();
    const execId = '0x3333333333333333333333333333333333333333333333333333333333333333';

    rescueEventRepository.find.mockResolvedValue([
      event({ eventName: 'RescueInitiated', execId, indexedAt: mkDate(10) }),
      event({
        eventName: 'CrossChainInitiated',
        execId,
        messageId: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        payload: { targetChain: '10344971235874465080' },
        indexedAt: mkDate(11),
      }),
      event({
        eventName: 'CrossChainCompleted',
        execId,
        messageId: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        chainId: 84532,
        indexedAt: mkDate(12),
      }),
    ]);

    await service.rebuildProjection(execId);

    expect(rescueExecutionRepository.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({
        execId,
        status: 'completed',
        destinationChainId: 84532,
      }),
      expect.any(Object),
    );

    rescueEventRepository.find.mockResolvedValue([
      event({ eventName: 'RescueInitiated', execId, indexedAt: mkDate(10) }),
      event({ eventName: 'CrossChainInitiated', execId, indexedAt: mkDate(11) }),
      event({
        eventName: 'CrossChainDestinationFailed',
        execId,
        indexedAt: mkDate(12),
      }),
    ]);

    await service.rebuildProjection(execId);

    expect(rescueExecutionRepository.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({
        execId,
        status: 'failed',
      }),
      expect.any(Object),
    );
  });

  it('returns deterministically ordered event timelines', async () => {
    const service = makeService();
    const execId = '0x4444444444444444444444444444444444444444444444444444444444444444';

    rescueEventRepository.find.mockResolvedValue([
      event({
        eventName: 'RescueCompleted',
        execId,
        indexedAt: mkDate(20),
        chainId: 11155111,
        blockNumber: '200',
        logIndex: 2,
      }),
      event({
        eventName: 'RescueInitiated',
        execId,
        indexedAt: mkDate(10),
        chainId: 11155111,
        blockNumber: '100',
        logIndex: 1,
      }),
      event({
        eventName: 'CrossChainCompleted',
        execId,
        indexedAt: mkDate(20),
        chainId: 84532,
        blockNumber: '150',
        logIndex: 1,
      }),
    ]);

    const timeline = await service.getRescueEvents(execId);

    expect(timeline.map((e) => e.eventName)).toEqual([
      'RescueInitiated',
      'CrossChainCompleted',
      'RescueCompleted',
    ]);
  });
});
