import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Min,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;

export class DemoWalletAddressParamDto {
  @ApiProperty({
    description: 'Managed demo wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @IsString()
  @Matches(ADDRESS_REGEX)
  demoWalletAddress!: string;
}

export class DemoWalletBootstrapRunParamDto extends DemoWalletAddressParamDto {
  @ApiProperty({
    description: 'Bootstrap run id',
    example: 12,
  })
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  runId!: number;
}

export class GenerateDemoWalletDto {
  @ApiProperty({
    description: 'Real user wallet address to seed deterministic demo wallet derivation',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @IsString()
  @Matches(ADDRESS_REGEX)
  realUserAddress!: string;
}

export class FundDemoWalletDto {
  @ApiPropertyOptional({
    description: 'Target native ETH balance on Ethereum Sepolia',
    example: '0.0001',
    default: '0.0001',
  })
  @IsOptional()
  @IsString()
  ethereumSepoliaGasEth?: string;

  @ApiPropertyOptional({
    description: 'Target native ETH balance on Base Sepolia',
    example: '0.0001',
    default: '0.0001',
  })
  @IsOptional()
  @IsString()
  baseSepoliaGasEth?: string;

  @ApiPropertyOptional({
    description: 'Target WETH balance on Ethereum Sepolia',
    example: '80',
    default: '80',
  })
  @IsOptional()
  @IsString()
  ethereumSepoliaWethTarget?: string;

  @ApiPropertyOptional({
    description: 'Target USDC balance on Ethereum Sepolia',
    example: '90000',
    default: '90000',
  })
  @IsOptional()
  @IsString()
  ethereumSepoliaUsdcTarget?: string;

  @ApiPropertyOptional({
    description: 'Target WETH balance on Base Sepolia',
    example: '50',
    default: '50',
  })
  @IsOptional()
  @IsString()
  baseSepoliaWethTarget?: string;

  @ApiPropertyOptional({
    description: 'Target USDC balance on Base Sepolia',
    example: '90000',
    default: '90000',
  })
  @IsOptional()
  @IsString()
  baseSepoliaUsdcTarget?: string;
}

export enum RescueModeDto {
  TOP_UP = 'TOP_UP',
  REPAY = 'REPAY',
}

export class BootstrapDemoWalletDto {
  @ApiProperty({
    description: 'Rescue orientation to prepare for demo runs',
    enum: RescueModeDto,
    example: RescueModeDto.TOP_UP,
  })
  @IsEnum(RescueModeDto)
  rescueMode!: RescueModeDto;

  @ApiPropertyOptional({
    description: 'Force a new bootstrap run even when a successful run already exists',
    default: false,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? false : value === true || value === 'true'))
  @IsBoolean()
  force?: boolean = false;

  @ApiPropertyOptional({
    description: 'Minimum USD amount below which no borrow action will be created',
    default: 1000,
    minimum: 1,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? 1000 : Number(value)))
  @Min(1)
  minBorrowUsd?: number = 1000;
}
