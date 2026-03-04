import { Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiQuery, ApiTags } from '@nestjs/swagger';
import { ListRelayJobsQueryDto, MessageIdParamDto } from './relay.dto';
import { RelayService } from './relay.service';

@ApiTags('Relay')
@Controller('v1/relay/jobs')
export class RelayController {
  constructor(private readonly relayService: RelayService) {}

  @ApiOperation({ summary: 'List relay jobs with filters and pagination' })
  @ApiQuery({ name: 'page', required: false, type: Number, description: 'Page number (1-based)' })
  @ApiQuery({ name: 'limit', required: false, type: Number, description: 'Page size (1-100)' })
  @ApiQuery({
    name: 'status',
    required: false,
    type: String,
    enum: ['pending', 'running', 'success', 'dead'],
    description: 'Relay status filter',
  })
  @ApiQuery({ name: 'chainId', required: false, type: Number, description: 'Source/destination chain id filter' })
  @Get()
  async listRelayJobs(@Query() query: ListRelayJobsQueryDto) {
    return this.relayService.listRelayJobs(query);
  }

  @ApiOperation({ summary: 'Get one relay job by message id' })
  @ApiParam({
    name: 'messageId',
    description: 'CCIP message id',
    example: '0x9b0ec998c06926f0e86a3935cd02e0c9ed2d444eb4eb93c899ea7ebe514043d8',
  })
  @Get(':messageId')
  async getRelayJob(@Param() params: MessageIdParamDto) {
    return this.relayService.getRelayJob(params.messageId);
  }

  @ApiOperation({ summary: 'Manually retry a relay job (sets status back to pending)' })
  @ApiParam({
    name: 'messageId',
    description: 'CCIP message id',
    example: '0x9b0ec998c06926f0e86a3935cd02e0c9ed2d444eb4eb93c899ea7ebe514043d8',
  })
  @Post(':messageId/retry')
  async retryRelayJob(@Param() params: MessageIdParamDto) {
    return this.relayService.retryRelayJob(params.messageId);
  }
}
