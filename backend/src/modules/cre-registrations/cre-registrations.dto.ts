import { Transform } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;

export enum CreWorkflowId {
  CHAINLINK_API_GUARD_V1 = 'CHAINLINK_API_GUARD_V1',
  QUANT_FUNDING_OI_V1 = 'QUANT_FUNDING_OI_V1',
  QUANT_BASIS_LIQUIDITY_V1 = 'QUANT_BASIS_LIQUIDITY_V1',
}

export enum QueuePriorityOrder {
  SAME_CHAIN_FIRST = 'SAME_CHAIN_FIRST',
  CROSS_CHAIN_FIRST = 'CROSS_CHAIN_FIRST',
}

export class UserAddressParamDto {
  @ApiProperty({
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @IsString()
  @Matches(ADDRESS_REGEX)
  address!: string;
}

export class UpsertUserCreRegistrationDto {
  @ApiProperty({
    description: 'Workflow strategy to run for this user',
    enum: CreWorkflowId,
    example: CreWorkflowId.CHAINLINK_API_GUARD_V1,
  })
  @IsEnum(CreWorkflowId)
  workflowId!: CreWorkflowId;

  @ApiProperty({
    description: 'Health-factor threshold in basis points (1.00 = 10000)',
    minimum: 1000,
    maximum: 100000,
    example: 11250,
  })
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1000)
  @Max(100000)
  hfThresholdBps!: number;

  @ApiProperty({
    description: 'Rescue priority ordering',
    enum: QueuePriorityOrder,
    example: QueuePriorityOrder.SAME_CHAIN_FIRST,
  })
  @IsEnum(QueuePriorityOrder)
  queuePriority!: QueuePriorityOrder;

  @ApiProperty({
    description: 'Budget cap in USD',
    minimum: 0.01,
    maximum: 1000000000,
    example: 25000,
  })
  @Transform(({ value }) => Number(value))
  @IsNumber()
  @Min(0.01)
  @Max(1000000000)
  budgetCapUsd!: number;

  @ApiPropertyOptional({
    description: 'Mutation source',
    example: 'api',
    default: 'api',
  })
  @IsOptional()
  @IsString()
  @MaxLength(32)
  source?: string;

  @ApiPropertyOptional({
    description: 'Actor identifier for audit trail',
    example: 'user:wallet',
  })
  @IsOptional()
  @IsString()
  @MaxLength(128)
  updatedBy?: string;
}

export class ListCreRegistrationRevisionsQueryDto {
  @ApiPropertyOptional({
    description: 'Page number (1-based)',
    minimum: 1,
    default: 1,
    example: 1,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 1 : Number(value)))
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    description: 'Page size',
    minimum: 1,
    maximum: 100,
    default: 20,
    example: 20,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 20 : Number(value)))
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;
}
