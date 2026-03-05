import { ConfigService } from '@nestjs/config';
import * as fs from 'node:fs';
import * as path from 'node:path';

const DEFAULT_CONFIG_DIR_CANDIDATES = ['./contracts-config', '/app/contracts-config'];

function toAbsolutePath(inputPath: string): string {
  return path.isAbsolute(inputPath)
    ? path.normalize(inputPath)
    : path.resolve(process.cwd(), inputPath);
}

export function resolveContractsConfigFilePath(
  configService: ConfigService,
  fileName: string,
  explicitFileOverride?: string,
): string {
  const checkedPaths: string[] = [];

  const override = explicitFileOverride?.trim();
  if (override && override.length > 0) {
    const overridePath = toAbsolutePath(override);
    checkedPaths.push(overridePath);
    if (fs.existsSync(overridePath)) {
      return overridePath;
    }
  }

  const configuredBaseDir = configService
    .get<string>('CONTRACTS_CONFIG_DIR', './contracts-config')
    ?.trim();

  const candidateBaseDirs = Array.from(
    new Set(
      [configuredBaseDir, ...DEFAULT_CONFIG_DIR_CANDIDATES].filter(
        (value): value is string => Boolean(value && value.length > 0),
      ),
    ),
  );

  for (const baseDir of candidateBaseDirs) {
    const candidatePath = toAbsolutePath(path.join(baseDir, fileName));
    checkedPaths.push(candidatePath);
    if (fs.existsSync(candidatePath)) {
      return candidatePath;
    }
  }

  throw new Error(
    `Contracts config file "${fileName}" not found. Checked: ${checkedPaths.join(', ')}`,
  );
}
