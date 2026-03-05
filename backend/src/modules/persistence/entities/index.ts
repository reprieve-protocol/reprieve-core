import { ChainEntity } from './chain.entity';
import { DemoWalletBootstrapRunEntity } from './demo-wallet-bootstrap-run.entity';
import { DemoWalletFundingRunEntity } from './demo-wallet-funding-run.entity';
import { DemoWalletEntity } from './demo-wallet.entity';
import { PositionSnapshotEntity } from './position-snapshot.entity';
import { ProtocolAdapterEntity } from './protocol-adapter.entity';
import { RelayJobEntity } from './relay-job.entity';
import { RescueEventEntity } from './rescue-event.entity';
import { RescueExecutionEntity } from './rescue-execution.entity';
import { RescueWorkflowLogEntity } from './rescue-workflow-log.entity';
import { UserCreRegistrationRevisionEntity } from './user-cre-registration-revision.entity';
import { UserCreRegistrationEntity } from './user-cre-registration.entity';
import { UserRescueStepEntity } from './user-rescue-step.entity';

export const PERSISTENCE_ENTITIES = [
  ChainEntity,
  ProtocolAdapterEntity,
  PositionSnapshotEntity,
  RescueEventEntity,
  RescueExecutionEntity,
  RescueWorkflowLogEntity,
  RelayJobEntity,
  DemoWalletEntity,
  DemoWalletFundingRunEntity,
  DemoWalletBootstrapRunEntity,
  UserCreRegistrationEntity,
  UserCreRegistrationRevisionEntity,
  UserRescueStepEntity,
];

export {
  ChainEntity,
  ProtocolAdapterEntity,
  PositionSnapshotEntity,
  RescueEventEntity,
  RescueExecutionEntity,
  RescueWorkflowLogEntity,
  RelayJobEntity,
  DemoWalletEntity,
  DemoWalletFundingRunEntity,
  DemoWalletBootstrapRunEntity,
  UserCreRegistrationEntity,
  UserCreRegistrationRevisionEntity,
  UserRescueStepEntity,
};
