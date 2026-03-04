import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  Contract,
  JsonRpcProvider,
  MaxUint256,
  Wallet,
  formatUnits,
  getAddress,
  isAddress,
  isHexString,
  keccak256,
  parseEther,
  parseUnits,
  toUtf8Bytes,
} from 'ethers';
import { SupportedChainKey } from '../../config/chains.config';
import { ArtifactAddressLoaderService } from '../chains/artifact-address-loader.service';
import { ChainRegistryService } from '../chains/chain-registry.service';
import {
  DemoWalletBootstrapRunEntity,
  DemoWalletEntity,
  DemoWalletFundingRunEntity,
} from '../persistence/entities';
import {
  BootstrapDemoWalletDto,
  FundDemoWalletDto,
  RescueModeDto,
} from './demo-wallets.dto';

interface ChainContractsConfig {
  chainId?: number;
  contracts?: Record<string, string>;
  tokenParams?: {
    collateral?: { decimals?: number };
    debt?: { decimals?: number };
  };
}

interface ChainContext {
  key: SupportedChainKey;
  chainId: number;
  provider: JsonRpcProvider;
  ownerSigner: Wallet;
  contracts: Record<string, string>;
}

interface BootstrapPlan {
  rescueMode: RescueModeDto;
  weakPosition: 'ethereum-compound' | 'base-compound';
  aaveSourceSupplyWeth: string;
  ethCompoundCollateral: {
    asset: string;
    amountHuman: string;
  };
  ethCompoundBorrow: {
    asset: string;
    amountHuman: string;
    targetHf: string;
  };
  baseCompoundMarket: string;
  baseCompoundCollateral: {
    asset: string;
    amountHuman: string;
  };
  baseCompoundBorrow: {
    asset: string;
    amountHuman: string;
    targetHf: string;
  };
  orientation: 'same-direction' | 'opposite-direction';
}

const ERC20_ABI = [
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function balanceOf(address) view returns (uint256)',
  'function allowance(address,address) view returns (uint256)',
  'function approve(address,uint256) returns (bool)',
  'function mint(address,uint256)',
] as const;

const ORACLE_ABI = [
  'function getPrice(address) view returns (uint256 price, uint256 updatedAt)',
] as const;

const AAVE_POOL_ABI = [
  'function aToken() view returns (address)',
  'function getUserPosition(address user) view returns ((uint256 collateral,uint256 debt,uint256 ltvBps,uint256 liquidationThresholdBps))',
  'function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)',
] as const;

const COMPOUND_MARKET_ABI = [
  'function collateral() view returns (address)',
  'function debt() view returns (address)',
  'function engine() view returns (address)',
  'function mint(address asset, uint256 amount)',
  'function borrow(address asset, uint256 amount)',
] as const;

const LENDING_ENGINE_ABI = [
  'function getUserPosition(address user) view returns ((uint256 collateral,uint256 debt,uint256 ltvBps,uint256 liquidationThresholdBps))',
  'function maxBorrowAmount(address user, uint256 price) view returns (uint256 maxBorrow)',
] as const;

const TX_GAS_LIMITS = {
  tokenMint: 250_000n,
  erc20Approve: 120_000n,
  aaveSupply: 600_000n,
  compoundMint: 700_000n,
  compoundBorrow: 700_000n,
  nativeFund: 50_000n,
} as const;

const DEMO_NATIVE_FAUCET_CAPS = {
  'ethereum-sepolia': parseEther('0.0001'),
  'base-sepolia': parseEther('0.00001'),
} as const;

@Injectable()
export class DemoWalletsService {
  private readonly logger = new Logger(DemoWalletsService.name);
  private readonly tokenDecimalsCache = new Map<string, number>();

  constructor(
    private readonly configService: ConfigService,
    private readonly chainRegistryService: ChainRegistryService,
    private readonly artifactAddressLoaderService: ArtifactAddressLoaderService,
    @InjectRepository(DemoWalletEntity)
    private readonly demoWalletRepository: Repository<DemoWalletEntity>,
    @InjectRepository(DemoWalletFundingRunEntity)
    private readonly demoWalletFundingRunRepository: Repository<DemoWalletFundingRunEntity>,
    @InjectRepository(DemoWalletBootstrapRunEntity)
    private readonly demoWalletBootstrapRunRepository: Repository<DemoWalletBootstrapRunEntity>,
  ) {}

  async generateDemoWallet(realUserAddress: string): Promise<Record<string, unknown>> {
    const normalizedRealUserAddress = this.normalizeAddressLower(realUserAddress);

    const existing = await this.demoWalletRepository.findOne({
      where: { realUserAddress: normalizedRealUserAddress },
    });
    if (existing) {
      return {
        created: false,
        realUserAddress: existing.realUserAddress,
        demoWalletAddress: getAddress(existing.demoWalletAddress),
        derivationVersion: existing.derivationVersion,
      };
    }

    const privateKey = this.deriveDemoPrivateKey(normalizedRealUserAddress);
    const wallet = new Wallet(privateKey);
    const demoWalletAddress = this.normalizeAddressLower(wallet.address);
    const encryptedPrivateKey = this.encryptPrivateKey(privateKey);

    const saved = await this.demoWalletRepository.save({
      realUserAddress: normalizedRealUserAddress,
      demoWalletAddress,
      encryptedPrivateKey,
      derivationVersion: 'v1',
      nativeFundedEthSepoliaWei: '0',
      nativeFundedBaseSepoliaWei: '0',
      updatedAt: new Date(),
    });

    return {
      created: true,
      realUserAddress: saved.realUserAddress,
      demoWalletAddress: getAddress(saved.demoWalletAddress),
      derivationVersion: saved.derivationVersion,
    };
  }

