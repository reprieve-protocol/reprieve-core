export interface AdapterPosition {
  protocol: string;
  collateralAsset: string;
  debtAsset: string;
  collateralAmount: string;
  debtAmount: string;
  healthFactor: string;
  ltvBps: string;
  maxLtvBps: string;
  liquidationThresholdBps: string;
}

export interface AdapterReadResult {
  positions: AdapterPosition[];
}

export interface PositionSyncError {
  chainId: number;
  chainKey: string;
  protocol: string;
  adapterAddress: string;
  reason: string;
}
