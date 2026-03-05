import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  SUPPORTED_CHAIN_KEYS,
  SupportedChainKey,
} from '../../config/chains.config';

@Injectable()
export class ArtifactAddressLoaderService {
  constructor(private readonly configService: ConfigService) {}

  getConfigPath(chainKey: SupportedChainKey): string {
    const envPrefix = chainKey.toUpperCase().replace(/-/g, '_');
    const override = this.configService.get<string>(`${envPrefix}_CONFIG_PATH`);
    if (override && override.trim().length > 0) {
      return path.resolve(process.cwd(), override);
    }

    const baseDir = this.configService.get<string>(
      'CONTRACTS_CONFIG_DIR',
      './contracts-config',
    );

    return path.resolve(process.cwd(), baseDir, `${chainKey}.json`);
  }

  loadChainArtifacts(chainKey: SupportedChainKey): Record<string, string> {
    if (!SUPPORTED_CHAIN_KEYS.includes(chainKey)) {
      throw new NotFoundException(`Unsupported chain key: ${chainKey}`);
    }

    const filePath = this.getConfigPath(chainKey);
    if (!fs.existsSync(filePath)) {
      throw new NotFoundException(`Artifact config not found at ${filePath}`);
    }

    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8')) as Record<
      string,
      unknown
    >;

    const output: Record<string, string> = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value === 'string' && value.startsWith('0x')) {
        output[key] = value;
      }
    }

    return output;
  }

  getAddress(chainKey: SupportedChainKey, artifactKey: string): string {
    const envKey = `${chainKey.toUpperCase().replace(/-/g, '_')}_${artifactKey
      .replace(/[^a-zA-Z0-9]/g, '_')
      .toUpperCase()}`;

    const override = this.configService.get<string>(envKey);
    if (override && override.trim().length > 0) {
      return override;
    }

    const artifacts = this.loadChainArtifacts(chainKey);
    const value = artifacts[artifactKey];

    if (!value) {
      throw new NotFoundException(
        `Address not found for key ${artifactKey} on ${chainKey}`,
      );
    }

    return value;
  }
}
