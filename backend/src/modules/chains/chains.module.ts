import { Module } from '@nestjs/common';
import { ArtifactAddressLoaderService } from './artifact-address-loader.service';
import { ChainRegistryService } from './chain-registry.service';

@Module({
  providers: [ChainRegistryService, ArtifactAddressLoaderService],
  exports: [ChainRegistryService, ArtifactAddressLoaderService],
})
export class ChainsModule {}
