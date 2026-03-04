import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { getAddress } from 'ethers';
import { Repository } from 'typeorm';
import {
  UserCreRegistrationRevisionEntity,
  UserCreRegistrationEntity,
} from '../persistence/entities';
import {
  ListCreRegistrationRevisionsQueryDto,
  UpsertUserCreRegistrationDto,
} from './cre-registrations.dto';

@Injectable()
export class CreRegistrationsService {
  constructor(
    @InjectRepository(UserCreRegistrationEntity)
    private readonly userCreRegistrationRepository: Repository<UserCreRegistrationEntity>,
    @InjectRepository(UserCreRegistrationRevisionEntity)
    private readonly userCreRegistrationRevisionRepository: Repository<UserCreRegistrationRevisionEntity>,
  ) {}

  async upsertRegistration(
    userAddressInput: string,
    dto: UpsertUserCreRegistrationDto,
  ): Promise<Record<string, unknown>> {
    const userAddress = this.normalizeAddressLower(userAddressInput);
    const source = (dto.source?.trim() || 'api').slice(0, 32);
    const updatedBy =
      dto.updatedBy && dto.updatedBy.trim().length > 0
        ? dto.updatedBy.trim().slice(0, 128)
        : null;
    const budgetCapUsd = dto.budgetCapUsd.toFixed(2);

    return this.userCreRegistrationRepository.manager.transaction(async (manager) => {
      const registrationRepository = manager.getRepository(UserCreRegistrationEntity);
      const revisionRepository = manager.getRepository(
        UserCreRegistrationRevisionEntity,
      );

      const existing = await registrationRepository.findOne({
        where: { userAddress },
      });
      const now = new Date();
      const status = existing ? 'updated' : 'created';

      const registration = await registrationRepository.save({
        id: existing?.id,
        userAddress,
        workflowId: dto.workflowId,
        hfThresholdBps: dto.hfThresholdBps,
        queuePriority: dto.queuePriority,
        budgetCapUsd,
        isActive: true,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      });

      await revisionRepository.save({
        registrationId: registration.id,
        userAddress: registration.userAddress,
        workflowId: registration.workflowId,
        hfThresholdBps: registration.hfThresholdBps,
        queuePriority: registration.queuePriority,
        budgetCapUsd: registration.budgetCapUsd,
        isActive: registration.isActive,
        changeType: status,
        changeSource: source,
        updatedBy,
        createdAt: now,
      });

      return {
        status,
        registration: this.toRegistrationDto(registration),
      };
    });
  }

  async getRegistration(userAddressInput: string): Promise<Record<string, unknown>> {
    const userAddress = this.normalizeAddressLower(userAddressInput);
    const registration = await this.userCreRegistrationRepository.findOne({
      where: { userAddress, isActive: true },
    });

    if (!registration) {
      throw new NotFoundException(
        `CRE registration not found for user: ${getAddress(userAddress)}`,
      );
    }

    return {
      registration: this.toRegistrationDto(registration),
    };
  }

  async listRegistrationRevisions(
    userAddressInput: string,
    query: ListCreRegistrationRevisionsQueryDto,
  ): Promise<Record<string, unknown>> {
    const userAddress = this.normalizeAddressLower(userAddressInput);
    const page = Math.max(1, query.page ?? 1);
    const limit = Math.min(100, Math.max(1, query.limit ?? 20));
    const skip = (page - 1) * limit;

    const [rows, total] = await this.userCreRegistrationRevisionRepository.findAndCount({
      where: { userAddress },
      order: { id: 'DESC' },
      skip,
      take: limit,
    });

    return {
      userAddress: getAddress(userAddress),
      page,
      limit,
      total,
      revisions: rows.map((row) => ({
        id: row.id,
        registrationId: row.registrationId,
        workflowId: row.workflowId,
        hfThresholdBps: row.hfThresholdBps,
        queuePriority: row.queuePriority,
        budgetCapUsd: Number(row.budgetCapUsd),
        isActive: row.isActive,
        changeType: row.changeType,
        changeSource: row.changeSource,
        updatedBy: row.updatedBy,
        createdAt: row.createdAt.toISOString(),
      })),
    };
  }

  private normalizeAddressLower(value: string): string {
    return getAddress(value).toLowerCase();
  }

  private toRegistrationDto(
    registration: UserCreRegistrationEntity,
  ): Record<string, unknown> {
    return {
      id: registration.id,
      userAddress: getAddress(registration.userAddress),
      workflowId: registration.workflowId,
      hfThresholdBps: registration.hfThresholdBps,
      queuePriority: registration.queuePriority,
      budgetCapUsd: Number(registration.budgetCapUsd),
      isActive: registration.isActive,
      createdAt: registration.createdAt.toISOString(),
      updatedAt: registration.updatedAt.toISOString(),
    };
  }
}
