import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import {
  ApiBody,
  ApiOperation,
  ApiParam,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import {
  AddressParamDto,
  RiskSnapshotQueryDto,
  SimulateApiGuardDto,
} from './positions.dto';
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

  @ApiOperation({
    summary: 'Get CRE-ready risk snapshot (cross-chain aggregated positions)',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @ApiQuery({
    name: 'maxAgeSec',
    required: false,
    type: Number,
    description: 'Max acceptable age of latest snapshot for stale flag',
  })
  @Get(':address/risk-snapshot')
  async getRiskSnapshot(
    @Param() params: AddressParamDto,
    @Query() query: RiskSnapshotQueryDto,
  ) {
    return this.positionsService.getRiskSnapshot(params.address, query.maxAgeSec ?? 600);
  }

  @ApiOperation({
    summary: 'Simulate CHAINLINK_API_GUARD_V1 rescue decision and planned step',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @ApiBody({
    required: false,
    type: SimulateApiGuardDto,
  })
  @Post(':address/simulate-api-guard')
  async simulateApiGuard(
    @Param() params: AddressParamDto,
    @Body() body: SimulateApiGuardDto,
  ) {
    return this.positionsService.simulateApiGuardDecision(params.address, body ?? {});
  }
}
