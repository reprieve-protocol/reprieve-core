import {
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  Contract,
  JsonRpcProvider,
  ZeroAddress,
  Wallet,
  getAddress,
  isAddress,
  isHexString,
} from 'ethers';
import { Repository } from 'typeorm';
import { ChainRegistryService } from '../chains/chain-registry.service';
import { SupportedChainKey } from '../../config/chains.config';
import {
  RelayJobEntity,
  RescueEventEntity,
  RescueExecutionEntity,
} from '../persistence/entities';
import { ListRelayJobsQueryDto } from './relay.dto';

interface UnresolvedCrossChainRow {
  message_id: string;
  exec_id: string | null;
  source_chain_id: number;
  payload: Record<string, unknown> | string | null;
}

interface RelayCommandResult {
  exitCode: number | null;
  timedOut: boolean;
  stdout: string;
  stderr: string;
}

interface ReprieveStackConfig {
  chainId?: number;
  wiring?: {
    ccipRouter?: string;
  };
}

interface StoredTokenAmount {
  token: string;
  amount: bigint;
}

interface StoredMessage {
  sourceChainSelector: bigint;
  destinationChainSelector: bigint;
  sender: string;
  receiver: string;
  data: string;
  tokenAmounts: StoredTokenAmount[];
  extraArgs: string;
  feeToken: string;
  timestamp: bigint;
}

const MOCK_ROUTER_ABI = [
  'function getMessage(bytes32 messageId) view returns ((uint64 sourceChainSelector,uint64 destinationChainSelector,address sender,bytes receiver,bytes data,(address token,uint256 amount)[] tokenAmounts,bytes extraArgs,address feeToken,uint256 timestamp))',
  'function tokenMappings(uint64 destinationChainSelector,address sourceToken) view returns (address)',
  'function deliverExternalMessage(bytes32 messageId,uint64 sourceChainSelector,address sourceSender,address receiver,bytes data,address destinationToken,uint256 destinationAmount) external',
] as const;

@Injectable()
export class RelayService implements OnModuleInit {
  private readonly logger = new Logger(RelayService.name);
  private readonly selectorToChainId: Map<string, number>;
  private readonly chainIdToKey: Map<number, SupportedChainKey>;
  private readonly pollIntervalMs: number;
  private readonly maxAttempts: number;
  private readonly backoffBaseMs: number;
  private readonly backoffMaxMs: number;
  private readonly commandTimeoutMs: number;
  private readonly scanLimit: number;
  private readonly batchSize: number;
  private readonly runningStaleMs: number;
  private readonly routerAddressByChainId = new Map<number, string>();

  constructor(
    private readonly configService: ConfigService,
    private readonly chainRegistryService: ChainRegistryService,
    @InjectRepository(RelayJobEntity)
    private readonly relayJobRepository: Repository<RelayJobEntity>,
    @InjectRepository(RescueEventEntity)
    private readonly rescueEventRepository: Repository<RescueEventEntity>,
    @InjectRepository(RescueExecutionEntity)
    private readonly rescueExecutionRepository: Repository<RescueExecutionEntity>,
  ) {
    const chains = this.chainRegistryService.getAll();
    this.selectorToChainId = new Map<string, number>();
    this.chainIdToKey = new Map<number, SupportedChainKey>();
    for (const chain of chains) {
      this.selectorToChainId.set(chain.ccipSelector, chain.chainId);
      this.chainIdToKey.set(chain.chainId, chain.key);
    }

    this.pollIntervalMs = Number(
      this.configService.get<string>('RELAY_POLL_INTERVAL_MS', '15000'),
    );
    this.maxAttempts = Number(
      this.configService.get<string>('RELAY_MAX_ATTEMPTS', '5'),
    );
    this.backoffBaseMs = Number(
      this.configService.get<string>('RELAY_BACKOFF_BASE_MS', '15000'),
    );
    this.backoffMaxMs = Number(
      this.configService.get<string>('RELAY_BACKOFF_MAX_MS', '300000'),
    );
    this.commandTimeoutMs = Number(
      this.configService.get<string>('RELAY_COMMAND_TIMEOUT_MS', '240000'),
    );
    this.scanLimit = Number(
      this.configService.get<string>('RELAY_SCAN_LIMIT', '250'),
    );
    this.batchSize = Number(
      this.configService.get<string>('RELAY_BATCH_SIZE', '5'),
    );
    this.runningStaleMs = Number(
      this.configService.get<string>('RELAY_RUNNING_STALE_MS', '300000'),
    );
  }

