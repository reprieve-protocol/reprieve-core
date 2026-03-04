import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  RescueExecutionEntity,
  RescueWorkflowLogEntity,
} from '../persistence/entities';
import {
  CreateRescueWorkflowLogDto,
  ListRescueWorkflowLogsQueryDto,
} from './rescue-history.dto';

@Injectable()
export class RescueWorkflowLogsService {
  constructor(
    @InjectRepository(RescueExecutionEntity)
    private readonly rescueExecutionRepository: Repository<RescueExecutionEntity>,
    @InjectRepository(RescueWorkflowLogEntity)
    private readonly rescueWorkflowLogRepository: Repository<RescueWorkflowLogEntity>,
  ) {}

  async createWorkflowLog(
    execIdInput: string,
    dto: CreateRescueWorkflowLogDto,
  ): Promise<Record<string, unknown>> {
    const execId = execIdInput.toLowerCase();
    const execution = await this.rescueExecutionRepository.findOne({
      where: { execId },
    });
    if (!execution) {
      throw new NotFoundException(`Rescue execution not found: ${execIdInput}`);
    }

    const created = await this.rescueWorkflowLogRepository.save({
      rescueExecutionId: execution.id,
      execId,
      workflowId: dto.workflowId ?? null,
      runId: dto.runId ?? null,
      logText: dto.logText,
      metadata: dto.metadata ?? {},
    });

    return {
      log: this.toLogDto(created),
    };
  }

  async listWorkflowLogs(
    execIdInput: string,
    query: ListRescueWorkflowLogsQueryDto,
  ): Promise<Record<string, unknown>> {
    const execId = execIdInput.toLowerCase();
    const execution = await this.rescueExecutionRepository.findOne({
      where: { execId },
    });
    if (!execution) {
      throw new NotFoundException(`Rescue execution not found: ${execIdInput}`);
    }

    const page = Math.max(1, query.page ?? 1);
    const limit = Math.min(100, Math.max(1, query.limit ?? 20));
    const skip = (page - 1) * limit;

    const [rows, total] = await this.rescueWorkflowLogRepository.findAndCount({
      where: { execId },
      order: { id: 'DESC' },
      skip,
      take: limit,
    });

    return {
      execId,
      page,
      limit,
      total,
      logs: rows.map((row) => this.toLogDto(row)),
    };
  }

  private toLogDto(row: RescueWorkflowLogEntity): Record<string, unknown> {
    return {
      id: row.id,
      rescueExecutionId: row.rescueExecutionId,
      execId: row.execId,
      workflowId: row.workflowId,
      runId: row.runId,
      logText: row.logText,
      metadata: row.metadata ?? {},
      createdAt: row.createdAt.toISOString(),
    };
  }
}
