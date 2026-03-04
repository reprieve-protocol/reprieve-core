import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SUPPORTED_CHAIN_KEYS, SupportedChainKey } from '../../config/chains.config';
import { ChainRegistryService } from '../chains/chain-registry.service';
import { ChainEntity, RescueEventEntity } from '../persistence/entities';
import { PositionsService } from '../positions/positions.service';
import { decodeIndexedEvent } from './event-decoder';
import { EvmRpcService } from './evm-rpc.service';
import { ReprieveAddressesService } from './reprieve-addresses.service';
import { RescueProjectionService } from './rescue-projection.service';
import { ChainIndexProgress, IndexerRunResult, RawRpcLog } from './types';

@Injectable()
export class RescueHistoryService {
  private readonly logger = new Logger(RescueHistoryService.name);
  private readonly blockWindow: bigint;
  private readonly confirmations: bigint;

  constructor(
    private readonly configService: ConfigService,
    private readonly chainRegistryService: ChainRegistryService,
    private readonly evmRpcService: EvmRpcService,
    private readonly reprieveAddressesService: ReprieveAddressesService,
    private readonly positionsService: PositionsService,
    private readonly rescueProjectionService: RescueProjectionService,
    @InjectRepository(ChainEntity)
    private readonly chainRepository: Repository<ChainEntity>,
    @InjectRepository(RescueEventEntity)
    private readonly rescueEventRepository: Repository<RescueEventEntity>,
  ) {
    this.blockWindow = BigInt(
      this.configService.get<string>('INDEXER_BLOCK_WINDOW', '1000'),
    );
    this.confirmations = BigInt(
      this.configService.get<string>('INDEXER_CONFIRMATIONS', '0'),
    );
  }

  async runIndexerOnce(): Promise<IndexerRunResult> {
    const startedAt = new Date();
    this.logger.log('Indexer run started');
    await this.ensureChainsSeeded();

    const chains = await this.chainRepository.find({
      where: {
        isEnabled: true,
        indexerEnabled: true,
      },
      order: {
        chainId: 'ASC',
      },
    });

    const chainResults: ChainIndexProgress[] = [];
    let totalLogsScanned = 0;
    let totalLogsDecoded = 0;

    for (const chain of chains) {
      const chainResult = await this.indexChain(chain);
      chainResults.push(chainResult);

      totalLogsScanned += chainResult.scannedLogs;
      totalLogsDecoded += chainResult.decodedLogs;
    }

    const result = {
      startedAt: startedAt.toISOString(),
      finishedAt: new Date().toISOString(),
      totalChains: chains.length,
      totalLogsScanned,
      totalLogsDecoded,
      chains: chainResults,
    };
    this.logger.log(
      `Indexer run finished: chains=${result.totalChains} scanned=${result.totalLogsScanned} decoded=${result.totalLogsDecoded}`,
    );
    return result;
  }

  async runIndexerLoop(): Promise<void> {
    const pollIntervalMs = Number(
      this.configService.get<string>('INDEXER_POLL_INTERVAL_MS', '15000'),
    );

    while (true) {
      const result = await this.runIndexerOnce();
      this.logger.log(
        `Indexer loop tick complete. Sleeping ${pollIntervalMs}ms. (${result.totalLogsDecoded} decoded logs)`,
      );
      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }
  }

  async resetIndexedRescueData(options?: {
    resetChainCursor?: boolean;
    clearRelayJobs?: boolean;
  }): Promise<{
    before: { rescueEvents: number; rescueExecutions: number; relayJobs: number };
    after: { rescueEvents: number; rescueExecutions: number; relayJobs: number };
    chainCursorsReset: boolean;
    relayJobsCleared: boolean;
  }> {
    const resetChainCursor = options?.resetChainCursor ?? true;
    const clearRelayJobs = options?.clearRelayJobs ?? false;

    const beforeCounts = await this.rescueEventRepository.query(
      `SELECT
        (SELECT COUNT(*)::int FROM rescue_events) AS rescue_events,
        (SELECT COUNT(*)::int FROM rescue_executions) AS rescue_executions,
        (SELECT COUNT(*)::int FROM relay_jobs) AS relay_jobs`,
    );
    const before = {
      rescueEvents: Number(beforeCounts?.[0]?.rescue_events ?? 0),
      rescueExecutions: Number(beforeCounts?.[0]?.rescue_executions ?? 0),
      relayJobs: Number(beforeCounts?.[0]?.relay_jobs ?? 0),
    };

    await this.rescueEventRepository.query('DELETE FROM rescue_events');
    await this.rescueEventRepository.query('DELETE FROM rescue_executions');
    if (clearRelayJobs) {
      await this.rescueEventRepository.query('DELETE FROM relay_jobs');
    }

    if (resetChainCursor) {
      await this.chainRepository
        .createQueryBuilder()
        .update(ChainEntity)
        .set({ indexerCursorBlock: null, updatedAt: () => 'NOW()' as never })
        .execute();
    }

    const afterCounts = await this.rescueEventRepository.query(
      `SELECT
        (SELECT COUNT(*)::int FROM rescue_events) AS rescue_events,
        (SELECT COUNT(*)::int FROM rescue_executions) AS rescue_executions,
        (SELECT COUNT(*)::int FROM relay_jobs) AS relay_jobs`,
    );
    const after = {
      rescueEvents: Number(afterCounts?.[0]?.rescue_events ?? 0),
      rescueExecutions: Number(afterCounts?.[0]?.rescue_executions ?? 0),
      relayJobs: Number(afterCounts?.[0]?.relay_jobs ?? 0),
    };

    return {
      before,
      after,
      chainCursorsReset: resetChainCursor,
      relayJobsCleared: clearRelayJobs,
    };
  }