  onModuleInit() {
    this.runRelayWorkerLoop().catch();
  }

  async runRelayWorkerLoop(): Promise<void> {
    while (true) {
      const run = await this.runRelayWorkerOnce();
      this.logger.log(
        `Relay loop tick: recovered=${run.recovered} scanned=${run.seed.scanned} seeded=${run.seed.upserted} processed=${run.processed} success=${run.success} failed=${run.failed} dead=${run.dead}`,
      );
      await new Promise((resolve) => setTimeout(resolve, this.pollIntervalMs));
    }
  }

  async runRelayWorkerOnce(): Promise<{
    seed: { scanned: number; upserted: number; skipped: number };
    recovered: number;
    processed: number;
    success: number;
    failed: number;
    dead: number;
  }> {
    this.logger.log('Relay worker tick started');
    const recovered = await this.recoverStaleRunningJobs();
    this.logger.log(`Step 1: recovered stale running jobs = ${recovered}`);

    const seed = await this.seedPendingJobsFromDb();
    this.logger.log(
      `Step 2: seeded relay jobs from unresolved events: scanned=${seed.scanned} upserted=${seed.upserted} skipped=${seed.skipped}`,
    );

    let processed = 0;
    let success = 0;
    let failed = 0;
    let dead = 0;

    for (let i = 0; i < this.batchSize; i += 1) {
      this.logger.log(
        `Step 3.${i + 1}: attempting to claim runnable relay job`,
      );
      const job = await this.claimNextRunnableJob();
      if (!job) {
        this.logger.log(
          `Step 3.${i + 1}: no runnable relay job found, stopping batch`,
        );
        break;
      }

      this.logger.log(
        `Step 3.${i + 1}: claimed job id=${job.id} messageId=${job.messageId} attempt=${job.attemptCount} sourceChainId=${job.sourceChainId} destChainId=${job.destinationChainId}`,
      );
      processed += 1;

      const sourceChainKey = this.chainIdToKey.get(job.sourceChainId);
      const destinationChainKey = this.chainIdToKey.get(job.destinationChainId);
      if (!sourceChainKey || !destinationChainKey) {
        await this.markJobDead(
          job,
          `Unsupported chain mapping source=${job.sourceChainId} destination=${job.destinationChainId}`,
          '',
          '',
        );
        this.logger.warn(
          `Step 4.${i + 1}: dead-lettered job ${job.messageId} due to unsupported chain mapping`,
        );
        dead += 1;
        continue;
      }

      this.logger.log(
        `Step 4.${i + 1}: executing relay messageId=${job.messageId} ${sourceChainKey} -> ${destinationChainKey}`,
      );
      const commandResult = await this.executeRelayCommand(
        sourceChainKey,
        destinationChainKey,
        job.messageId,
      );
      this.logger.log(
        `Step 5.${i + 1}: relay execution completed messageId=${job.messageId} exitCode=${String(commandResult.exitCode)} timedOut=${commandResult.timedOut}`,
      );

      if (commandResult.exitCode === 0 && !commandResult.timedOut) {
        await this.markJobSuccess(
          job,
          commandResult.stdout,
          commandResult.stderr,
        );
        this.logger.log(
          `Step 6.${i + 1}: marked SUCCESS for messageId=${job.messageId}`,
        );
        success += 1;
        continue;
      }

      const errorSummary = commandResult.timedOut
        ? `Relay command timed out after ${this.commandTimeoutMs}ms`
        : `Relay command failed with exit code ${String(commandResult.exitCode ?? 'unknown')}`;

      const isDead = await this.markJobFailure(
        job,
        errorSummary,
        commandResult.stdout,
        commandResult.stderr,
      );
      if (isDead) {
        this.logger.warn(
          `Step 6.${i + 1}: marked DEAD for messageId=${job.messageId} reason=${errorSummary}`,
        );
        dead += 1;
      } else {
        this.logger.warn(
          `Step 6.${i + 1}: marked RETRY for messageId=${job.messageId} reason=${errorSummary}`,
        );
        failed += 1;
      }
    }

    this.logger.log(
      `Relay worker tick finished: recovered=${recovered} scanned=${seed.scanned} seeded=${seed.upserted} processed=${processed} success=${success} failed=${failed} dead=${dead}`,
    );
    return { seed, recovered, processed, success, failed, dead };
  }

