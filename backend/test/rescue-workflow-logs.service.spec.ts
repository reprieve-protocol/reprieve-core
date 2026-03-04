import { NotFoundException } from '@nestjs/common';
import { RescueWorkflowLogsService } from '../src/modules/rescue-history/rescue-workflow-logs.service';

describe('RescueWorkflowLogsService', () => {
  const rescueExecutionRepository = {
    findOne: jest.fn(),
  };
  const rescueWorkflowLogRepository = {
    save: jest.fn(),
    findAndCount: jest.fn(),
  };

  const makeService = (): RescueWorkflowLogsService =>
    new RescueWorkflowLogsService(
      rescueExecutionRepository as never,
      rescueWorkflowLogRepository as never,
    );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('stores and lists workflow logs mapped to an execution', async () => {
    const service = makeService();
    const execId = '0x8750baebd9956ac3b0b73f49a2913e5a01ff0a866e67208c8f60dc4e13406e9c';
    const normalizedExecId = execId.toLowerCase();
    const createdAt = new Date('2026-03-04T08:00:00.000Z');

    rescueExecutionRepository.findOne.mockResolvedValue({
      id: 12,
      execId: normalizedExecId,
    });
    rescueWorkflowLogRepository.save.mockResolvedValue({
      id: 1,
      rescueExecutionId: 12,
      execId: normalizedExecId,
      workflowId: 'CHAINLINK_API_GUARD_V1',
      runId: 'run-1',
      logText: 'long log payload',
      metadata: { trigger: 'http' },
      createdAt,
    });
    rescueWorkflowLogRepository.findAndCount.mockResolvedValue([
      [
        {
          id: 1,
          rescueExecutionId: 12,
          execId: normalizedExecId,
          workflowId: 'CHAINLINK_API_GUARD_V1',
          runId: 'run-1',
          logText: 'long log payload',
          metadata: { trigger: 'http' },
          createdAt,
        },
      ],
      1,
    ]);

    const created = await service.createWorkflowLog(execId, {
      workflowId: 'CHAINLINK_API_GUARD_V1',
      runId: 'run-1',
      logText: 'long log payload',
      metadata: { trigger: 'http' },
    });
    expect((created.log as any).execId).toBe(normalizedExecId);
    expect((created.log as any).rescueExecutionId).toBe(12);

    const listed = await service.listWorkflowLogs(execId, {
      page: 1,
      limit: 20,
    });
    expect(listed.execId).toBe(normalizedExecId);
    expect(listed.total).toBe(1);
    expect((listed.logs as any[])[0].workflowId).toBe('CHAINLINK_API_GUARD_V1');
  });

  it('throws when rescue execution is missing', async () => {
    const service = makeService();
    rescueExecutionRepository.findOne.mockResolvedValue(null);

    await expect(
      service.createWorkflowLog(
        '0x8750baebd9956ac3b0b73f49a2913e5a01ff0a866e67208c8f60dc4e13406e9c',
        {
          logText: 'abc',
        },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
