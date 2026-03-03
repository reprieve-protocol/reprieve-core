import { IsString, Matches } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

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
