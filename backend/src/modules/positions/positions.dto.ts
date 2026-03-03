import { IsOptional, IsString, Matches, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';

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
