import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  Min,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { SUPPORTED_CHAIN_KEYS, SupportedChainKey } from '../../config/chains.config';

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;

export class AddressParamDto {
  @ApiProperty({
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @IsString()
  @Matches(ADDRESS_REGEX)
  address!: string;
}

export class OraclePriceQueryDto {
  @ApiProperty({
    description: 'Supported chain key',
    enum: ['ethereum-sepolia', 'base-sepolia'],
    example: 'ethereum-sepolia',
  })
  @IsString()
  @IsEnum(SUPPORTED_CHAIN_KEYS)
  chainKey!: SupportedChainKey;

  @ApiProperty({
    description: 'Asset token address',
    example: '0x4c87EA388AdE37f6A556146B4fF6ff2A12192968',
  })
  @IsString()
  @Matches(ADDRESS_REGEX)
  asset!: string;
}

export class RiskSnapshotQueryDto {
  @ApiPropertyOptional({
    description: 'Max acceptable age (seconds) of latest position snapshot',
    minimum: 1,
    example: 600,
    default: 600,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 600 : Number(value)))
  @Min(1)
  maxAgeSec?: number = 600;
}

export class SimulateApiGuardDto {
  @ApiPropertyOptional({
    description: 'Execution chain key used by planner for source withdrawal',
    enum: ['ethereum-sepolia', 'base-sepolia'],
    default: 'ethereum-sepolia',
  })
  @IsOptional()
  @IsString()
  executionChainKey?: SupportedChainKey = 'ethereum-sepolia';

  @ApiPropertyOptional({
    description: 'Max acceptable age (seconds) for latest position snapshot',
    minimum: 1,
    default: 600,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 600 : Number(value)))
  @IsInt()
  @Min(1)
  maxAgeSec?: number = 600;

  @ApiPropertyOptional({
    description: 'Force plan to cross-chain even when source/target appear on same chain',
    default: false,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? false : value === true || value === 'true'))
  @IsBoolean()
  forceCrossChain?: boolean = false;

  @ApiPropertyOptional({
    description: 'Optional source adapter override',
    example: '0x9a2389d74e6318C67824339e37450437b4De7027',
  })
  @IsOptional()
  @IsString()
  @Matches(ADDRESS_REGEX)
  sourceAdapter?: string;

  @ApiPropertyOptional({
    description: 'Optional target adapter override',
    example: '0xA10dD58EcAdf3fd071a23415e55FD23287d684bc',
  })
  @IsOptional()
  @IsString()
  @Matches(ADDRESS_REGEX)
  targetAdapter?: string;

  @ApiPropertyOptional({
    description: 'Early warning health factor threshold in bps',
    minimum: 10000,
    default: 11250,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 11250 : Number(value)))
  @IsInt()
  @Min(10000)
  earlyWarningHfBps?: number = 11250;

  @ApiPropertyOptional({
    description: 'Hard minimum health factor threshold in bps',
    minimum: 10000,
    default: 10000,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 10000 : Number(value)))
  @IsInt()
  @Min(10000)
  onchainHfMinBps?: number = 10000;

  @ApiPropertyOptional({
    description: 'Minimum source HF floor after withdrawal, in bps',
    minimum: 10000,
    default: 11250,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 11250 : Number(value)))
  @IsInt()
  @Min(10000)
  sourceFloorHfBps?: number = 11250;

  @ApiPropertyOptional({
    description: 'Target HF in bps used to size rescue action amount',
    minimum: 10000,
    default: 14500,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 14500 : Number(value)))
  @IsInt()
  @Min(10000)
  targetHfBps?: number = 14500;

  @ApiPropertyOptional({
    description: 'Reserve cap in bps (portion protected from withdrawal)',
    minimum: 0,
    maximum: 10000,
    default: 3000,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 3000 : Number(value)))
  @IsInt()
  @Min(0)
  @Max(10000)
  reserveCapBps?: number = 3000;

  @ApiPropertyOptional({
    description: 'Maximum rescue notional in USD',
    minimum: 1,
    default: 100000,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 100000 : Number(value)))
  @IsInt()
  @Min(1)
  maxRescueNotionalUsd?: number = 100000;

  @ApiPropertyOptional({
    description: 'Minimum action threshold in USD',
    minimum: 0,
    default: 10,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 10 : Number(value)))
  @IsInt()
  @Min(0)
  minActionUsd?: number = 10;

  @ApiPropertyOptional({
    description: 'Allow cross-chain planning',
    default: true,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? true : value === true || value === 'true'))
  @IsBoolean()
  allowCrossChain?: boolean = true;
}
