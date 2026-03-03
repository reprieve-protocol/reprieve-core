import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SUPPORTED_CHAIN_KEYS } from '../../config/chains.config';
import { ChainRegistryService } from '../chains/chain-registry.service';
import { RescueEventEntity, RescueExecutionEntity } from '../persistence/entities';
import { ListRescuesQueryDto } from './rescue-history.dto';

interface ProjectionState {
  execId: string;
  userAddress: string | null;
  sourceChainId: number | null;
  destinationChainId: number | null;
  mode: string | null;
  ccipMessageId: string | null;
  sourceTxHash: string | null;
  lastEventAt: Date | null;
  hasInitiated: boolean;
  hasRescueCompleted: boolean;
  hasRescueFailed: boolean;
  hasCrossChainInitiated: boolean;
  hasCrossChainCompleted: boolean;
  hasCrossChainFailed: boolean;
}

interface SortedEvent {
  event: RescueEventEntity;
  sortTuple: [number, number, bigint, number, number];
}

@Injectable()
export class RescueProjectionService {
  constructor(
    private readonly chainRegistryService: ChainRegistryService,
    @InjectRepository(RescueEventEntity)
    private readonly rescueEventRepository: Repository<RescueEventEntity>,
    @InjectRepository(RescueExecutionEntity)
    private readonly rescueExecutionRepository: Repository<RescueExecutionEntity>,
  ) {}

  async rebuildProjection(execId?: string): Promise<{
    updated: number;
    execIds: string[];
  }> {
    const execIds = execId
      ? [execId.toLowerCase()]
      : await this.listDistinctExecIds();

    let updated = 0;
    for (const id of execIds) {
      const changed = await this.projectExec(id);
      if (changed) {
        updated += 1;
      }
    }

    return {
      updated,
      execIds,
    };
  }

  async listRescues(query: ListRescuesQueryDto): Promise<{
    page: number;
    limit: number;
    total: number;
    items: RescueExecutionEntity[];
  }> {
    const page = query.page ?? 1;
    const limit = query.limit ?? 20;

    const qb = this.rescueExecutionRepository.createQueryBuilder('r');

    if (query.user) {
      qb.andWhere('r.user_address = :user', { user: query.user.toLowerCase() });
    }

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

    return { page, limit, total, items };
  }

  async getRescue(execId: string): Promise<RescueExecutionEntity> {
    const normalizedExecId = execId.toLowerCase();

    await this.projectExec(normalizedExecId);

    const row = await this.rescueExecutionRepository.findOne({
      where: { execId: normalizedExecId },
    });

    if (!row) {
      throw new NotFoundException(`Rescue execution not found: ${normalizedExecId}`);
    }

    return row;
  }

  async getRescueEvents(execId: string): Promise<RescueEventEntity[]> {
    const normalizedExecId = execId.toLowerCase();

    const events = await this.rescueEventRepository.find({
      where: { execId: normalizedExecId },
    });

    if (events.length === 0) {
      throw new NotFoundException(`Rescue events not found: ${normalizedExecId}`);
    }

    return this.sortEvents(events);
  }

  private async listDistinctExecIds(): Promise<string[]> {
    const rows = await this.rescueEventRepository
      .createQueryBuilder('e')
      .select('DISTINCT e.exec_id', 'execId')
      .where('e.exec_id IS NOT NULL')
      .getRawMany<{ execId: string | null }>();

    return rows
      .map((row) => row.execId)
      .filter((value): value is string => typeof value === 'string' && value.length > 0)
      .map((value) => value.toLowerCase());
  }

  private async projectExec(execId: string): Promise<boolean> {
    const events = await this.rescueEventRepository.find({ where: { execId } });
    if (events.length === 0) {
      return false;
    }

    const sorted = this.sortEvents(events);
    const projection = this.reduceProjection(execId, sorted);

    const status = this.computeStatus(projection);

    await this.rescueExecutionRepository.upsert(
      {
        execId,
        userAddress: projection.userAddress ?? '0x0000000000000000000000000000000000000000',
        sourceChainId: projection.sourceChainId,
        mode: projection.mode,
        status,
        ccipMessageId: projection.ccipMessageId,
        sourceTxHash: projection.sourceTxHash,
        destinationChainId: projection.destinationChainId,
        lastEventAt: projection.lastEventAt,
        updatedAt: new Date(),
      },
      {
        conflictPaths: ['execId'],
        skipUpdateIfNoValuesChanged: false,
      },
    );

    return true;
  }

