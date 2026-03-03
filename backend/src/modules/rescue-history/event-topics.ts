export const EVENT_TOPICS = {
  PositionUpdated:
    '0x9208581a0e171145ce93f9f72ef656f294f2c169925e140f0f20406aba1a04ae',
  RescueInitiated:
    '0xd4128db1fda076924846d094ad59a41b49f7a4549d7458efe4cc4b646e71ff8f',
  RescueStepCompleted:
    '0x514662d55cd5547edcd009c6570869f270902339ffb7985ede2ffff582902e62',
  RescueCompleted:
    '0x33b6af444fe9519ea73c16ffe62acbdc79315a8279b135dea1c39fbf71e57600',
  RescueFailed:
    '0xa2009c4dd61cbd90c9ae3bd19525a33ddbc46f3dc6973936180c9f1f091b6dbe',
  CrossChainInitiated:
    '0x4cdde96a772bd91aba8e6b851177e3723470d4e954a493eb5d018aa56320c30c',
  CrossChainCompleted:
    '0x9a38f04f175068f7831600f534c9e0a415195bdd7ed9af8a9db2618ee37ee11d',
  CrossChainDestinationFailed:
    '0xa1a9797d1cf848fa8a8558bc9e2d8cefadf44a7c0155cc17c5aa72b965d58a30',
  EscrowCreated:
    '0x50695c66e89a8e569a3b023ade1c3eb8931859c633360562f1233b9b543894f7',
  LogEntryAdded:
    '0x9da6638612079a2a3ab8cb4a63cb496a07b5140f812f0870dfc6a4f2bab6394e',
  MessageFailed:
    '0xe8f12c23b5fd4f02be2f5efb64d44b3403acc8907eac3d41c338ff5ad3d19016',
} as const;

export type IndexedEventName = keyof typeof EVENT_TOPICS;

export const INDEXED_EVENT_TOPIC_LIST: string[] = Object.values(EVENT_TOPICS);
