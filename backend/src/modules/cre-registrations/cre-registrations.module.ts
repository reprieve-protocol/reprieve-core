import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  UserCreRegistrationRevisionEntity,
  UserCreRegistrationEntity,
} from '../persistence/entities';
import { CreRegistrationsController } from './cre-registrations.controller';
import { CreRegistrationsService } from './cre-registrations.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      UserCreRegistrationEntity,
      UserCreRegistrationRevisionEntity,
    ]),
  ],
  controllers: [CreRegistrationsController],
  providers: [CreRegistrationsService],
  exports: [CreRegistrationsService],
})
export class CreRegistrationsModule {}