  async fundDemoWallet(
    demoWalletAddressInput: string,
    dto: FundDemoWalletDto,
  ): Promise<Record<string, unknown>> {
    const demoWalletAddress = this.normalizeAddressLower(demoWalletAddressInput);
    const demoWallet = await this.demoWalletRepository.findOne({
      where: { demoWalletAddress },
    });
    if (!demoWallet) {
      throw new NotFoundException(`Demo wallet not found: ${demoWalletAddressInput}`);
    }

    const run = await this.demoWalletFundingRunRepository.save({
      demoWalletId: demoWallet.id,
      status: 'running',
      requestPayload: {
        ethereumSepoliaGasEth:
          dto.ethereumSepoliaGasEth ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_ETH_SEPOLIA_GAS_ETH', '0.0001'),
        baseSepoliaGasEth:
          dto.baseSepoliaGasEth ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_BASE_SEPOLIA_GAS_ETH', '0.0001'),
        ethereumSepoliaWethTarget:
          dto.ethereumSepoliaWethTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_ETH_WETH', '80'),
        ethereumSepoliaUsdcTarget:
          dto.ethereumSepoliaUsdcTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_ETH_USDC', '90000'),
        baseSepoliaWethTarget:
          dto.baseSepoliaWethTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_BASE_WETH', '50'),
        baseSepoliaUsdcTarget:
          dto.baseSepoliaUsdcTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_BASE_USDC', '90000'),
      },
      resultPayload: {},
      errorMessage: null,
      updatedAt: new Date(),
    });

    try {
      const ethContext = this.loadChainContext('ethereum-sepolia');
      const baseContext = this.loadChainContext('base-sepolia');

      const ethCollateral = this.requireAddress(
        ethContext.contracts.MockERC20_Collateral,
        'ethereum-sepolia MockERC20_Collateral',
      );
      const ethDebt = this.requireAddress(
        ethContext.contracts.MockERC20_Debt,
        'ethereum-sepolia MockERC20_Debt',
      );
      const baseCollateral = this.requireAddress(
        baseContext.contracts.MockERC20_Collateral,
        'base-sepolia MockERC20_Collateral',
      );
      const baseDebt = this.requireAddress(
        baseContext.contracts.MockERC20_Debt,
        'base-sepolia MockERC20_Debt',
      );

      const targetEthGas = parseEther(
        dto.ethereumSepoliaGasEth ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_ETH_SEPOLIA_GAS_ETH', '0.0001'),
      );
      const targetBaseGas = parseEther(
        dto.baseSepoliaGasEth ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_BASE_SEPOLIA_GAS_ETH', '0.0001'),
      );

      const ethWethDecimals = await this.getTokenDecimals(ethContext, ethCollateral);
      const ethUsdcDecimals = await this.getTokenDecimals(ethContext, ethDebt);
      const baseWethDecimals = await this.getTokenDecimals(baseContext, baseCollateral);
      const baseUsdcDecimals = await this.getTokenDecimals(baseContext, baseDebt);

      const targetEthWeth = parseUnits(
        dto.ethereumSepoliaWethTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_ETH_WETH', '80'),
        ethWethDecimals,
      );
      const targetEthUsdc = parseUnits(
        dto.ethereumSepoliaUsdcTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_ETH_USDC', '90000'),
        ethUsdcDecimals,
      );
      const targetBaseWeth = parseUnits(
        dto.baseSepoliaWethTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_BASE_WETH', '50'),
        baseWethDecimals,
      );
      const targetBaseUsdc = parseUnits(
        dto.baseSepoliaUsdcTarget ??
          this.configService.get<string>('DEMO_WALLET_DEFAULT_BASE_USDC', '90000'),
        baseUsdcDecimals,
      );

      const operations: Array<Record<string, unknown>> = [];
      let fundedEthSepoliaWei = this.parseBigIntOrZero(
        demoWallet.nativeFundedEthSepoliaWei,
      );
      let fundedBaseSepoliaWei = this.parseBigIntOrZero(
        demoWallet.nativeFundedBaseSepoliaWei,
      );

      await this.ensureTokenBalance(
        ethContext,
        ethCollateral,
        demoWalletAddress,
        targetEthWeth,
        operations,
        'ethereum-sepolia-WETH',
      );
      await this.ensureTokenBalance(
        ethContext,
        ethDebt,
        demoWalletAddress,
        targetEthUsdc,
        operations,
        'ethereum-sepolia-USDC',
      );
      await this.ensureTokenBalance(
        baseContext,
        baseCollateral,
        demoWalletAddress,
        targetBaseWeth,
        operations,
        'base-sepolia-WETH',
      );
      await this.ensureTokenBalance(
        baseContext,
        baseDebt,
        demoWalletAddress,
        targetBaseUsdc,
        operations,
        'base-sepolia-USDC',
      );

      const fundedEthDelta = await this.ensureNativeBalance(
        ethContext,
        demoWalletAddress,
        targetEthGas,
        operations,
        'ethereum-sepolia',
        fundedEthSepoliaWei,
        this.getNativeFundingCap('ethereum-sepolia'),
      );
      fundedEthSepoliaWei += fundedEthDelta;

      const fundedBaseDelta = await this.ensureNativeBalance(
        baseContext,
        demoWalletAddress,
        targetBaseGas,
        operations,
        'base-sepolia',
        fundedBaseSepoliaWei,
        this.getNativeFundingCap('base-sepolia'),
      );
      fundedBaseSepoliaWei += fundedBaseDelta;

      await this.demoWalletRepository.update(demoWallet.id, {
        nativeFundedEthSepoliaWei: fundedEthSepoliaWei.toString(),
        nativeFundedBaseSepoliaWei: fundedBaseSepoliaWei.toString(),
        updatedAt: new Date(),
      });

      const resultPayload = {
        demoWalletAddress: getAddress(demoWalletAddress),
        operationCount: operations.length,
        nativeFundingCapsWei: {
          ethereumSepolia: this.getNativeFundingCap('ethereum-sepolia').toString(),
          baseSepolia: this.getNativeFundingCap('base-sepolia').toString(),
        },
        nativeFundingTotalsWei: {
          ethereumSepolia: fundedEthSepoliaWei.toString(),
          baseSepolia: fundedBaseSepoliaWei.toString(),
        },
        operations,
      };

      await this.demoWalletFundingRunRepository.update(run.id, {
        status: 'success',
        resultPayload,
        errorMessage: null,
        updatedAt: new Date(),
      });

      return {
        runId: run.id,
        status: 'success',
        ...resultPayload,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.demoWalletFundingRunRepository.update(run.id, {
        status: 'failed',
        errorMessage: message,
        updatedAt: new Date(),
      });
      throw new BadRequestException(message);
    }
  }

  async bootstrapPositions(
    demoWalletAddressInput: string,
    dto: BootstrapDemoWalletDto,
  ): Promise<Record<string, unknown>> {
    const demoWalletAddress = this.normalizeAddressLower(demoWalletAddressInput);
    const demoWallet = await this.demoWalletRepository.findOne({
      where: { demoWalletAddress },
    });
    if (!demoWallet) {
      throw new NotFoundException(`Demo wallet not found: ${demoWalletAddressInput}`);
    }

    const rescueMode = dto.rescueMode;
    const existingSuccessfulRun = await this.demoWalletBootstrapRunRepository.findOne({
      where: {
        demoWalletId: demoWallet.id,
        rescueMode,
        status: 'success',
      },
      order: { id: 'DESC' },
    });
    if (existingSuccessfulRun && !dto.force) {
      return {
        runId: existingSuccessfulRun.id,
        status: 'success',
        reused: true,
        rescueMode,
        result: existingSuccessfulRun.resultPayload,
      };
    }

    const run = await this.demoWalletBootstrapRunRepository.save({
      demoWalletId: demoWallet.id,
      rescueMode,
      status: 'running',
      requestPayload: {
        rescueMode,
        force: Boolean(dto.force),
        minBorrowUsd: dto.minBorrowUsd ?? 1000,
      },
      resultPayload: {},
      errorMessage: null,
      updatedAt: new Date(),
    });

    try {
      const ethContext = this.loadChainContext('ethereum-sepolia');
      const baseContext = this.loadChainContext('base-sepolia');
      const demoPrivateKey = this.decryptPrivateKey(demoWallet.encryptedPrivateKey);

      const ethDemoSigner = new Wallet(demoPrivateKey, ethContext.provider);
      const baseDemoSigner = new Wallet(demoPrivateKey, baseContext.provider);
      if (
        this.normalizeAddressLower(ethDemoSigner.address) !== demoWalletAddress ||
        this.normalizeAddressLower(baseDemoSigner.address) !== demoWalletAddress
      ) {
        throw new Error('Stored demo wallet key does not match requested demo wallet address');
      }

      const plan = await this.buildBootstrapPlan(
        rescueMode,
        ethContext,
        baseContext,
        dto.minBorrowUsd ?? 1000,
      );

      const txs: Array<Record<string, unknown>> = [];

      const ethAavePool = this.requireAddress(
        ethContext.contracts.MockAavePool,
        'ethereum-sepolia MockAavePool',
      );
      const aaveSupplyRaw = parseUnits(
        plan.aaveSourceSupplyWeth,
        await this.getTokenDecimals(ethContext, plan.ethCompoundCollateral.asset),
      );
      const aavePool = new Contract(ethAavePool, AAVE_POOL_ABI, ethDemoSigner);
      const userPosition = (await aavePool.getUserPosition(demoWalletAddress)) as
        | { collateral?: bigint }
        | Array<bigint>;
      const existingAaveCollateralRaw = BigInt(
        (userPosition as { collateral?: bigint })?.collateral ??
          (Array.isArray(userPosition) ? userPosition[0] : 0n) ??
          0n,
      );
      const aaveSupplyDeltaRaw =
        existingAaveCollateralRaw >= aaveSupplyRaw
          ? 0n
          : aaveSupplyRaw - existingAaveCollateralRaw;

      if (aaveSupplyDeltaRaw > 0n) {
        const walletFreeCollateral = await this.getTokenBalance(
          ethContext,
          plan.ethCompoundCollateral.asset,
          demoWalletAddress,
        );
        const executableAaveSupply = walletFreeCollateral >= aaveSupplyDeltaRaw ? aaveSupplyDeltaRaw : walletFreeCollateral;
        if (executableAaveSupply < aaveSupplyDeltaRaw) {
          txs.push({
            step: 'aave-supply-eth-balance-check',
            chain: 'ethereum-sepolia',
            adjusted: true,
            reason: 'insufficient free token balance for requested supply delta',
            requestedRaw: aaveSupplyDeltaRaw.toString(),
            executableRaw: executableAaveSupply.toString(),
            freeBalanceRaw: walletFreeCollateral.toString(),
          });
        }
        if (executableAaveSupply === 0n) {
          txs.push({
            step: 'aave-supply-eth',
            chain: 'ethereum-sepolia',
            skipped: true,
            reason: 'no free collateral balance available',
            existingCollateralRaw: existingAaveCollateralRaw.toString(),
            targetCollateralRaw: aaveSupplyRaw.toString(),
          });
        } else {
        await this.ensureApproval(
          ethContext,
          plan.ethCompoundCollateral.asset,
          ethDemoSigner,
          ethAavePool,
          executableAaveSupply,
          txs,
          'approve-aave-eth',
        );
        const aaveSupplyTx = await aavePool.supply(
          plan.ethCompoundCollateral.asset,
          executableAaveSupply,
          demoWalletAddress,
          0,
          {
            gasLimit: TX_GAS_LIMITS.aaveSupply,
          },
        );
        const aaveSupplyReceipt = await aaveSupplyTx.wait();
        txs.push({
          step: 'aave-supply-eth',
          chain: 'ethereum-sepolia',
          txHash: aaveSupplyTx.hash,
          blockNumber: String(aaveSupplyReceipt?.blockNumber ?? 0),
          suppliedRaw: executableAaveSupply.toString(),
          existingCollateralRaw: existingAaveCollateralRaw.toString(),
          targetCollateralRaw: aaveSupplyRaw.toString(),
        });
        }
      } else {
        txs.push({
          step: 'aave-supply-eth',
          chain: 'ethereum-sepolia',
          skipped: true,
          reason: 'existing collateral already satisfies target',
          existingCollateralRaw: existingAaveCollateralRaw.toString(),
          targetCollateralRaw: aaveSupplyRaw.toString(),
        });
      }

      const ethAaveAdapter = this.requireAddress(
        ethContext.contracts.AaveLikeAdapter,
        'ethereum-sepolia AaveLikeAdapter',
      );
      const aTokenAddress = this.normalizeAddressLower(String(await aavePool.aToken()));
      const aTokenApprovalRequired =
        existingAaveCollateralRaw + aaveSupplyDeltaRaw > 0n
          ? existingAaveCollateralRaw + aaveSupplyDeltaRaw
          : aaveSupplyRaw;
      await this.ensureApproval(
        ethContext,
        aTokenAddress,
        ethDemoSigner,
        ethAaveAdapter,
        aTokenApprovalRequired,
        txs,
        'approve-aave-atoken-to-adapter',
      );

      const ethCompoundMarketAddress = this.requireAddress(
        ethContext.contracts.MockCompoundComet,
        'ethereum-sepolia MockCompoundComet',
      );
      await this.executeCompoundPositionStep(
        ethContext,
        ethDemoSigner,
        ethCompoundMarketAddress,
        plan.ethCompoundCollateral.asset,
        plan.ethCompoundCollateral.amountHuman,
        plan.ethCompoundBorrow.asset,
        plan.ethCompoundBorrow.amountHuman,
        txs,
        'compound-eth',
      );

      await this.executeCompoundPositionStep(
        baseContext,
        baseDemoSigner,
        plan.baseCompoundMarket,
        plan.baseCompoundCollateral.asset,
        plan.baseCompoundCollateral.amountHuman,
        plan.baseCompoundBorrow.asset,
        plan.baseCompoundBorrow.amountHuman,
        txs,
        'compound-base',
      );

      const resultPayload = {
        demoWalletAddress: getAddress(demoWalletAddress),
        rescueMode,
        orientation: plan.orientation,
        weakPosition: plan.weakPosition,
        plan,
        txs,
      };
      await this.demoWalletBootstrapRunRepository.update(run.id, {
        status: 'success',
        resultPayload,
        errorMessage: null,
        updatedAt: new Date(),
      });

      return {
        runId: run.id,
        status: 'success',
        reused: false,
        ...resultPayload,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.demoWalletBootstrapRunRepository.update(run.id, {
        status: 'failed',
        errorMessage: message,
        updatedAt: new Date(),
      });
      throw new BadRequestException(message);
    }
  }

  private async buildBootstrapPlan(
    rescueMode: RescueModeDto,
    ethContext: ChainContext,
    baseContext: ChainContext,
    minBorrowUsd: number,
  ): Promise<BootstrapPlan> {
    const ethWeth = this.requireAddress(
      ethContext.contracts.MockERC20_Collateral,
      'ethereum-sepolia MockERC20_Collateral',
    );
    const ethUsdc = this.requireAddress(
      ethContext.contracts.MockERC20_Debt,
      'ethereum-sepolia MockERC20_Debt',
    );
    const baseWeth = this.requireAddress(
      baseContext.contracts.MockERC20_Collateral,
      'base-sepolia MockERC20_Collateral',
    );
    const baseUsdc = this.requireAddress(
      baseContext.contracts.MockERC20_Debt,
      'base-sepolia MockERC20_Debt',
    );

    const ethWethPriceUsd = await this.getOraclePriceUsd(ethContext, ethWeth);
    const ethUsdcPriceUsd = await this.getOraclePriceUsd(ethContext, ethUsdc);
    const baseWethPriceUsd = await this.getOraclePriceUsd(baseContext, baseWeth);
    const baseUsdcPriceUsd = await this.getOraclePriceUsd(baseContext, baseUsdc);

    const aaveSupplyWeth = this.randomHuman(45, 75, 4);
    const ethCollWeth = this.randomHuman(9, 16, 4);
    const ethTargetHf = this.randomHuman(1.35, 1.75, 4);
    const ethDebtUsdc = this.computeDebtHuman(
      ethCollWeth,
      ethWethPriceUsd,
      ethTargetHf,
      ethUsdcPriceUsd,
    );

    if (Number(ethDebtUsdc) < minBorrowUsd) {
      throw new Error(
        `Computed Ethereum compound borrow below minimum threshold: ${ethDebtUsdc} < ${String(
          minBorrowUsd,
        )}`,
      );
    }

    if (rescueMode === RescueModeDto.TOP_UP) {
      const baseTargetHf = this.randomHuman(1.04, 1.12, 4);
      const baseCollWeth = this.randomHuman(7, 13, 4);
      const baseDebtUsdc = this.computeDebtHuman(
        baseCollWeth,
        baseWethPriceUsd,
        baseTargetHf,
        baseUsdcPriceUsd,
      );
      if (Number(baseDebtUsdc) < minBorrowUsd) {
        throw new Error(
          `Computed Base compound borrow below minimum threshold: ${baseDebtUsdc} < ${String(
            minBorrowUsd,
          )}`,
        );
      }

      const baseMarket = this.requireAddress(
        baseContext.contracts.MockCompoundComet,
        'base-sepolia MockCompoundComet',
      );

      return {
        rescueMode,
        weakPosition: 'base-compound',
        aaveSourceSupplyWeth: aaveSupplyWeth,
        ethCompoundCollateral: { asset: ethWeth, amountHuman: ethCollWeth },
        ethCompoundBorrow: {
          asset: ethUsdc,
          amountHuman: ethDebtUsdc,
          targetHf: ethTargetHf,
        },
        baseCompoundMarket: baseMarket,
        baseCompoundCollateral: { asset: baseWeth, amountHuman: baseCollWeth },
        baseCompoundBorrow: {
          asset: baseUsdc,
          amountHuman: baseDebtUsdc,
          targetHf: baseTargetHf,
        },
        orientation: 'same-direction',
      };
    }

    const repayBaseMarket = this.resolveRepayBaseCompoundMarketAddress();
    const market = new Contract(repayBaseMarket, COMPOUND_MARKET_ABI, baseContext.provider);
    const marketCollateralAsset = this.normalizeAddressLower(
      String(await market.collateral()),
    );
    const marketDebtAsset = this.normalizeAddressLower(String(await market.debt()));
    if (marketCollateralAsset !== baseUsdc || marketDebtAsset !== baseWeth) {
      throw new Error(
        `Repay market is not opposite-direction (expected collateral=${baseUsdc} debt=${baseWeth}, got collateral=${marketCollateralAsset} debt=${marketDebtAsset})`,
      );
    }

    const baseTargetHf = this.randomHuman(1.04, 1.12, 4);
    const baseCollUsdc = this.randomHuman(15000, 28000, 2);
    const baseDebtWeth = this.computeDebtHuman(
      baseCollUsdc,
      baseUsdcPriceUsd,
      baseTargetHf,
      baseWethPriceUsd,
    );

    if (Number(baseCollUsdc) < minBorrowUsd) {
      throw new Error(
        `Computed Base repay collateral below minimum threshold: ${baseCollUsdc} < ${String(
          minBorrowUsd,
        )}`,
      );
    }

    return {
      rescueMode,
      weakPosition: 'base-compound',
      aaveSourceSupplyWeth: aaveSupplyWeth,
      ethCompoundCollateral: { asset: ethWeth, amountHuman: ethCollWeth },
      ethCompoundBorrow: {
        asset: ethUsdc,
        amountHuman: ethDebtUsdc,
        targetHf: ethTargetHf,
      },
      baseCompoundMarket: repayBaseMarket,
      baseCompoundCollateral: {
        asset: marketCollateralAsset,
        amountHuman: baseCollUsdc,
      },
      baseCompoundBorrow: {
        asset: marketDebtAsset,
        amountHuman: baseDebtWeth,
        targetHf: baseTargetHf,
      },
      orientation: 'opposite-direction',
    };
  }

  private async executeCompoundPositionStep(
    chainContext: ChainContext,
    demoSigner: Wallet,
    marketAddress: string,
    collateralAsset: string,
    collateralAmountHuman: string,
    borrowAsset: string,
    borrowAmountHuman: string,
    txs: Array<Record<string, unknown>>,
    stepLabel: string,
  ): Promise<void> {
    const market = new Contract(marketAddress, COMPOUND_MARKET_ABI, demoSigner);
    const collateralDecimals = await this.getTokenDecimals(chainContext, collateralAsset);
    const debtDecimals = await this.getTokenDecimals(chainContext, borrowAsset);

    const collateralAmountRaw = parseUnits(collateralAmountHuman, collateralDecimals);
    const debtAmountRaw = parseUnits(borrowAmountHuman, debtDecimals);

    const engineAddress = this.normalizeAddressLower(String(await market.engine()));
    const engine = new Contract(engineAddress, LENDING_ENGINE_ABI, chainContext.provider);
    const currentPosition = (await engine.getUserPosition(demoSigner.address)) as
      | { collateral?: bigint; debt?: bigint }
      | Array<bigint>;
    const existingCollateralRaw = BigInt(
      (currentPosition as { collateral?: bigint })?.collateral ??
        (Array.isArray(currentPosition) ? currentPosition[0] : 0n) ??
        0n,
    );
    const wantedMintDelta =
      existingCollateralRaw >= collateralAmountRaw
        ? 0n
        : collateralAmountRaw - existingCollateralRaw;
    const walletFreeCollateralRaw = await this.getTokenBalance(
      chainContext,
      collateralAsset,
      demoSigner.address,
    );
    const mintDeltaRaw =
      walletFreeCollateralRaw >= wantedMintDelta
        ? wantedMintDelta
        : walletFreeCollateralRaw;
    if (mintDeltaRaw < wantedMintDelta) {
      txs.push({
        step: `${stepLabel}-mint-balance-check`,
        chain: chainContext.key,
        adjusted: true,
        reason: 'insufficient free token balance for requested mint delta',
        requestedRaw: wantedMintDelta.toString(),
        executableRaw: mintDeltaRaw.toString(),
        freeBalanceRaw: walletFreeCollateralRaw.toString(),
      });
    }

    await this.ensureApproval(
      chainContext,
      collateralAsset,
      demoSigner,
      marketAddress,
      mintDeltaRaw,
      txs,
      `${stepLabel}-approve`,
    );
    if (mintDeltaRaw > 0n) {
      try {
        const mintTx = await market.mint(collateralAsset, mintDeltaRaw, {
          gasLimit: TX_GAS_LIMITS.compoundMint,
        });
        const mintReceipt = await mintTx.wait();
        txs.push({
          step: `${stepLabel}-mint`,
          chain: chainContext.key,
          txHash: mintTx.hash,
          blockNumber: String(mintReceipt?.blockNumber ?? 0),
          collateralAsset: getAddress(collateralAsset),
          collateralAmountRaw: mintDeltaRaw.toString(),
          existingCollateralRaw: existingCollateralRaw.toString(),
          targetCollateralRaw: collateralAmountRaw.toString(),
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(
          `${stepLabel} mint failed on ${chainContext.key}: ${message}`,
        );
      }
    } else {
      txs.push({
        step: `${stepLabel}-mint`,
        chain: chainContext.key,
        skipped: true,
        reason: 'existing collateral already satisfies target or no free balance',
        existingCollateralRaw: existingCollateralRaw.toString(),
        targetCollateralRaw: collateralAmountRaw.toString(),
      });
    }

    const postMintPosition = (await engine.getUserPosition(demoSigner.address)) as
      | { collateral?: bigint; debt?: bigint }
      | Array<bigint>;
    const postMintDebtRaw = BigInt(
      (postMintPosition as { debt?: bigint })?.debt ??
        (Array.isArray(postMintPosition) ? postMintPosition[1] : 0n) ??
        0n,
    );
    const wantedBorrowDeltaRaw =
      postMintDebtRaw >= debtAmountRaw ? 0n : debtAmountRaw - postMintDebtRaw;

    const oracleAddress = this.requireAddress(
      chainContext.contracts.MockPriceOracle,
      `${chainContext.key} MockPriceOracle`,
    );
    const oracle = new Contract(oracleAddress, ORACLE_ABI, chainContext.provider);
    const collateralPrice = ((await oracle.getPrice(collateralAsset)) as [bigint, bigint])[0];
    const maxBorrowAllowedRaw = (await engine.maxBorrowAmount(
      demoSigner.address,
      collateralPrice,
    )) as bigint;
    const borrowDeltaRaw =
      maxBorrowAllowedRaw >= wantedBorrowDeltaRaw
        ? wantedBorrowDeltaRaw
        : maxBorrowAllowedRaw;
    if (borrowDeltaRaw < wantedBorrowDeltaRaw) {
      txs.push({
        step: `${stepLabel}-borrow-cap-check`,
        chain: chainContext.key,
        adjusted: true,
        reason: 'borrow capped by current maxBorrowAmount',
        requestedRaw: wantedBorrowDeltaRaw.toString(),
        executableRaw: borrowDeltaRaw.toString(),
        maxBorrowRaw: maxBorrowAllowedRaw.toString(),
      });
    }

    await this.ensureCompoundDebtLiquidity(
      chainContext,
      marketAddress,
      borrowAsset,
      borrowDeltaRaw,
      txs,
      `${stepLabel}-debt-liquidity`,
    );

    if (borrowDeltaRaw > 0n) {
      try {
        const borrowTx = await market.borrow(borrowAsset, borrowDeltaRaw, {
          gasLimit: TX_GAS_LIMITS.compoundBorrow,
        });
        const borrowReceipt = await borrowTx.wait();
        txs.push({
          step: `${stepLabel}-borrow`,
          chain: chainContext.key,
          txHash: borrowTx.hash,
          blockNumber: String(borrowReceipt?.blockNumber ?? 0),
          debtAsset: getAddress(borrowAsset),
          debtAmountRaw: borrowDeltaRaw.toString(),
          existingDebtRaw: postMintDebtRaw.toString(),
          targetDebtRaw: debtAmountRaw.toString(),
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(
          `${stepLabel} borrow failed on ${chainContext.key}: ${message}`,
        );
      }
    } else {
      txs.push({
        step: `${stepLabel}-borrow`,
        chain: chainContext.key,
        skipped: true,
        reason: 'existing debt already satisfies target or maxBorrowAmount is zero',
        existingDebtRaw: postMintDebtRaw.toString(),
        targetDebtRaw: debtAmountRaw.toString(),
      });
    }
  }

  private async ensureCompoundDebtLiquidity(
    chainContext: ChainContext,
    marketAddress: string,
    debtAsset: string,
    requiredDebtAmount: bigint,
    txs: Array<Record<string, unknown>>,
    stepLabel: string,
  ): Promise<void> {
    const market = new Contract(marketAddress, COMPOUND_MARKET_ABI, chainContext.provider);
    const engineAddress = this.normalizeAddressLower(String(await market.engine()));
    const debtToken = new Contract(debtAsset, ERC20_ABI, chainContext.ownerSigner);

    const current = (await debtToken.balanceOf(engineAddress)) as bigint;
    if (current >= requiredDebtAmount) {
      return;
    }

    const delta = requiredDebtAmount - current;
    const mintTx = await debtToken.mint(engineAddress, delta, {
      gasLimit: TX_GAS_LIMITS.tokenMint,
    });
    const mintReceipt = await mintTx.wait();
    txs.push({
      step: stepLabel,
      chain: chainContext.key,
      txHash: mintTx.hash,
      blockNumber: String(mintReceipt?.blockNumber ?? 0),
      engine: getAddress(engineAddress),
      mintedRaw: delta.toString(),
      asset: getAddress(debtAsset),
    });
  }

  private async ensureApproval(
    chainContext: ChainContext,
    tokenAddress: string,
    tokenOwnerSigner: Wallet,
    spender: string,
    requiredAmount: bigint,
    txs: Array<Record<string, unknown>>,
    stepLabel: string,
  ): Promise<void> {
    const tokenRead = new Contract(tokenAddress, ERC20_ABI, chainContext.provider);
    const allowance = (await tokenRead.allowance(
      tokenOwnerSigner.address,
      spender,
    )) as bigint;
    if (allowance >= requiredAmount) {
      return;
    }

    const signerToken = new Contract(tokenAddress, ERC20_ABI, tokenOwnerSigner);
    const approveTx = await signerToken.approve(spender, MaxUint256, {
      gasLimit: TX_GAS_LIMITS.erc20Approve,
    });
    const receipt = await approveTx.wait();
    txs.push({
      step: stepLabel,
      chain: chainContext.key,
      txHash: approveTx.hash,
      blockNumber: String(receipt?.blockNumber ?? 0),
      token: getAddress(tokenAddress),
      spender: getAddress(spender),
      approved: 'MAX_UINT256',
    });
  }

  private async ensureTokenBalance(
    chainContext: ChainContext,
    tokenAddress: string,
    walletAddress: string,
    targetBalance: bigint,
    operations: Array<Record<string, unknown>>,
    label: string,
  ): Promise<void> {
    if (targetBalance <= 0n) {
      return;
    }

    const token = new Contract(tokenAddress, ERC20_ABI, chainContext.ownerSigner);
    const currentBalance = (await token.balanceOf(walletAddress)) as bigint;
    if (currentBalance >= targetBalance) {
      operations.push({
        type: 'mint',
        label,
        chain: chainContext.key,
        token: getAddress(tokenAddress),
        action: 'skipped',
        currentBalanceRaw: currentBalance.toString(),
        targetBalanceRaw: targetBalance.toString(),
      });
      return;
    }

    const amountToMint = targetBalance - currentBalance;
    const tx = await token.mint(walletAddress, amountToMint, {
      gasLimit: TX_GAS_LIMITS.tokenMint,
    });
    const receipt = await tx.wait();
    operations.push({
      type: 'mint',
      label,
      chain: chainContext.key,
      token: getAddress(tokenAddress),
      action: 'minted',
      txHash: tx.hash,
      blockNumber: String(receipt?.blockNumber ?? 0),
      mintedAmountRaw: amountToMint.toString(),
      targetBalanceRaw: targetBalance.toString(),
    });
  }

  private async ensureNativeBalance(
    chainContext: ChainContext,
    walletAddress: string,
    targetBalance: bigint,
    operations: Array<Record<string, unknown>>,
    label: string,
    alreadyFundedWei: bigint,
    fundingCapWei: bigint,
  ): Promise<bigint> {
    if (targetBalance <= 0n) {
      return 0n;
    }

    const current = await chainContext.provider.getBalance(walletAddress);
    const remainingFaucetAllowanceWei =
      alreadyFundedWei >= fundingCapWei ? 0n : fundingCapWei - alreadyFundedWei;
    if (current >= targetBalance) {
      operations.push({
        type: 'native-fund',
        label,
        chain: chainContext.key,
        action: 'skipped',
        currentBalanceWei: current.toString(),
        targetBalanceWei: targetBalance.toString(),
        faucetRemainingWei: remainingFaucetAllowanceWei.toString(),
      });
      return 0n;
    }

    if (remainingFaucetAllowanceWei === 0n) {
      operations.push({
        type: 'native-fund',
        label,
        chain: chainContext.key,
        action: 'blocked',
        reason: 'faucet cap reached for this demo wallet',
        currentBalanceWei: current.toString(),
        targetBalanceWei: targetBalance.toString(),
        alreadyFundedWei: alreadyFundedWei.toString(),
        faucetCapWei: fundingCapWei.toString(),
      });
      return 0n;
    }

    const deltaNeededWei = targetBalance - current;
    const delta =
      deltaNeededWei > remainingFaucetAllowanceWei
        ? remainingFaucetAllowanceWei
        : deltaNeededWei;
    const adjustedByCap = delta < deltaNeededWei;
    const tx = await chainContext.ownerSigner.sendTransaction({
      to: walletAddress,
      value: delta,
      gasLimit: TX_GAS_LIMITS.nativeFund,
    });
    const receipt = await tx.wait();
    operations.push({
      type: 'native-fund',
      label,
      chain: chainContext.key,
      action: 'funded',
      txHash: tx.hash,
      blockNumber: String(receipt?.blockNumber ?? 0),
      fundedWei: delta.toString(),
      requestedWei: deltaNeededWei.toString(),
      adjustedByCap,
      faucetRemainingBeforeWei: remainingFaucetAllowanceWei.toString(),
      targetBalanceWei: targetBalance.toString(),
    });
    return delta;
  }

  private async getTokenDecimals(
    chainContext: ChainContext,
    tokenAddress: string,
  ): Promise<number> {
    const key = `${chainContext.chainId}:${this.normalizeAddressLower(tokenAddress)}`;
    const cached = this.tokenDecimalsCache.get(key);
    if (cached !== undefined) {
      return cached;
    }

    const token = new Contract(tokenAddress, ERC20_ABI, chainContext.provider);
    const decimals = Number(await token.decimals());
    this.tokenDecimalsCache.set(key, decimals);
    return decimals;
  }

  private async getTokenBalance(
    chainContext: ChainContext,
    tokenAddress: string,
    holder: string,
  ): Promise<bigint> {
    const token = new Contract(tokenAddress, ERC20_ABI, chainContext.provider);
    return (await token.balanceOf(holder)) as bigint;
  }

  private async getOraclePriceUsd(
    chainContext: ChainContext,
    asset: string,
  ): Promise<number> {
    const oracleAddress = this.requireAddress(
      chainContext.contracts.MockPriceOracle,
      `${chainContext.key} MockPriceOracle`,
    );
    const oracle = new Contract(oracleAddress, ORACLE_ABI, chainContext.provider);
    const response = (await oracle.getPrice(asset)) as [bigint, bigint];
    const priceWad = response?.[0] ?? 0n;
    if (priceWad <= 0n) {
      throw new Error(
        `Oracle returned non-positive price for ${asset} on ${chainContext.key}`,
      );
    }
    return Number(formatUnits(priceWad, 18));
  }

  private computeDebtHuman(
    collateralAmountHuman: string,
    collateralPriceUsd: number,
    targetHf: string,
    debtPriceUsd: number,
  ): string {
    const collateral = Number(collateralAmountHuman);
    const hf = Number(targetHf);
    const debtPrice = Number(debtPriceUsd);
    const collateralPrice = Number(collateralPriceUsd);

    if (
      !Number.isFinite(collateral) ||
      !Number.isFinite(hf) ||
      !Number.isFinite(debtPrice) ||
      !Number.isFinite(collateralPrice) ||
      collateral <= 0 ||
      hf <= 1 ||
      debtPrice <= 0 ||
      collateralPrice <= 0
    ) {
      throw new Error('Invalid values while computing debt amount');
    }

    const effectiveCollateralUsd = collateral * collateralPrice * 0.8;
    const debtAmountHuman = effectiveCollateralUsd / (hf * debtPrice);
    return debtAmountHuman.toFixed(6).replace(/\.?0+$/, '');
  }

  private randomHuman(min: number, max: number, decimals: number): string {
    if (max <= min) {
      throw new Error(`Invalid random range: min=${String(min)} max=${String(max)}`);
    }
    const factor = 10 ** decimals;
    const minScaled = Math.floor(min * factor);
    const maxScaled = Math.floor(max * factor);
    const sampled = crypto.randomInt(minScaled, maxScaled + 1);
    return (sampled / factor).toFixed(decimals).replace(/\.?0+$/, '');
  }

  private loadChainContext(chainKey: SupportedChainKey): ChainContext {
    const chain = this.chainRegistryService.getByKey(chainKey);
    const provider = new JsonRpcProvider(chain.rpcUrl);
    const ownerPrivateKey = this.resolveChainPrivateKey(chainKey);
    const ownerSigner = new Wallet(ownerPrivateKey, provider);

    const configPath = this.artifactAddressLoaderService.getConfigPath(chainKey);
    const parsed = JSON.parse(fs.readFileSync(configPath, 'utf8')) as ChainContractsConfig;
    const contracts = parsed.contracts ?? {};

    return {
      key: chainKey,
      chainId: chain.chainId,
      provider,
      ownerSigner,
      contracts,
    };
  }

  private resolveRepayBaseCompoundMarketAddress(): string {
    const envOverride = this.configService.get<string>('DEMO_REPAY_BASE_COMPOUND_MARKET', '');
    if (envOverride && isAddress(envOverride)) {
      return this.normalizeAddressLower(envOverride);
    }

    const contractsConfigDir = this.configService.get<string>(
      'CONTRACTS_CONFIG_DIR',
      '../contracts/config',
    );
    const filePath = path.resolve(
      process.cwd(),
      contractsConfigDir,
      'cross-chain-rescue-destination-84532.json',
    );
    if (!fs.existsSync(filePath)) {
      throw new Error(
        `Missing repay market config. Set DEMO_REPAY_BASE_COMPOUND_MARKET or create ${filePath}`,
      );
    }

    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8')) as {
      target?: { targetMarket?: string };
    };
    const marketAddress = parsed?.target?.targetMarket;
    if (!marketAddress || !isAddress(marketAddress)) {
      throw new Error(
        `Invalid target.targetMarket in ${filePath}; set DEMO_REPAY_BASE_COMPOUND_MARKET`,
      );
    }
    return this.normalizeAddressLower(marketAddress);
  }

  private requireAddress(value: string | undefined, label: string): string {
    if (!value || !isAddress(value)) {
      throw new Error(`Invalid address for ${label}`);
    }
    return this.normalizeAddressLower(value);
  }

  private resolveChainPrivateKey(chainKey: SupportedChainKey): string {
    const chainSpecificKey =
      chainKey === 'ethereum-sepolia'
        ? this.configService.get<string>('ETHEREUM_SEPOLIA_PRIVATE_KEY')
        : this.configService.get<string>('BASE_SEPOLIA_PRIVATE_KEY');

    const raw = chainSpecificKey ?? this.configService.get<string>('PRIVATE_KEY') ?? '';
    if (!raw || raw.trim().length === 0) {
      throw new Error(`Missing owner private key for ${chainKey}`);
    }

    const normalized = raw.startsWith('0x') ? raw : `0x${raw}`;
    if (!isHexString(normalized, 32)) {
      throw new Error(`Invalid owner private key for ${chainKey}`);
    }
    return normalized;
  }

  private deriveDemoPrivateKey(realUserAddress: string): string {
    const masterSecret = this.configService.get<string>('DEMO_WALLET_MASTER_SECRET', '');
    if (!masterSecret || masterSecret.trim().length < 16) {
      throw new Error(
        'DEMO_WALLET_MASTER_SECRET must be set and at least 16 characters long',
      );
    }

    for (let counter = 0; counter < 16; counter += 1) {
      const digest = keccak256(
        toUtf8Bytes(`${masterSecret}:${realUserAddress}:${String(counter)}`),
      );
      try {
        const wallet = new Wallet(digest);
        if (wallet.address) {
          return digest;
        }
      } catch {
        // continue searching for valid key material
      }
    }

    throw new Error('Unable to derive a valid deterministic demo wallet private key');
  }

  private encryptPrivateKey(privateKey: string): string {
    const key = this.resolveEncryptionKey();
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const encrypted = Buffer.concat([
      cipher.update(Buffer.from(privateKey, 'utf8')),
      cipher.final(),
    ]);
    const authTag = cipher.getAuthTag();
    return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted.toString('hex')}`;
  }

  private decryptPrivateKey(ciphertext: string): string {
    const key = this.resolveEncryptionKey();
    const [ivHex, tagHex, dataHex] = ciphertext.split(':');
    if (!ivHex || !tagHex || !dataHex) {
      throw new Error('Malformed encrypted private key payload');
    }

    const iv = Buffer.from(ivHex, 'hex');
    const authTag = Buffer.from(tagHex, 'hex');
    const encrypted = Buffer.from(dataHex, 'hex');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(authTag);
    const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
    const privateKey = decrypted.toString('utf8');
    if (!isHexString(privateKey, 32)) {
      throw new Error('Decrypted demo private key is invalid');
    }
    return privateKey;
  }

  private resolveEncryptionKey(): Buffer {
    const raw = this.configService.get<string>('DEMO_WALLET_ENCRYPTION_KEY', '').trim();
    if (!raw) {
      throw new Error('DEMO_WALLET_ENCRYPTION_KEY must be set for demo wallet operations');
    }

    if (raw.startsWith('0x') && raw.length === 66) {
      return Buffer.from(raw.slice(2), 'hex');
    }
    return crypto.createHash('sha256').update(raw, 'utf8').digest();
  }

  private normalizeAddressLower(address: string): string {
    if (!isAddress(address)) {
      throw new BadRequestException(`Invalid EVM address: ${address}`);
    }
    return getAddress(address).toLowerCase();
  }

  private getNativeFundingCap(chainKey: SupportedChainKey): bigint {
    return DEMO_NATIVE_FAUCET_CAPS[chainKey];
  }

  private parseBigIntOrZero(value: string | null | undefined): bigint {
    if (!value || value.trim().length === 0) {
      return 0n;
    }
    try {
      return BigInt(value);
    } catch {
      return 0n;
    }
  }
}
