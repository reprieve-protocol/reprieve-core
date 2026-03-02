import {
  cre,
  type Runtime,
  type EVMLog,
  getNetwork,
  encodeCallMsg,
  LAST_FINALIZED_BLOCK_NUMBER,
  bytesToHex,
  hexToBase64,
} from "@chainlink/cre-sdk";
import {
  decodeEventLog,
  decodeFunctionResult,
  encodeFunctionData,
  parseAbi,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import type { BaseWorkflowConfig } from "../types";

export interface ChainRef {
  chainSelectorName: string;
  isTestnet: boolean;
}

export interface AdapterPosition {
  protocol: Address;
  collateralAsset: Address;
  debtAsset: Address;
  collateralAmount: bigint;
  debtAmount: bigint;
  healthFactor: bigint;
  ltvBps: bigint;
  maxLtvBps: bigint;
  liquidationThresholdBps: bigint;
}

export interface RescueStepInput {
  stepIndex: bigint;
  sourceAdapter: Address;
  targetAdapter: Address;
  collateralAsset: Address;
  debtAsset: Address;
  collateralAmount: bigint;
  debtAmount: bigint;
  isCrossChain: boolean;
  targetChain: bigint;
}

export interface RescuePlanInput {
  execId: Hex;
  user: Address;
  mode: number;
  steps: RescueStepInput[];
  deadline: bigint;
  maxFee: bigint;
}

export interface RescueLogEntry {
  execId: Hex;
  stepIndex: bigint;
  user: Address;
  status: bigint;
  timestamp: bigint;
  details: string;
}

export interface FailedMessageSnapshot {
  messageId: Hex;
  escrowId: Hex;
  sourceChainSelector: bigint;
  sender: Address;
  data: Hex;
  tokenAmounts: Array<{ token: Address; amount: bigint }>;
  reason: string;
  timestamp: bigint;
  recovered: boolean;
}

export interface DecodedLifecycleEvent {
  eventName: string;
  args: Record<string, unknown>;
}

export interface CrossChainTerminalEvent {
  execId: Hex;
  messageId: Hex;
  status: "SUCCESS" | "FAILED";
  amountReceived?: bigint;
  reason?: string;
}

const ADAPTER_ABI = parseAbi([
  "function discoverPositions(address user) view returns ((address protocol,address collateralAsset,address debtAsset,uint256 collateralAmount,uint256 debtAmount,uint256 healthFactor,uint256 ltvBps,uint256 maxLtvBps,uint256 liquidationThresholdBps)[] positions)",
  "function healthFactor(address user) view returns (uint256 hfWad)",
  "function availableCollateral(address user, address asset) view returns (uint256 amount)",
]);

const RESCUE_EXECUTOR_ABI = parseAbi([
  "function rescueInProgress(address user) view returns (bool)",
  "function getRescueStatus(bytes32 execId) view returns (uint8)",
  "function getCcipMessageId(bytes32 execId) view returns (bytes32)",
  "function executeRescue((bytes32 execId,address user,uint8 mode,(uint256 stepIndex,address sourceAdapter,address targetAdapter,address collateralAsset,address debtAsset,uint256 collateralAmount,uint256 debtAmount,bool isCrossChain,uint64 targetChain)[] steps,uint256 deadline,uint256 maxFee) plan) returns (bool success)",
]);

const RESCUE_LOG_ABI = parseAbi([
  "function getLogEntries(bytes32 execId) view returns ((bytes32 execId,uint256 stepIndex,address user,uint8 status,uint256 timestamp,string details)[] entries)",
]);

const CCIP_RECEIVER_ABI = parseAbi([
  "function getFailedMessage(bytes32 messageId) view returns ((bytes32 messageId,bytes32 escrowId,uint64 sourceChainSelector,address sender,bytes data,(address token,uint256 amount)[] tokenAmounts,string reason,uint256 timestamp,bool recovered) failedMessage)",
]);

const ERC20_METADATA_ABI = parseAbi([
  "function decimals() view returns (uint8)",
]);

const REPRIEVE_EVENT_ABI = parseAbi([
  "event RescueInitiated(bytes32 indexed execId,address indexed user,uint256 steps,uint256 deadline)",
  "event RescueCompleted(bytes32 indexed execId,address indexed user,uint8 status,uint256 finalStepIndex)",
  "event RescueFailed(bytes32 indexed execId,address indexed user,string reason,uint256 failedStepIndex)",
  "event CrossChainInitiated(bytes32 indexed execId,uint64 indexed targetChain,bytes32 indexed ccipMessageId,uint256 feePaid)",
  "event CrossChainCompleted(bytes32 indexed execId,bytes32 indexed ccipMessageId,uint256 amountReceived)",
  "event CrossChainDestinationFailed(bytes32 indexed execId,bytes32 indexed ccipMessageId,string reason)",
  "event LogEntryAdded(bytes32 indexed execId,uint256 indexed stepIndex,address indexed user,uint8 status,string details)",
]);

const normalizeTxHash = (input: string): Hex => {
  if (input.startsWith("0x")) {
    return input as Hex;
  }
  return (`0x${Buffer.from(input, "base64").toString("hex")}`) as Hex;
};

export const createEvmClient = (chain: ChainRef) => {
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: chain.chainSelectorName,
    isTestnet: chain.isTestnet,
  });

  if (!network) {
    throw new Error(`Network not found: ${chain.chainSelectorName}`);
  }

  return new cre.capabilities.EVMClient(network.chainSelector.selector);
};

