import { readFileSync } from "node:fs";
import {
  parseProfileWorkflowConfig,
  type StrategyId,
} from "../../cre/reprieve-common/types";

type ProfileTarget = {
  strategyId: StrategyId;
  stagingPath: string;
  productionPath: string;
};

const ROOT = "/Users/sniperman/code/reprieve";

const targets: ProfileTarget[] = [
  {
    strategyId: "CHAINLINK_API_GUARD_V1",
    stagingPath: `${ROOT}/cre/reprieve-chainlink-api-guard-v1/config.staging.json`,
    productionPath: `${ROOT}/cre/reprieve-chainlink-api-guard-v1/config.production.json`,
  },
  {
    strategyId: "QUANT_FUNDING_OI_V1",
    stagingPath: `${ROOT}/cre/reprieve-quant-funding-oi-v1/config.staging.json`,
    productionPath: `${ROOT}/cre/reprieve-quant-funding-oi-v1/config.production.json`,
  },
  {
    strategyId: "QUANT_BASIS_LIQUIDITY_V1",
    stagingPath: `${ROOT}/cre/reprieve-quant-basis-liquidity-v1/config.staging.json`,
    productionPath: `${ROOT}/cre/reprieve-quant-basis-liquidity-v1/config.production.json`,
  },
];

const loadJson = (path: string): unknown => JSON.parse(readFileSync(path, "utf8"));

const expectThrows = (label: string, fn: () => void): void => {
  try {
    fn();
    throw new Error(`Expected failure did not occur: ${label}`);
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("Expected failure did not occur")) {
      throw error;
    }
    console.log(`✓ Expected failure: ${label}`);
  }
};

const deepClone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

const run = (): void => {
  console.log("Validating profile configs...");

  for (const target of targets) {
    const stagingRaw = loadJson(target.stagingPath);
    const productionRaw = loadJson(target.productionPath);

    const staging = parseProfileWorkflowConfig(stagingRaw, target.strategyId);
    const production = parseProfileWorkflowConfig(productionRaw, target.strategyId);

    console.log(
      `✓ ${target.strategyId} staging/production valid (version ${staging.workflowVersion})`
    );

    if (staging.strategyId !== production.strategyId) {
      throw new Error(`Profile mismatch between staging and production for ${target.strategyId}`);
    }
  }

  const chainlink = loadJson(targets[0].stagingPath) as Record<string, unknown>;
  const funding = loadJson(targets[1].stagingPath) as Record<string, unknown>;
  const basis = loadJson(targets[2].stagingPath) as Record<string, unknown>;

  const missingChainlinkUrl = deepClone(chainlink) as any;
  delete missingChainlinkUrl.dataSources.chainlinkApi.priceApiBaseUrl;
  expectThrows("CHAINLINK_API_GUARD_V1 missing chainlinkApi.priceApiBaseUrl", () => {
    parseProfileWorkflowConfig(missingChainlinkUrl, "CHAINLINK_API_GUARD_V1");
  });

  const badFundingWeights = deepClone(funding) as any;
  badFundingWeights.dataSources.quantFundingOi.fundingWeightBps = 2000;
  expectThrows("QUANT_FUNDING_OI_V1 invalid weight sum", () => {
    parseProfileWorkflowConfig(badFundingWeights, "QUANT_FUNDING_OI_V1");
  });

  const missingBasisSource = deepClone(basis) as any;
  delete missingBasisSource.dataSources.quantBasisLiquidity;
  expectThrows("QUANT_BASIS_LIQUIDITY_V1 missing quantBasisLiquidity source", () => {
    parseProfileWorkflowConfig(missingBasisSource, "QUANT_BASIS_LIQUIDITY_V1");
  });

  expectThrows("Profile identity mismatch rejected", () => {
    parseProfileWorkflowConfig(chainlink, "QUANT_FUNDING_OI_V1");
  });

  console.log("All Slide 1 config validations passed.");
};

run();