  async seedPendingJobsFromDb(): Promise<{
    scanned: number;
    upserted: number;
    skipped: number;
  }> {
    const unresolved = (await this.rescueEventRepository.query(
      `
      SELECT DISTINCT ON (ci.message_id)
        LOWER(ci.message_id) AS message_id,
        LOWER(ci.exec_id) AS exec_id,
        ci.chain_id AS source_chain_id,
        ci.payload AS payload
      FROM rescue_events ci
      WHERE ci.event_name = 'CrossChainInitiated'
        AND ci.message_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM rescue_events terminal
          WHERE LOWER(terminal.message_id) = LOWER(ci.message_id)
            AND terminal.event_name IN (
              'CrossChainCompleted',
              'CrossChainDestinationFailed',
              'MessageFailed'
            )
        )
      ORDER BY ci.message_id, ci.id DESC
      LIMIT $1
      `,
      [this.scanLimit],
    )) as UnresolvedCrossChainRow[];

    let upserted = 0;
    let skipped = 0;

    this.logger.log(
      `Seeding relay jobs: unresolved CrossChainInitiated rows=${unresolved.length}`,
    );

    for (const row of unresolved) {
      const messageId = row.message_id.toLowerCase();
      const execId = row.exec_id ? row.exec_id.toLowerCase() : null;
      const sourceChainId = Number(row.source_chain_id);

      const destinationChainId = await this.resolveDestinationChainId(
        row.payload,
        execId,
      );
      if (!destinationChainId) {
        skipped += 1;
        this.logger.warn(
          `Skipping unresolved message without destination mapping: messageId=${messageId} execId=${execId ?? 'n/a'}`,
        );
        continue;
      }

      const existing = await this.relayJobRepository.findOne({
        where: { messageId },
      });

      if (!existing) {
        await this.relayJobRepository.save({
          messageId,
          execId,
          sourceChainId,
          destinationChainId,
          status: 'pending',
          attemptCount: 0,
          nextAttemptAt: null,
          lastError: null,
          lastStdout: null,
          lastStderr: null,
          updatedAt: new Date(),
        });
        upserted += 1;
        this.logger.log(
          `Seeded new relay job: messageId=${messageId} execId=${execId ?? 'n/a'} sourceChainId=${sourceChainId} destinationChainId=${destinationChainId}`,
        );
        continue;
      }

      const needsMetadataUpdate =
        existing.sourceChainId !== sourceChainId ||
        existing.destinationChainId !== destinationChainId ||
        (existing.execId ?? null) !== execId;

      if (needsMetadataUpdate) {
        await this.relayJobRepository.update(existing.id, {
          sourceChainId,
          destinationChainId,
          execId,
          updatedAt: new Date(),
        });
        this.logger.log(
          `Updated relay job metadata: id=${existing.id} messageId=${messageId} sourceChainId=${sourceChainId} destinationChainId=${destinationChainId}`,
        );
      }
    }

    return {
      scanned: unresolved.length,
      upserted,
      skipped,
    };
  }

