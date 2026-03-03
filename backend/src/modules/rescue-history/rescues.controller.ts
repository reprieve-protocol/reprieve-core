import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiQuery, ApiTags } from '@nestjs/swagger';
import { ExecIdParamDto, ListRescuesQueryDto } from './rescue-history.dto';
import { RescueProjectionService } from './rescue-projection.service';

@ApiTags('Rescues')
@Controller('v1/rescues')
export class RescuesController {
  constructor(private readonly rescueProjectionService: RescueProjectionService) {}

  @ApiOperation({ summary: 'List rescue executions with filters and pagination' })
  @ApiQuery({ name: 'page', required: false, type: Number, description: 'Page number (1-based)' })
  @ApiQuery({ name: 'limit', required: false, type: Number, description: 'Page size (1-100)' })
  @ApiQuery({ name: 'user', required: false, type: String, description: 'User wallet address filter' })
  @ApiQuery({
    name: 'status',
    required: false,
    type: String,
    enum: ['none', 'in_progress', 'completed', 'failed', 'partial', 'cancelled'],
    description: 'Rescue status filter',
  })
  @ApiQuery({ name: 'chainId', required: false, type: Number, description: 'Chain id filter' })
  @Get()
  async listRescues(@Query() query: ListRescuesQueryDto) {
    return this.rescueProjectionService.listRescues(query);
  }

  @ApiOperation({ summary: 'Get rescue execution aggregate by execId' })
  @ApiParam({
    name: 'execId',
    description: 'Rescue execution id',
    example: '0x8750baebd9956ac3b0b73f49a2913e5a01ff0a866e67208c8f60dc4e13406e9c',
  })
  @Get(':execId')
  async getRescue(@Param() params: ExecIdParamDto) {
    return this.rescueProjectionService.getRescue(params.execId);
  }

  @ApiOperation({ summary: 'Get ordered raw events for a rescue execId' })
  @ApiParam({
    name: 'execId',
    description: 'Rescue execution id',
    example: '0x8750baebd9956ac3b0b73f49a2913e5a01ff0a866e67208c8f60dc4e13406e9c',
  })
  @Get(':execId/events')
  async getRescueEvents(@Param() params: ExecIdParamDto) {
    return this.rescueProjectionService.getRescueEvents(params.execId);
  }
}
