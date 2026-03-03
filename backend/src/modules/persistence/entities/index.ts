import { ChainEntity } from './chain.entity';
import { PositionSnapshotEntity } from './position-snapshot.entity';
import { ProtocolAdapterEntity } from './protocol-adapter.entity';
import { RelayJobEntity } from './relay-job.entity';
import { RescueEventEntity } from './rescue-event.entity';
import { RescueExecutionEntity } from './rescue-execution.entity';

export const PERSISTENCE_ENTITIES = [
  ChainEntity,
  ProtocolAdapterEntity,
  PositionSnapshotEntity,
  RescueEventEntity,
  RescueExecutionEntity,
  RelayJobEntity,
];

export {
  ChainEntity,
  ProtocolAdapterEntity,
  PositionSnapshotEntity,
  RescueEventEntity,
  RescueExecutionEntity,
  RelayJobEntity,
};
