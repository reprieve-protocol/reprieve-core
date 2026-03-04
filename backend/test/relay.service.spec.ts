import { ConfigService } from '@nestjs/config';
import { RelayJobEntity } from '../src/modules/persistence/entities';
import { RelayService } from '../src/modules/relay/relay.service';

describe('RelayService', () => {
  const configService = {
    get: jest.fn((key: string, fallback?: string) => {
      if (key === 'RELAY_POLL_INTERVAL_MS') return '1000';
      if (key === 'RELAY_MAX_ATTEMPTS') return '3';
      if (key === 'RELAY_BACKOFF_BASE_MS') return '1000';
      if (key === 'RELAY_BACKOFF_MAX_MS') return '10000';
      if (key === 'RELAY_COMMAND_TIMEOUT_MS') return '5000';
      if (key === 'RELAY_SCAN_LIMIT') return '250';
      if (key === 'RELAY_BATCH_SIZE') return '5';
      return fallback;
    }),
  } as unknown as ConfigService;

  const chainRegistryService = {
    getAll: jest.fn(() => [
      {
        key: 'ethereum-sepolia',
        chainId: 11155111,
        ccipSelector: '16015286601757825753',
      },
      {
        key: 'base-sepolia',
        chainId: 84532,
        ccipSelector: '10344971235874465080',
      },
    ]),
  };

  const relayJobRepository = {
    query: jest.fn(),
    findOne: jest.fn(),
    save: jest.fn(),
    update: jest.fn(),
    createQueryBuilder: jest.fn(),
  };

  const rescueEventRepository = {
    query: jest.fn(),
  };

  const rescueExecutionRepository = {
    findOne: jest.fn(),
  };

  const makeService = (): RelayService =>
    new RelayService(
      configService,
      chainRegistryService as never,
      relayJobRepository as never,
      rescueEventRepository as never,
      rescueExecutionRepository as never,
    );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('seeds pending relay jobs from unresolved CrossChainInitiated rows', async () => {
    const service = makeService();

    rescueEventRepository.query.mockResolvedValue([
      {
        message_id:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        exec_id: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        source_chain_id: 11155111,
        payload: {
          targetChain: '10344971235874465080',
        },
      },
    ]);
    relayJobRepository.findOne.mockResolvedValue(null);

    const result = await service.seedPendingJobsFromDb();

    expect(result.scanned).toBe(1);
    expect(result.upserted).toBe(1);
    expect(result.skipped).toBe(0);
    expect(relayJobRepository.save).toHaveBeenCalledWith(
      expect.objectContaining({
        messageId:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        execId: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        sourceChainId: 11155111,
        destinationChainId: 84532,
        status: 'pending',
      }),
    );
  });

  it('skips unresolved rows when destination chain cannot be resolved', async () => {
    const service = makeService();

    rescueEventRepository.query.mockResolvedValue([
      {
        message_id:
          '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        exec_id: null,
        source_chain_id: 11155111,
        payload: {},
      },
    ]);

    const result = await service.seedPendingJobsFromDb();

    expect(result.scanned).toBe(1);
    expect(result.upserted).toBe(0);
    expect(result.skipped).toBe(1);
    expect(relayJobRepository.save).not.toHaveBeenCalled();
  });

  it('processes one claimed relay job and marks success', async () => {
    const service = makeService();

    const job = new RelayJobEntity();
    job.id = 1;
    job.messageId = '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    job.sourceChainId = 11155111;
    job.destinationChainId = 84532;
    job.execId = null;
    job.status = 'running';
    job.attemptCount = 1;
    job.nextAttemptAt = null;
    job.lastError = null;
    job.lastStdout = null;
    job.lastStderr = null;
    job.createdAt = new Date();
    job.updatedAt = new Date();

    jest
      .spyOn(service, 'seedPendingJobsFromDb')
      .mockResolvedValue({ scanned: 0, upserted: 0, skipped: 0 });
    jest
      .spyOn(service as any, 'recoverStaleRunningJobs')
      .mockResolvedValue(0);
    jest
      .spyOn(service as any, 'claimNextRunnableJob')
      .mockResolvedValueOnce(job)
      .mockResolvedValueOnce(null);
    jest.spyOn(service as any, 'executeRelayCommand').mockResolvedValue({
      exitCode: 0,
      timedOut: false,
      stdout: 'ok',
      stderr: '',
    });
    const markJobSuccessSpy = jest
      .spyOn(service as any, 'markJobSuccess')
      .mockResolvedValue(undefined);

    const result = await service.runRelayWorkerOnce();

    expect(result.processed).toBe(1);
    expect(result.success).toBe(1);
    expect(result.failed).toBe(0);
    expect(result.dead).toBe(0);
    expect(markJobSuccessSpy).toHaveBeenCalledWith(job, 'ok', '');
  });
});
