import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import {
  ApiOperation,
  ApiParam,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import {
  AddressParamDto,
  OraclePriceQueryDto,
  RiskSnapshotQueryDto,
  SimulateApiGuardDto,
} from './positions.dto';
import { PositionsService } from './positions.service';

@ApiTags('Positions')
@Controller('v1/positions')
export class PositionsController {
  constructor(private readonly positionsService: PositionsService) {}

  private mergeWhatIfAliases<T extends { whatIfPrices?: Record<string, Record<string, string>> }>(
    input: T & {
      'ethereum-sepolia'?: Record<string, string>;
      'base-sepolia'?: Record<string, string>;
    },
  ): T {
    const merged = {
      ...(input.whatIfPrices ?? {}),
    };
    if (input['ethereum-sepolia']) {
      merged['ethereum-sepolia'] = input['ethereum-sepolia'];
    }
    if (input['base-sepolia']) {
      merged['base-sepolia'] = input['base-sepolia'];
    }

    return {
      ...input,
      whatIfPrices: Object.keys(merged).length > 0 ? merged : undefined,
    };
  }

  @ApiOperation({ summary: 'Read oracle price for an asset on a supported chain' })
  @Get('oracle-price')
  async getOraclePrice(@Query() query: OraclePriceQueryDto) {
    return this.positionsService.getOraclePrice(query.chainKey, query.asset);
  }

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
    const normalized = this.mergeWhatIfAliases(query);
    return this.positionsService.getRiskSnapshot(
      params.address,
      normalized.maxAgeSec ?? 600,
      normalized.whatIfPrices,
    );
  }

  @ApiOperation({
    summary:
      'Get CRE-ready risk snapshot (cross-chain aggregated positions) with optional what-if prices',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Post(':address/risk-snapshot')
  async getRiskSnapshotPostAlias(
    @Param() params: AddressParamDto,
    @Body() body: RiskSnapshotQueryDto,
  ) {
    const normalized = this.mergeWhatIfAliases(body);
    return this.positionsService.getRiskSnapshot(
      params.address,
      normalized.maxAgeSec ?? 600,
      normalized.whatIfPrices,
    );
  }

  @ApiOperation({
    summary: 'Simulate CHAINLINK_API_GUARD_V1 rescue decision and planned step',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Get(':address/simulate-api-guard')
  async simulateApiGuard(
    @Param() params: AddressParamDto,
    @Query() query: SimulateApiGuardDto,
  ) {
    return this.positionsService.simulateApiGuardDecision(
      params.address,
      this.mergeWhatIfAliases(query ?? {}),
    );
  }

  @ApiOperation({
    summary:
      'Simulate CHAINLINK_API_GUARD_V1 rescue decision and planned step (POST alias)',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Post(':address/simulate-api-guard')
  async simulateApiGuardPostAlias(
    @Param() params: AddressParamDto,
    @Body() body?: SimulateApiGuardDto,
  ) {
    return this.positionsService.simulateApiGuardDecision(
      params.address,
      this.mergeWhatIfAliases(body ?? {}),
    );
  }
}