  async listRelayJobs(query: ListRelayJobsQueryDto): Promise<{
    page: number;
    limit: number;
    total: number;
    items: RelayJobEntity[];
  }> {
    const page = query.page ?? 1;
    const limit = query.limit ?? 20;
    const qb = this.relayJobRepository.createQueryBuilder('r');

    if (query.status) {
      qb.andWhere('r.status = :status', { status: query.status });
    }

    if (query.chainId) {
      qb.andWhere(
        '(r.source_chain_id = :chainId OR r.destination_chain_id = :chainId)',
        { chainId: query.chainId },
      );
    }

    qb.orderBy('r.updated_at', 'DESC');

    const [items, total] = await qb
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount();

    return {
      page,
      limit,
      total,
      items,
    };
  }

  async getRelayJob(messageId: string): Promise<RelayJobEntity> {
    const normalized = messageId.toLowerCase();
    const job = await this.relayJobRepository.findOne({
      where: { messageId: normalized },
    });

    if (!job) {
      throw new NotFoundException(
        `Relay job not found for message ${normalized}`,
      );
    }

    return job;
  }

  async retryRelayJob(messageId: string): Promise<RelayJobEntity> {
    const job = await this.getRelayJob(messageId);

    if (job.status === 'running') {
      throw new ServiceUnavailableException(
        `Relay job ${job.messageId} is currently running`,
      );
    }

    await this.relayJobRepository.update(job.id, {
      status: 'pending',
      nextAttemptAt: null,
      lastError: null,
      updatedAt: new Date(),
    });

    this.logger.log(
      `Manual retry queued for relay job messageId=${job.messageId}`,
    );

    return this.getRelayJob(job.messageId);
  }

  private async recoverStaleRunningJobs(): Promise<number> {
    const staleBefore = new Date(Date.now() - this.runningStaleMs);
    const result = await this.relayJobRepository
      .createQueryBuilder()
      .update(RelayJobEntity)
      .set({
        status: 'pending',
        nextAttemptAt: new Date(),
        lastError: `Recovered stale running job at ${new Date().toISOString()}`,
        updatedAt: new Date(),
      })
      .where('status = :status', { status: 'running' })
      .andWhere('updated_at < :staleBefore', { staleBefore })
      .execute();

    const recovered = Number(result.affected ?? 0);
    if (recovered > 0) {
      this.logger.warn(`Recovered ${recovered} stale running relay job(s)`);
    }
    return recovered;
  }

  private async claimNextRunnableJob(): Promise<RelayJobEntity | null> {
    return this.relayJobRepository.manager.transaction(async (manager) => {
      const jobRepository = manager.getRepository(RelayJobEntity);
      const now = new Date();
      const job = await jobRepository
        .createQueryBuilder('job')
        .setLock('pessimistic_write')
        .setOnLocked('skip_locked')
        .where('job.status = :status', { status: 'pending' })
        .andWhere('(job.nextAttemptAt IS NULL OR job.nextAttemptAt <= :now)', {
          now,
        })
        .orderBy('job.nextAttemptAt', 'ASC', 'NULLS FIRST')
        .addOrderBy('job.id', 'ASC')
        .getOne();

      if (!job) {
        return null;
      }

      job.status = 'running';
      job.attemptCount += 1;
      job.nextAttemptAt = null;
      job.updatedAt = now;
      await jobRepository.save(job);
      this.logger.log(
        `Claimed runnable relay job id=${job.id} messageId=${job.messageId} attempt=${job.attemptCount}`,
      );

      return job;
    });
  }