  private reduceProjection(execId: string, events: RescueEventEntity[]): ProjectionState {
    const initial: ProjectionState = {
      execId,
      userAddress: null,
      sourceChainId: null,
      destinationChainId: null,
      mode: null,
      ccipMessageId: null,
      sourceTxHash: null,
      lastEventAt: null,
      hasInitiated: false,
      hasRescueCompleted: false,
      hasRescueFailed: false,
      hasCrossChainInitiated: false,
      hasCrossChainCompleted: false,
      hasCrossChainFailed: false,
    };

    const selectorToChainId = new Map<string, number>();
    for (const key of SUPPORTED_CHAIN_KEYS) {
      const chain = this.chainRegistryService.getByKey(key);
      selectorToChainId.set(chain.ccipSelector, chain.chainId);
    }

    for (const event of events) {
      if (!initial.sourceChainId) {
        initial.sourceChainId = event.chainId;
      }

      if (!initial.sourceTxHash) {
        initial.sourceTxHash = event.txHash;
      }

      if (!initial.userAddress && event.userAddress) {
        initial.userAddress = event.userAddress.toLowerCase();
      }

      if (event.indexedAt) {
        initial.lastEventAt = event.indexedAt;
      }

      if (event.messageId && !initial.ccipMessageId) {
        initial.ccipMessageId = event.messageId.toLowerCase();
      }

      if (event.eventName === 'RescueInitiated') {
        initial.hasInitiated = true;
      }

      if (event.eventName === 'RescueCompleted') {
        initial.hasRescueCompleted = true;
      }

      if (event.eventName === 'RescueFailed') {
        initial.hasRescueFailed = true;
      }

      if (event.eventName === 'CrossChainInitiated') {
        initial.hasCrossChainInitiated = true;
        const targetChainSelector = this.readPayloadAsString(
          event.payload,
          'targetChain',
        );

        if (targetChainSelector) {
          const mapped = selectorToChainId.get(targetChainSelector);
          initial.destinationChainId = mapped ?? initial.destinationChainId;
        }
      }

      if (event.eventName === 'CrossChainCompleted') {
        initial.hasCrossChainCompleted = true;
        initial.destinationChainId = event.chainId;
      }

      if (
        event.eventName === 'CrossChainDestinationFailed' ||
        event.eventName === 'MessageFailed'
      ) {
        initial.hasCrossChainFailed = true;
      }

      if (!initial.mode && event.eventName === 'LogEntryAdded') {
        const details = this.readPayloadAsString(event.payload, 'details');
        if (details) {
          const parsed = this.extractModeFromDetails(details);
          if (parsed) {
            initial.mode = parsed;
          }
        }
      }
    }

    return initial;
  }

  private computeStatus(projection: ProjectionState): string {
    if (projection.hasRescueFailed || projection.hasCrossChainFailed) {
      return 'failed';
    }

    if (projection.hasCrossChainInitiated && !projection.hasCrossChainCompleted) {
      return 'in_progress';
    }

    if (projection.hasCrossChainCompleted) {
      return 'completed';
    }

    if (projection.hasRescueCompleted) {
      return 'completed';
    }

    if (projection.hasInitiated) {
      return 'in_progress';
    }

    return 'none';
  }

  private extractModeFromDetails(details: string): string | null {
    const match = details.match(/mode=(TOP_UP|REPAY)/i);
    if (!match || !match[1]) {
      return null;
    }

    return match[1].toUpperCase();
  }

  private readPayloadAsString(
    payload: Record<string, unknown>,
    key: string,
  ): string | null {
    const value = payload?.[key];
    if (typeof value === 'string') {
      return value;
    }

    if (typeof value === 'number') {
      return value.toString();
    }

    return null;
  }

  private sortEvents(events: RescueEventEntity[]): RescueEventEntity[] {
    const sortable: SortedEvent[] = events.map((event, idx) => ({
      event,
      sortTuple: [
        event.indexedAt?.getTime() ?? 0,
        event.chainId,
        BigInt(event.blockNumber),
        event.logIndex,
        idx,
      ],
    }));

    sortable.sort((a, b) => {
      if (a.sortTuple[0] !== b.sortTuple[0]) return a.sortTuple[0] - b.sortTuple[0];
      if (a.sortTuple[1] !== b.sortTuple[1]) return a.sortTuple[1] - b.sortTuple[1];
      if (a.sortTuple[2] !== b.sortTuple[2]) return a.sortTuple[2] < b.sortTuple[2] ? -1 : 1;
      if (a.sortTuple[3] !== b.sortTuple[3]) return a.sortTuple[3] - b.sortTuple[3];
      return a.sortTuple[4] - b.sortTuple[4];
    });

    return sortable.map((item) => item.event);
  }
}
