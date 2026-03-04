import { Body, Controller, Get, Param, Put, Query } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiQuery, ApiTags } from '@nestjs/swagger';
import {
  ListCreRegistrationRevisionsQueryDto,
  UpsertUserCreRegistrationDto,
  UserAddressParamDto,
} from './cre-registrations.dto';
import { CreRegistrationsService } from './cre-registrations.service';

@ApiTags('CRE Registrations')
@Controller('v1/users')
export class CreRegistrationsController {
  constructor(
    private readonly creRegistrationsService: CreRegistrationsService,
  ) {}

  @ApiOperation({
    summary: 'Create or update the active CRE registration for a user',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Put(':address/cre-registration')
  async upsertRegistration(
    @Param() params: UserAddressParamDto,
    @Body() body: UpsertUserCreRegistrationDto,
  ) {
    return this.creRegistrationsService.upsertRegistration(params.address, body);
  }

  @ApiOperation({
    summary: 'Get active CRE registration for a user',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @Get(':address/cre-registration')
  async getRegistration(@Param() params: UserAddressParamDto) {
    return this.creRegistrationsService.getRegistration(params.address);
  }

  @ApiOperation({
    summary: 'List CRE registration revisions for a user',
  })
  @ApiParam({
    name: 'address',
    description: 'Wallet address',
    example: '0x7FbBC4ABd42f91a6e3861D33a67DeC13558658b5',
  })
  @ApiQuery({ name: 'page', required: false, type: Number, description: 'Page number (1-based)' })
  @ApiQuery({ name: 'limit', required: false, type: Number, description: 'Page size (1-100)' })
  @Get(':address/cre-registration/revisions')
  async listRegistrationRevisions(
    @Param() params: UserAddressParamDto,
    @Query() query: ListCreRegistrationRevisionsQueryDto,
  ) {
    return this.creRegistrationsService.listRegistrationRevisions(
      params.address,
      query,
    );
  }
}