  private async markJobSuccess(
    job: RelayJobEntity,
    stdout: string,
    stderr: string,
  ): Promise<void> {
    await this.relayJobRepository.update(job.id, {
      status: 'success',
      nextAttemptAt: null,
      lastError: null,
      lastStdout: stdout,
      lastStderr: stderr,
      updatedAt: new Date(),
    });
  }

  private async markJobDead(
    job: RelayJobEntity,
    error: string,
    stdout: string,
    stderr: string,
  ): Promise<void> {
    await this.relayJobRepository.update(job.id, {
      status: 'dead',
      nextAttemptAt: null,
      lastError: error,
      lastStdout: stdout,
      lastStderr: stderr,
      updatedAt: new Date(),
    });
  }

  private async markJobFailure(
    job: RelayJobEntity,
    error: string,
    stdout: string,
    stderr: string,
  ): Promise<boolean> {
    const attempts = job.attemptCount;
    if (attempts >= this.maxAttempts) {
      await this.markJobDead(job, error, stdout, stderr);
      return true;
    }

    const backoffMs = Math.min(
      this.backoffMaxMs,
      this.backoffBaseMs * 2 ** Math.max(0, attempts - 1),
    );
    const nextAttemptAt = new Date(Date.now() + backoffMs);

    await this.relayJobRepository.update(job.id, {
      status: 'pending',
      nextAttemptAt,
      lastError: error,
      lastStdout: stdout,
      lastStderr: stderr,
      updatedAt: new Date(),
    });
    return false;
  }

