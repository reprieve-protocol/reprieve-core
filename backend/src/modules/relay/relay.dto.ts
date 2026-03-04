import { Transform } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

const MESSAGE_ID_REGEX = /^0x[a-fA-F0-9]{64}$/;

export class ListRelayJobsQueryDto {
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
    description: 'Filter by relay status',
    enum: ['pending', 'running', 'success', 'dead'],
    example: 'pending',
  })
  @IsOptional()
  @IsIn(['pending', 'running', 'success', 'dead'])
  status?: string;

  @ApiPropertyOptional({
    description: 'Filter by source/destination chain id',
    minimum: 1,
    example: 11155111,
  })
  @IsOptional()
  @Transform(({ value }) => (value === undefined ? undefined : Number(value)))
  @IsInt()
  @Min(1)
  chainId?: number;
}

export class MessageIdParamDto {
  @ApiProperty({
    description: 'CCIP message id',
    example: '0x9b0ec998c06926f0e86a3935cd02e0c9ed2d444eb4eb93c899ea7ebe514043d8',
  })
  @Matches(MESSAGE_ID_REGEX)
  messageId!: string;
}
