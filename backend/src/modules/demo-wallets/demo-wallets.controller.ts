import { Body, Controller, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiTags } from '@nestjs/swagger';
import {
  BootstrapDemoWalletDto,
  DemoWalletAddressParamDto,
  FundDemoWalletDto,
  GenerateDemoWalletDto,
} from './demo-wallets.dto';
import { DemoWalletsService } from './demo-wallets.service';

@ApiTags('Demo Wallets')
@Controller('v1/demo-wallets')
export class DemoWalletsController {
  constructor(private readonly demoWalletsService: DemoWalletsService) {}

  @ApiOperation({
    summary: 'Generate deterministic managed demo wallet from real user address',
  })
  @Post('generate')
  async generate(@Body() body: GenerateDemoWalletDto) {
    return this.demoWalletsService.generateDemoWallet(body.realUserAddress);
  }

  @ApiOperation({
    summary: 'Mint demo balances and fund native gas on supported chains',
  })
  @ApiParam({
    name: 'demoWalletAddress',
    description: 'Managed demo wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Post(':demoWalletAddress/fund')
  async fund(
    @Param() params: DemoWalletAddressParamDto,
    @Body() body: FundDemoWalletDto,
  ) {
    return this.demoWalletsService.fundDemoWallet(params.demoWalletAddress, body);
  }

  @ApiOperation({
    summary: 'Bootstrap demo wallet positions for rescue scenarios across Ethereum/Base Sepolia',
  })
  @ApiParam({
    name: 'demoWalletAddress',
    description: 'Managed demo wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Post(':demoWalletAddress/bootstrap-positions')
  async bootstrapPositions(
    @Param() params: DemoWalletAddressParamDto,
    @Body() body: BootstrapDemoWalletDto,
  ) {
    return this.demoWalletsService.bootstrapPositions(params.demoWalletAddress, body);
  }
}
