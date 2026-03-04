import { NotFoundException } from '@nestjs/common';
import { CreRegistrationsService } from '../src/modules/cre-registrations/cre-registrations.service';
import {
  CreWorkflowId,
  QueuePriorityOrder,
} from '../src/modules/cre-registrations/cre-registrations.dto';
import {
  UserCreRegistrationRevisionEntity,
  UserCreRegistrationEntity,
} from '../src/modules/persistence/entities';

describe('CreRegistrationsService', () => {
  let registrationRows: UserCreRegistrationEntity[] = [];
  let revisionRows: UserCreRegistrationRevisionEntity[] = [];
  let registrationIdSeq = 1;
  let revisionIdSeq = 1;

  const registrationRepository = {
    findOne: jest.fn(async ({ where }: { where: Partial<UserCreRegistrationEntity> }) => {
      return (
        registrationRows.find((row) => {
          if (where.userAddress && row.userAddress !== where.userAddress) return false;
          if (where.isActive !== undefined && row.isActive !== where.isActive) return false;
          return true;
        }) ?? null
      );
    }),
    manager: {
      transaction: jest.fn(async (callback: (manager: any) => Promise<unknown>) => {
        const manager = {
          getRepository: (entity: unknown) => {
            if (entity === UserCreRegistrationEntity) {
              return {
                findOne: registrationRepository.findOne,
                save: async (payload: Partial<UserCreRegistrationEntity>) => {
                  const now = payload.updatedAt ?? new Date();
                  if (payload.id) {
                    const existing = registrationRows.find((r) => r.id === payload.id);
                    if (!existing) {
                      throw new Error('missing registration for update');
                    }
                    Object.assign(existing, payload, { updatedAt: now });
                    return existing;
                  }

                  const created: UserCreRegistrationEntity = {
                    id: registrationIdSeq++,
                    userAddress: String(payload.userAddress),
                    workflowId: String(payload.workflowId),
                    hfThresholdBps: Number(payload.hfThresholdBps),
                    queuePriority: String(payload.queuePriority),
                    budgetCapUsd: String(payload.budgetCapUsd),
                    isActive: payload.isActive ?? true,
                    createdAt: payload.createdAt ?? now,
                    updatedAt: now,
                  };
                  registrationRows.push(created);
                  return created;
                },
              };
            }

            if (entity === UserCreRegistrationRevisionEntity) {
              return {
                save: async (payload: Partial<UserCreRegistrationRevisionEntity>) => {
                  const created: UserCreRegistrationRevisionEntity = {
                    id: revisionIdSeq++,
                    registrationId: Number(payload.registrationId),
                    userAddress: String(payload.userAddress),
                    workflowId: String(payload.workflowId),
                    hfThresholdBps: Number(payload.hfThresholdBps),
                    queuePriority: String(payload.queuePriority),
                    budgetCapUsd: String(payload.budgetCapUsd),
                    isActive: payload.isActive ?? true,
                    changeType: String(payload.changeType),
                    changeSource: String(payload.changeSource ?? 'api'),
                    updatedBy: payload.updatedBy ?? null,
                    createdAt: payload.createdAt ?? new Date(),
                  };
                  revisionRows.push(created);
                  return created;
                },
              };
            }

            throw new Error('unexpected repository');
          },
        };
        return callback(manager);
      }),
    },
  };

  const revisionRepository = {
    findAndCount: jest.fn(async ({
      where,
      skip = 0,
      take = 20,
    }: {
      where: { userAddress: string };
      skip?: number;
      take?: number;
    }) => {
      const rows = revisionRows
        .filter((row) => row.userAddress === where.userAddress)
        .sort((a, b) => b.id - a.id);
      return [rows.slice(skip, skip + take), rows.length];
    }),
  };

  const makeService = (): CreRegistrationsService =>
    new CreRegistrationsService(
      registrationRepository as never,
      revisionRepository as never,
    );

  beforeEach(() => {
    registrationRows = [];
    revisionRows = [];
    registrationIdSeq = 1;
    revisionIdSeq = 1;
    jest.clearAllMocks();
  });

  it('creates then updates a single active registration with revision history', async () => {
    const service = makeService();
    const user = '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5';

    const created = await service.upsertRegistration(user, {
      workflowId: CreWorkflowId.CHAINLINK_API_GUARD_V1,
      hfThresholdBps: 11250,
      queuePriority: QueuePriorityOrder.SAME_CHAIN_FIRST,
      budgetCapUsd: 15000,
      source: 'api',
      updatedBy: 'tester-1',
    });

    expect(created.status).toBe('created');
    expect(registrationRows).toHaveLength(1);
    expect(revisionRows).toHaveLength(1);
    expect(revisionRows[0].changeType).toBe('created');

    const updated = await service.upsertRegistration(user, {
      workflowId: CreWorkflowId.QUANT_FUNDING_OI_V1,
      hfThresholdBps: 12000,
      queuePriority: QueuePriorityOrder.CROSS_CHAIN_FIRST,
      budgetCapUsd: 22000.5,
      source: 'api',
      updatedBy: 'tester-2',
    });

    expect(updated.status).toBe('updated');
    expect(registrationRows).toHaveLength(1);
    expect(registrationRows[0].workflowId).toBe(CreWorkflowId.QUANT_FUNDING_OI_V1);
    expect(registrationRows[0].budgetCapUsd).toBe('22000.50');
    expect(revisionRows).toHaveLength(2);
    expect(revisionRows[1].changeType).toBe('updated');

    const current = await service.getRegistration(user);
    expect((current.registration as any).workflowId).toBe(
      CreWorkflowId.QUANT_FUNDING_OI_V1,
    );

    const history = await service.listRegistrationRevisions(user, { page: 1, limit: 20 });
    expect(history.total).toBe(2);
    expect((history.revisions as any[])[0].changeType).toBe('updated');
    expect((history.revisions as any[])[1].changeType).toBe('created');
  });

  it('throws not found when user has no active registration', async () => {
    const service = makeService();
    await expect(
      service.getRegistration('0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