  private async indexChain(chain: ChainEntity): Promise<ChainIndexProgress> {
    const chainKey = this.resolveChainKeyFromChainId(chain.chainId);

    try {
      const chainConfig = this.chainRegistryService.getByKey(chainKey);
      const addresses = await this.reprieveAddressesService.getIndexedContractAddresses(
        chain.chainId,
      );

      if (addresses.length === 0) {
        return {
          chainId: chain.chainId,
          chainKey,
          fromBlock: null,
          toBlock: null,
          scannedLogs: 0,
          decodedLogs: 0,
          status: 'idle',
        };
      }

      const latestBlock = await this.evmRpcService.getLatestBlockNumber(
        chainConfig.rpcUrl,
      );
      const safeLatestBlock =
        latestBlock > this.confirmations
          ? latestBlock - this.confirmations
          : 0n;

      const configuredStart = BigInt(chainConfig.startBlock);
      const cursor = chain.indexerCursorBlock
        ? BigInt(chain.indexerCursorBlock)
        : null;

      const fromBlock = cursor !== null ? cursor + 1n : configuredStart;

      if (fromBlock > safeLatestBlock) {
        return {
          chainId: chain.chainId,
          chainKey,
          fromBlock: fromBlock.toString(),
          toBlock: safeLatestBlock.toString(),
          scannedLogs: 0,
          decodedLogs: 0,
          status: 'idle',
        };
      }

      const toBlockCandidate = fromBlock + this.blockWindow - 1n;
      const toBlock =
        toBlockCandidate < safeLatestBlock ? toBlockCandidate : safeLatestBlock;

      this.logger.log(
        `Indexing chain ${chainKey} (${chain.chainId}) from block ${fromBlock} to ${toBlock} (latest: ${latestBlock}, safe: ${safeLatestBlock})`,
      );

      const logs = await this.fetchLogsAdaptive(
        chainConfig.rpcUrl,
        addresses,
        fromBlock,
        toBlock,
      );

      const persistResult = await this.persistLogs(chain.chainId, logs);
      await this.syncUsersFromPositionEvents(persistResult.positionUpdatedUsers);
      await this.projectExecutionsFromEvents(persistResult.execIds);

      await this.chainRepository.update(chain.id, {
        indexerCursorBlock: toBlock.toString(),
        updatedAt: new Date(),
      });

      return {
        chainId: chain.chainId,
        chainKey,
        fromBlock: fromBlock.toString(),
        toBlock: toBlock.toString(),
        scannedLogs: logs.length,
        decodedLogs: persistResult.decodedCount,
        status: 'indexed',
      };
    } catch (error) {
      return {
        chainId: chain.chainId,
        chainKey,
        fromBlock: null,
        toBlock: null,
        scannedLogs: 0,
        decodedLogs: 0,
        status: 'error',
        error: error instanceof Error ? error.message : 'unknown error',
      };
    }
  }

