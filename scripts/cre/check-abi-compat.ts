const loadViem = async () => {
  try {
    return await import("viem");
  } catch {
    return await import("../../cre/reprieve-chainlink-api-guard-v1/node_modules/viem/index.ts");
  }
};

const concatSelectors = (selectors: string[]): `0x${string}` =>
  (`0x${selectors.map((s) => s.slice(2)).join("")}`) as `0x${string}`;

const assertUniqueSelectors = (label: string, selectors: string[]) => {
  const unique = new Set(selectors);
  if (unique.size !== selectors.length) {
    throw new Error(`${label} has selector collision`);
  }
};

const run = async () => {
  const {
    encodeFunctionData,
    keccak256,
    parseAbi,
    toBytes,
    toFunctionSelector,
  } = (await loadViem()) as any;

  const adapterSignatures = [
    "discoverPositions(address)",
    "healthFactor(address)",
    "availableCollateral(address,address)",
  ];

  const executorSignatures = [
    "executeRescue((bytes32,address,uint8,(uint256,address,address,address,address,uint256,uint256,bool,uint64)[],uint256,uint256))",
    "rescueInProgress(address)",
    "getRescueStatus(bytes32)",
    "getCcipMessageId(bytes32)",
  ];

  const rescueLogSignatures = ["getLogEntries(bytes32)"];

  const eventSignatures = [
    "RescueInitiated(bytes32,address,uint256,uint256)",
    "RescueCompleted(bytes32,address,uint8,uint256)",
    "RescueFailed(bytes32,address,string,uint256)",
    "CrossChainCompleted(bytes32,bytes32,uint256)",
    "CrossChainDestinationFailed(bytes32,bytes32,string)",
    "LogEntryAdded(bytes32,uint256,address,uint8,string)",
  ];

  const adapterSelectors = adapterSignatures.map((sig) => toFunctionSelector(sig));
  const executorSelectors = executorSignatures.map((sig) => toFunctionSelector(sig));
  const rescueLogSelectors = rescueLogSignatures.map((sig) => toFunctionSelector(sig));

  assertUniqueSelectors("Adapter", adapterSelectors);
  assertUniqueSelectors("Executor", executorSelectors);
  assertUniqueSelectors("RescueLog", rescueLogSelectors);

  console.log("Adapter selectors:", adapterSelectors.join(", "));
  console.log("Executor selectors:", executorSelectors.join(", "));
  console.log("RescueLog selectors:", rescueLogSelectors.join(", "));

  const adapterHash = keccak256(concatSelectors(adapterSelectors));
  const executorHash = keccak256(concatSelectors(executorSelectors));
  const rescueLogHash = keccak256(concatSelectors(rescueLogSelectors));

  console.log("Adapter selector-set hash:", adapterHash);
  console.log("Executor selector-set hash:", executorHash);
  console.log("RescueLog selector-set hash:", rescueLogHash);

  const executeRescueAbi = parseAbi([
    "function executeRescue((bytes32 execId,address user,uint8 mode,(uint256 stepIndex,address sourceAdapter,address targetAdapter,address collateralAsset,address debtAsset,uint256 collateralAmount,uint256 debtAmount,bool isCrossChain,uint64 targetChain)[] steps,uint256 deadline,uint256 maxFee) plan) returns (bool success)",
  ]);

  const samplePlan = {
    execId:
      "0x1111111111111111111111111111111111111111111111111111111111111111",
    user: "0x1111111111111111111111111111111111111111",
    mode: 0,
    steps: [
      {
        stepIndex: 0n,
        sourceAdapter: "0x2222222222222222222222222222222222222222",
        targetAdapter: "0x3333333333333333333333333333333333333333",
        collateralAsset: "0x4444444444444444444444444444444444444444",
        debtAsset: "0x5555555555555555555555555555555555555555",
        collateralAmount: 1000000000000000000n,
        debtAmount: 5000000n,
        isCrossChain: false,
        targetChain: 0,
      },
    ],
    deadline: 2000000000n,
    maxFee: 10000000000000000n,
  };

  const calldata = encodeFunctionData({
    abi: executeRescueAbi,
    functionName: "executeRescue",
    args: [samplePlan],
  });

  if (!calldata || calldata.length <= 10) {
    throw new Error("executeRescue calldata encode failed");
  }

  console.log("executeRescue calldata encode: OK");

  for (const signature of eventSignatures) {
    const topic = keccak256(toBytes(signature));
    console.log(`Event topic ${signature}: ${topic}`);
  }

  console.log("ABI compatibility checks passed.");
};

await run();
