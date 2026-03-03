import { Controller, Get, Param } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiTags } from '@nestjs/swagger';
import { AddressParamDto } from './positions.dto';
import { PositionsService } from './positions.service';

@ApiTags('Positions')
@Controller('v1/positions')
export class PositionsController {
  constructor(private readonly positionsService: PositionsService) {}

  @ApiOperation({ summary: 'Get latest known positions for a wallet address' })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Get(':address')
  async getPositions(@Param() params: AddressParamDto) {
    return this.positionsService.getPositions(params.address);
  }
}