  async persistLogs(
    chainId: number,
    logs: RawRpcLog[],
  ): Promise<{ decodedCount: number; positionUpdatedUsers: string[]; execIds: string[] }> {
    let decodedCount = 0;
    const positionUpdatedUsers = new Set<string>();
    const execIds = new Set<string>();

    for (const log of logs) {
      const decoded = decodeIndexedEvent(log);
      if (!decoded) {
        continue;
      }

      const blockNumber = BigInt(log.blockNumber).toString();
      const logIndex = Number(BigInt(log.logIndex));

      const row: Partial<RescueEventEntity> = {
        chainId,
        blockNumber,
        txHash: log.transactionHash.toLowerCase(),
        logIndex,
        contractAddress: log.address.toLowerCase(),
        eventName: decoded.eventName,
        execId: decoded.execId,
        userAddress: decoded.userAddress,
        messageId: decoded.messageId,
        payload: decoded.payload as unknown as Record<string, unknown>,
        indexedAt: new Date(),
      };

      await this.rescueEventRepository.upsert(row as never, {
        conflictPaths: ['chainId', 'txHash', 'logIndex'],
        skipUpdateIfNoValuesChanged: false,
      });

      if (decoded.eventName === 'PositionUpdated' && decoded.userAddress) {
        positionUpdatedUsers.add(decoded.userAddress.toLowerCase());
      }
      if (decoded.execId) {
        execIds.add(decoded.execId.toLowerCase());
      }

      decodedCount += 1;
    }

    return {
      decodedCount,
      positionUpdatedUsers: Array.from(positionUpdatedUsers),
      execIds: Array.from(execIds),
    };
  }

  private async ensureChainsSeeded(): Promise<void> {
    const existing = await this.chainRepository.count();
    if (existing > 0) {
      return;
    }

    for (const key of SUPPORTED_CHAIN_KEYS) {
      const chainConfig = this.chainRegistryService.getByKey(key);

      await this.chainRepository.save({
        key,
        chainId: chainConfig.chainId,
        rpcUrl: chainConfig.rpcUrl,
        isEnabled: true,
        indexerEnabled: true,
        indexerCursorBlock: null,
      });
    }
  }

  private resolveChainKeyFromChainId(chainId: number): SupportedChainKey {
    const match = SUPPORTED_CHAIN_KEYS.find((key) => {
      const chain = this.chainRegistryService.getByKey(key);
      return chain.chainId === chainId;
    });

    if (!match) {
      throw new Error(`Unsupported chain id: ${chainId}`);
    }

    return match;
  }

  private async fetchLogsAdaptive(
    rpcUrl: string,
    addresses: string[],
    fromBlock: bigint,
    toBlock: bigint,
  ): Promise<RawRpcLog[]> {
    const logs: RawRpcLog[] = [];
    let currentFrom = fromBlock;
    let chunkSize = this.blockWindow > 0n ? this.blockWindow : 1n;

    while (currentFrom <= toBlock) {
      const currentToCandidate = currentFrom + chunkSize - 1n;
      const currentTo =
        currentToCandidate < toBlock ? currentToCandidate : toBlock;

      try {
        const chunkLogs = await this.evmRpcService.getIndexedLogs(
          rpcUrl,
          addresses,
          currentFrom,
          currentTo,
        );
        logs.push(...chunkLogs);
        currentFrom = currentTo + 1n;
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : 'unknown error';
        const rpcMaxBlocks = this.parseRpcMaxBlocks(errorMessage);

        if (rpcMaxBlocks !== null && rpcMaxBlocks > 0n && rpcMaxBlocks < chunkSize) {
          chunkSize = rpcMaxBlocks;
          continue;
        }

        if (chunkSize > 1n) {
          chunkSize = chunkSize / 2n;
          if (chunkSize < 1n) {
            chunkSize = 1n;
          }
          continue;
        }

        throw error;
      }
    }

    return logs;
  }

  private parseRpcMaxBlocks(errorMessage: string): bigint | null {
    const match = errorMessage.match(/maximum allowed is\s+(\d+)\s+blocks/i);
    if (!match || !match[1]) {
      return null;
    }

    return BigInt(match[1]);
  }

  private async syncUsersFromPositionEvents(userAddresses: string[]): Promise<void> {
    if (userAddresses.length > 0) {
      this.logger.log(
        `PositionUpdated users detected: ${userAddresses.length}. Triggering position sync.`,
      );
    }
    for (const userAddress of userAddresses) {
      try {
        const syncResult = await this.positionsService.syncPositions(userAddress);
        this.logger.log(
          `Position sync for ${userAddress}: status=${syncResult.status} upserts=${syncResult.snapshotsUpserted} errors=${syncResult.errors.length}`,
        );
      } catch (error) {
        this.logger.warn(
          `Position sync failed for ${userAddress}: ${
            error instanceof Error ? error.message : 'unknown error'
          }`,
        );
      }
    }
  }

  private async projectExecutionsFromEvents(execIds: string[]): Promise<void> {
    for (const execId of execIds) {
      try {
        await this.rescueProjectionService.rebuildProjection(execId);
      } catch {
        // Projection failure should not block raw event indexing.
      }
    }
  }
}