const readContract = <T>(
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  contractAddress: Address,
  abi: ReturnType<typeof parseAbi>,
  functionName: string,
  args: unknown[] = []
): T => {
  const evmClient = createEvmClient(chain);

  const calldata = encodeFunctionData({
    abi,
    functionName,
    args,
  });

  const response = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: contractAddress,
        data: calldata,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  return decodeFunctionResult({
    abi,
    functionName,
    data: bytesToHex(response.data),
  }) as T;
};

const writeContract = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  contractAddress: Address,
  abi: ReturnType<typeof parseAbi>,
  functionName: string,
  args: unknown[] = [],
  gasLimit = "900000"
): Hex => {
  const evmClient = createEvmClient(chain);

  const calldata = encodeFunctionData({
    abi,
    functionName,
    args,
  });

  const result = (evmClient as any).write(
    {
      contractAddress: hexToBase64(contractAddress),
      calldata: hexToBase64(calldata),
    },
    { gasLimit }
  );

  if (!result.transactionHash) {
    throw new Error(`No transaction hash returned for ${functionName}`);
  }

  return normalizeTxHash(result.transactionHash);
};

export const discoverPositions = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  adapterAddress: Address,
  user: Address
): AdapterPosition[] =>
  readContract<AdapterPosition[]>(
    runtime,
    chain,
    adapterAddress,
    ADAPTER_ABI,
    "discoverPositions",
    [user]
  );

export const readHealthFactor = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  adapterAddress: Address,
  user: Address
): bigint =>
  readContract<bigint>(
    runtime,
    chain,
    adapterAddress,
    ADAPTER_ABI,
    "healthFactor",
    [user]
  );

export const readAvailableCollateral = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  adapterAddress: Address,
  user: Address,
  asset: Address
): bigint =>
  readContract<bigint>(
    runtime,
    chain,
    adapterAddress,
    ADAPTER_ABI,
    "availableCollateral",
    [user, asset]
  );

export const readTokenDecimals = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  tokenAddress: Address
): number =>
  Number(
    readContract<bigint>(
      runtime,
      chain,
      tokenAddress,
      ERC20_METADATA_ABI,
      "decimals",
      []
    )
  );

export const readAdapterSnapshot = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  adapterAddress: Address,
  user: Address,
  collateralAsset: Address
) => {
  const positions = discoverPositions(runtime, chain, adapterAddress, user);
  const hfWad = readHealthFactor(runtime, chain, adapterAddress, user);
  const availableCollateral = readAvailableCollateral(
    runtime,
    chain,
    adapterAddress,
    user,
    collateralAsset
  );

  return { positions, hfWad, availableCollateral };
};

export const readRescueInProgress = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  executorAddress: Address,
  user: Address
): boolean =>
  readContract<boolean>(
    runtime,
    chain,
    executorAddress,
    RESCUE_EXECUTOR_ABI,
    "rescueInProgress",
    [user]
  );

export const readRescueStatus = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  executorAddress: Address,
  execId: Hex
): bigint =>
  readContract<bigint>(
    runtime,
    chain,
    executorAddress,
    RESCUE_EXECUTOR_ABI,
    "getRescueStatus",
    [execId]
  );

export const readCcipMessageId = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  executorAddress: Address,
  execId: Hex
): Hex =>
  readContract<Hex>(
    runtime,
    chain,
    executorAddress,
    RESCUE_EXECUTOR_ABI,
    "getCcipMessageId",
    [execId]
  );

export const submitRescuePlan = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  executorAddress: Address,
  plan: RescuePlanInput,
  gasLimit = "1200000"
): Hex =>
  writeContract(
    runtime,
    chain,
    executorAddress,
    RESCUE_EXECUTOR_ABI,
    "executeRescue",
    [plan],
    gasLimit
  );

export const readRescueLogEntries = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  rescueLogAddress: Address,
  execId: Hex
): RescueLogEntry[] =>
  readContract<RescueLogEntry[]>(
    runtime,
    chain,
    rescueLogAddress,
    RESCUE_LOG_ABI,
    "getLogEntries",
    [execId]
  );

export const readFailedMessage = (
  runtime: Runtime<BaseWorkflowConfig>,
  chain: ChainRef,
  ccipReceiverAddress: Address,
  messageId: Hex
): FailedMessageSnapshot =>
  readContract<FailedMessageSnapshot>(
    runtime,
    chain,
    ccipReceiverAddress,
    CCIP_RECEIVER_ABI,
    "getFailedMessage",
    [messageId]
  );

export const decodeReprieveEvent = (log: EVMLog): DecodedLifecycleEvent | null => {
  const topics = log.topics.map((item) => bytesToHex(item)) as [Hex, ...Hex[]];
  const data = bytesToHex(log.data);

  try {
    const decoded = decodeEventLog({
      abi: REPRIEVE_EVENT_ABI,
      topics,
      data,
    });

    return {
      eventName: decoded.eventName,
      args: (decoded.args ?? {}) as Record<string, unknown>,
    };
  } catch {
    return null;
  }
};

export const decodeCrossChainTerminalEvent = (
  log: EVMLog
): CrossChainTerminalEvent | null => {
  const decoded = decodeReprieveEvent(log);
  if (!decoded) return null;

  if (decoded.eventName === "CrossChainCompleted") {
    return {
      execId: decoded.args.execId as Hex,
      messageId: decoded.args.ccipMessageId as Hex,
      status: "SUCCESS",
      amountReceived: decoded.args.amountReceived as bigint,
    };
  }

  if (decoded.eventName === "CrossChainDestinationFailed") {
    return {
      execId: decoded.args.execId as Hex,
      messageId: decoded.args.ccipMessageId as Hex,
      status: "FAILED",
      reason: decoded.args.reason as string,
    };
  }

  return null;
};
