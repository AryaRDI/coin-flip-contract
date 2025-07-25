# Smart Contracts

This directory contains the smart contracts for the Coin Flip game.

## Local Development Deployment

### Quick Start (Smart Deployment)

1. **Start Hardhat network**:
   ```bash
   docker-compose up hardhat
   ```

2. **Deploy contracts** (only need to do this once):
   ```bash
   # Deploy TreasuryCoinFlip (free games with token rewards)
   docker exec -it coinflip_hardhat pnpm run deploy:local
   
   # OR deploy CoinFlip (ETH betting with VRF)
   docker exec -it coinflip_hardhat pnpm run deploy:local:vrf
   ```

3. **Start the backend**:
   ```bash
   docker-compose up nestjs front
   ```

### How Smart Deployment Works

- ✅ **First time**: Deploys new contracts and saves addresses to `deployed-addresses.json`
- ✅ **Subsequent runs**: Checks if contracts exist, reuses them if they do
- ✅ **Auto-verification**: Calls contract functions to verify they're actually deployed
- ✅ **No re-deployment needed**: Contracts persist until you manually delete the deployment file

### Available Scripts

```bash
# Deploy TreasuryCoinFlip (smart - checks for existing)
pnpm run deploy:local

# Deploy CoinFlip VRF version (smart - checks for existing)
pnpm run deploy:local:vrf

# Check if contracts are deployed and working
pnpm run check:deployments

# Test the deployed contracts
pnpm run test:treasury
```

### Resetting Local Deployment

If you want to deploy fresh contracts:

```bash
# Remove the deployment file
rm deployed-addresses.json

# Deploy again
pnpm run deploy:local
```

## Production Networks

```bash
# Linea Testnet
pnpm run deploy:lineaTestnet

# Linea Mainnet  
pnpm run deploy:linea
```
