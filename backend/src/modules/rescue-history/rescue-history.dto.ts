import { Transform } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;
const EXEC_ID_REGEX = /^0x[a-fA-F0-9]{64}$/;

export class ListRescuesQueryDto {
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

  @ApiPropertyOptional({
    description: 'Filter by user wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @IsOptional()
  @Matches(ADDRESS_REGEX)
  user?: string;

  @ApiPropertyOptional({
    description: 'Filter by rescue status',
    enum: ['none', 'in_progress', 'completed', 'failed', 'partial', 'cancelled'],
    example: 'completed',
  })
  @IsOptional()
  @IsIn(['none', 'in_progress', 'completed', 'failed', 'partial', 'cancelled'])
  status?: string;

  @ApiPropertyOptional({
    description: 'Filter by chain id',
    minimum: 1,
    example: 11155111,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? undefined : Number(value)))
  @IsInt()
  @Min(1)
  chainId?: number;
}

export class ExecIdParamDto {
  @ApiProperty({
    description: 'Rescue execution ID',
    example: '0x8750baebd9956ac3b0b73f49a2913e5a01ff0a866e67208c8f60dc4e13406e9c',
  })
  @Matches(EXEC_ID_REGEX)
  execId!: string;
}
