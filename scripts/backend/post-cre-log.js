#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const EXEC_ID_REGEX = /^0x[a-fA-F0-9]{64}$/;

function readArg(args, flag) {
  const idx = args.indexOf(flag);
  if (idx === -1) return undefined;
  return args[idx + 1];
}

function printUsageAndExit(code) {
  const usage = `
Usage:
  node scripts/backend/post-cre-log.js --exec-id <0x...64hex> [options]

Options:
  --api-base <url>        API base URL (default: http://localhost:3001)
  --file <path>           Log file path (default: ./logs.txt)
  --workflow-id <id>      Optional workflow id
  --run-id <id>           Optional run id
  --metadata <json>       Optional metadata JSON string
  --dry-run               Print payload and URL without sending
  --help                  Show this help

Environment fallback:
  EXEC_ID
  API_BASE_URL
  LOG_FILE
  WORKFLOW_ID
  RUN_ID
  LOG_METADATA_JSON
`;
  process.stdout.write(usage);
  process.exit(code);
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes("--help")) {
    printUsageAndExit(0);
  }

  const repoRoot = path.resolve(__dirname, "..", "..");
  const execId = readArg(args, "--exec-id") || process.env.EXEC_ID || "";
  const apiBase = readArg(args, "--api-base") || process.env.API_BASE_URL || "http://localhost:3001";
  const logFile = readArg(args, "--file") || process.env.LOG_FILE || path.join(repoRoot, "logs.txt");
  const workflowId = readArg(args, "--workflow-id") || process.env.WORKFLOW_ID;
  const runId = readArg(args, "--run-id") || process.env.RUN_ID;
  const metadataRaw = readArg(args, "--metadata") || process.env.LOG_METADATA_JSON;
  const dryRun = args.includes("--dry-run");

  if (!EXEC_ID_REGEX.test(execId)) {
    process.stderr.write("Error: --exec-id (or EXEC_ID) must be a 0x-prefixed 64-hex string.\n");
    printUsageAndExit(1);
  }

  if (!fs.existsSync(logFile)) {
    process.stderr.write(`Error: log file not found: ${logFile}\n`);
    process.exit(1);
  }

  const logText = fs.readFileSync(logFile, "utf8");
  if (logText.trim().length === 0) {
    process.stderr.write(`Error: log file is empty: ${logFile}\n`);
    process.exit(1);
  }

  let metadata;
  if (metadataRaw && metadataRaw.trim().length > 0) {
    try {
      metadata = JSON.parse(metadataRaw);
      if (metadata === null || Array.isArray(metadata) || typeof metadata !== "object") {
        throw new Error("metadata must be a JSON object");
      }
    } catch (error) {
      process.stderr.write(`Error: invalid metadata JSON: ${error.message}\n`);
      process.exit(1);
    }
  }

  const payload = { logText };
  if (workflowId) payload.workflowId = workflowId;
  if (runId) payload.runId = runId;
  if (metadata) payload.metadata = metadata;

  const url = `${apiBase.replace(/\/+$/, "")}/v1/rescues/${execId}/cre-logs`;

  if (dryRun) {
    process.stdout.write(`DRY RUN\nPOST ${url}\n`);
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    return;
  }

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(payload),
  });

  const text = await response.text();
  if (!response.ok) {
    process.stderr.write(`Request failed (${response.status} ${response.statusText})\n`);
    process.stderr.write(`${text}\n`);
    process.exit(1);
  }

  process.stdout.write(`${text}\n`);
}

main().catch((error) => {
  process.stderr.write(`Unexpected error: ${error.message}\n`);
  process.exit(1);
});