  private async resolveDestinationChainId(
    payload: Record<string, unknown> | string | null,
    execId: string | null,
  ): Promise<number | null> {
    let payloadObject: Record<string, unknown> | null = null;
    if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
      payloadObject = payload;
    } else if (typeof payload === 'string' && payload.length > 0) {
      try {
        const parsed = JSON.parse(payload) as unknown;
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
          payloadObject = parsed as Record<string, unknown>;
        }
      } catch {
        payloadObject = null;
      }
    }

    const targetChain = payloadObject?.targetChain as
      | string
      | number
      | undefined;
    if (targetChain !== undefined && targetChain !== null) {
      const asSelector = String(targetChain);
      const mapped = this.selectorToChainId.get(asSelector);
      if (mapped) {
        return mapped;
      }
    }

    if (!execId) {
      return null;
    }

    const execution = await this.rescueExecutionRepository.findOne({
      where: { execId },
    });

    return execution?.destinationChainId ?? null;
  }

  private executeRelayCommand(
    sourceChainKey: SupportedChainKey,
    destinationChainKey: SupportedChainKey,
    messageId: string,
  ): Promise<RelayCommandResult> {
    this.logger.log(
      `Relay command start (native EVM): messageId=${messageId} ${sourceChainKey} -> ${destinationChainKey}`,
    );
    const timeoutResult = new Promise<RelayCommandResult>((resolve) => {
      setTimeout(() => {
        this.logger.warn(
          `Relay command timeout: messageId=${messageId} timeoutMs=${this.commandTimeoutMs}`,
        );
        resolve({
          exitCode: 1,
          timedOut: true,
          stdout: '',
          stderr: `Relay execution timed out after ${this.commandTimeoutMs}ms`,
        });
      }, this.commandTimeoutMs);
    });

    const relayResult = this.executeRelayViaEvm(
      sourceChainKey,
      destinationChainKey,
      messageId,
    ).catch((error: unknown) => ({
      exitCode: 1,
      timedOut: false,
      stdout: '',
      stderr: error instanceof Error ? error.message : String(error),
    }));

    return Promise.race([relayResult, timeoutResult]);
  }

  private async executeRelayViaEvm(
    sourceChainKey: SupportedChainKey,
    destinationChainKey: SupportedChainKey,
    messageId: string,
  ): Promise<RelayCommandResult> {
    if (!isHexString(messageId, 32)) {
      throw new Error(`Invalid message id: ${messageId}`);
    }
    this.logger.log(`EVM relay step: validating messageId=${messageId}`);

    const sourceChain = this.chainRegistryService.getByKey(sourceChainKey);
    const destinationChain =
      this.chainRegistryService.getByKey(destinationChainKey);
    this.logger.log(
      `EVM relay step: sourceChain=${sourceChain.key}(${sourceChain.chainId}) destinationChain=${destinationChain.key}(${destinationChain.chainId})`,
    );

    const sourceRouterAddress = this.resolveRouterAddress(sourceChain.chainId);
    const destinationRouterAddress = this.resolveRouterAddress(
      destinationChain.chainId,
    );
    const relayPrivateKey = this.resolveRelayPrivateKey(destinationChain.key);
    this.logger.log(
      `EVM relay step: resolved routers source=${sourceRouterAddress} destination=${destinationRouterAddress}`,
    );

    const sourceProvider = new JsonRpcProvider(sourceChain.rpcUrl);
    const destinationProvider = new JsonRpcProvider(destinationChain.rpcUrl);
    const destinationSigner = new Wallet(relayPrivateKey, destinationProvider);
    this.logger.log(
      `EVM relay step: destination signer=${destinationSigner.address}`,
    );

    const sourceRouter = new Contract(
      sourceRouterAddress,
      MOCK_ROUTER_ABI,
      sourceProvider,
    );
    const destinationRouter = new Contract(
      destinationRouterAddress,
      MOCK_ROUTER_ABI,
      destinationSigner,
    );

    const stored = (await sourceRouter.getMessage(messageId)) as StoredMessage;
    if (!stored || stored.timestamp === 0n) {
      throw new Error(`Source router message not found: ${messageId}`);
    }
    this.logger.log(
      `EVM relay step: loaded source message messageId=${messageId} sourceSelector=${stored.sourceChainSelector.toString()} destinationSelector=${stored.destinationChainSelector.toString()} tokenCount=${stored.tokenAmounts.length}`,
    );
    if (!stored.tokenAmounts || stored.tokenAmounts.length === 0) {
      throw new Error(
        `Source router message has no token amounts: ${messageId}`,
      );
    }

    const sourceToken = stored.tokenAmounts[0]?.token;
    const destinationAmount = stored.tokenAmounts[0]?.amount;
    if (!sourceToken || !destinationAmount || destinationAmount <= 0n) {
      throw new Error(`Invalid source token amount for message: ${messageId}`);
    }

    const destinationToken = (await sourceRouter.tokenMappings(
      stored.destinationChainSelector,
      sourceToken,
    )) as string;
    if (!isAddress(destinationToken) || destinationToken === ZeroAddress) {
      throw new Error(
        `Destination token mapping not configured for source token ${sourceToken}`,
      );
    }
    this.logger.log(
      `EVM relay step: resolved token mapping sourceToken=${sourceToken} destinationToken=${destinationToken} amount=${destinationAmount.toString()}`,
    );

    const destinationReceiver = this.decodeReceiverAddress(stored.receiver);
    this.logger.log(
      `EVM relay step: decoded destination receiver=${destinationReceiver}`,
    );

    const tx = await destinationRouter.deliverExternalMessage(
      messageId,
      stored.sourceChainSelector,
      stored.sender,
      destinationReceiver,
      stored.data,
      destinationToken,
      destinationAmount,
    );
    this.logger.log(
      `EVM relay step: submitted deliverExternalMessage tx=${tx.hash}`,
    );

    const receipt = await tx.wait();
    if (!receipt || receipt.status !== 1) {
      throw new Error(
        `Relay tx failed for message ${messageId}; tx=${tx.hash ?? 'unknown'}`,
      );
    }
    this.logger.log(
      `EVM relay step: tx confirmed messageId=${messageId} tx=${tx.hash} block=${String(receipt.blockNumber)}`,
    );

    const summary = [
      `relay tx hash: ${tx.hash}`,
      `source chain: ${sourceChainKey}`,
      `destination chain: ${destinationChainKey}`,
      `source router: ${sourceRouterAddress}`,
      `destination router: ${destinationRouterAddress}`,
      `receiver: ${destinationReceiver}`,
      `destination token: ${destinationToken}`,
      `amount: ${destinationAmount.toString()}`,
    ].join('\n');

    return {
      exitCode: 0,
      timedOut: false,
      stdout: summary,
      stderr: '',
    };
  }

  private resolveRouterAddress(chainId: number): string {
    const cached = this.routerAddressByChainId.get(chainId);
    if (cached) {
      this.logger.log(
        `Router resolution: using cached router for chainId=${chainId} address=${cached}`,
      );
      return cached;
    }

    const baseDir = this.configService.get<string>(
      'CONTRACTS_CONFIG_DIR',
      '../contracts/config',
    );
    const configPath = path.resolve(
      process.cwd(),
      baseDir,
      `reprieve-stack-${chainId}.json`,
    );

    if (!fs.existsSync(configPath)) {
      throw new Error(
        `Missing reprieve stack config for chain ${chainId}: ${configPath}`,
      );
    }

    const raw = fs.readFileSync(configPath, 'utf8');
    const parsed = JSON.parse(raw) as ReprieveStackConfig;
    const router = parsed.wiring?.ccipRouter;
    if (!router || !isAddress(router)) {
      throw new Error(
        `Invalid or missing wiring.ccipRouter in ${configPath} for chain ${chainId}`,
      );
    }

    const normalized = getAddress(router);
    this.routerAddressByChainId.set(chainId, normalized);
    this.logger.log(
      `Router resolution: loaded router from config chainId=${chainId} address=${normalized}`,
    );
    return normalized;
  }

  private resolveRelayPrivateKey(
    destinationChainKey: SupportedChainKey,
  ): string {
    const chainSpecificKey =
      destinationChainKey === 'ethereum-sepolia'
        ? this.configService.get<string>('ETHEREUM_SEPOLIA_PRIVATE_KEY')
        : this.configService.get<string>('BASE_SEPOLIA_PRIVATE_KEY');

    const raw =
      chainSpecificKey ??
      this.configService.get<string>('RELAY_SIGNER_PRIVATE_KEY') ??
      this.configService.get<string>('PRIVATE_KEY');

    if (!raw || raw.trim().length === 0) {
      throw new Error(
        `Missing relay signer key for ${destinationChainKey}. Set ${
          destinationChainKey === 'ethereum-sepolia'
            ? 'ETHEREUM_SEPOLIA_PRIVATE_KEY'
            : 'BASE_SEPOLIA_PRIVATE_KEY'
        }, RELAY_SIGNER_PRIVATE_KEY, or PRIVATE_KEY`,
      );
    }

    const normalized = raw.startsWith('0x') ? raw : `0x${raw}`;
    if (!isHexString(normalized, 32)) {
      throw new Error(
        `Invalid relay private key format for ${destinationChainKey}`,
      );
    }
    this.logger.log(
      `Signer resolution: using configured relay signer for ${destinationChainKey}`,
    );
    return normalized;
  }

  private decodeReceiverAddress(receiverBytes: string): string {
    if (!receiverBytes || !receiverBytes.startsWith('0x')) {
      throw new Error(`Invalid receiver bytes value: ${receiverBytes}`);
    }

    const hex = receiverBytes.slice(2);
    if (hex.length === 40) {
      this.logger.log('Receiver decode: interpreted 20-byte raw receiver');
      return getAddress(`0x${hex}`);
    }
    if (hex.length === 64) {
      this.logger.log(
        'Receiver decode: interpreted 32-byte ABI-encoded receiver',
      );
      return getAddress(`0x${hex.slice(24)}`);
    }

    throw new Error(
      `Unsupported receiver bytes length: ${receiverBytes.length}`,
    );
  }
}
