import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';

@ApiTags('Health')
@Controller('v1/health')
export class HealthController {
  @ApiOperation({ summary: 'Health check endpoint' })
  @Get()
  getHealth(): { service: string; status: string; timestamp: string } {
    return {
      service: 'reprieve-backend',
      status: 'ok',
      timestamp: new Date().toISOString(),
    };
  }
}
