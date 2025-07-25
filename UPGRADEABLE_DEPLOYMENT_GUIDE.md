# Upgradeable TreasuryCoinFlip Deployment Guide

## 🎯 Overview
This guide covers deploying and managing the upgradeable treasury-based coin flip system using OpenZeppelin proxy patterns. The system allows contract upgrades while preserving state and treasury funds.

## 🏗️ Architecture

### Proxy Pattern (UUPS)
- **Proxy Contract**: Fixed address that never changes - this is what your frontend/backend uses
- **Implementation Contract**: Contains the logic, can be upgraded
- **State**: All treasury balances, game data, and configurations stay in the proxy

### Key Benefits
- ✅ **Same address forever** - no need to update frontend/backend after upgrades
- ✅ **Preserve treasury funds** - all balances and state remain during upgrades
- ✅ **Add new features** - upgrade logic without losing existing data
- ✅ **Enhanced security** - only owner can upgrade, with proper authorization

## 📋 Prerequisites

1. **Install Dependencies**
   ```bash
   pnpm install
   ```

2. **Environment Setup**
   ```bash
   cp env.example .env
   # Edit .env with your values
   ```

## 🚀 Initial Deployment

### Step 1: Deploy Upgradeable Contract

```bash
# Local development
pnpm run deploy:local:proxy

# Linea Testnet 
pnpm run deploy:lineaTestnet:proxy

# Linea Mainnet
pnpm run deploy:linea:proxy
```

### Step 2: Save the Proxy Address

The deployment will output:
```
✅ Proxy deployed to: 0xYourProxyAddress
🔧 Implementation deployed to: 0xYourImplementationAddress

📋 Next steps for backend:
   EVM_COINFLIP_ADDRESS=0xYourProxyAddress
```

**Important**: Always use the **proxy address** in your backend, never the implementation address!

### Step 3: Update Backend Configuration

Update your backend environment variables:
```env
EVM_COINFLIP_ADDRESS=0xYourProxyAddress
GAME_TOKEN_ADDRESS=0xYourTokenAddress
```

## 🔄 Upgrading the Contract

### When to Upgrade
- Adding new features
- Fixing bugs
- Improving security
- Optimizing gas usage

### How to Upgrade

1. **Modify the Contract**
   - Edit `contracts/TreasuryCoinFlipUpgradeable.sol`
   - Update the `version()` function to track changes

2. **Run Upgrade Script**
   ```bash
   # Local
   pnpm run upgrade:local
   
   # Testnet
   pnpm run upgrade:lineaTestnet
   
   # Mainnet
   pnpm run upgrade:linea
   ```

3. **Verify Upgrade**
   The script will:
   - Deploy new implementation
   - Update proxy to point to new implementation
   - Test basic functionality
   - **Proxy address stays the same!**

### Upgrade Safety Rules

✅ **Safe to add:**
- New state variables (at the end)
- New functions
- New events
- New modifiers

❌ **Never change:**
- Order of existing state variables
- Type of existing state variables
- Function signatures that are used

## 🏦 Treasury Management

### Safe Deposit Functions

```solidity
// Authorized depositors can deposit tokens
function depositToTreasury(uint256 amount) external;

// Check if address can deposit
function authorizedDepositors(address depositor) external view returns (bool);
```

### Safe Withdraw Functions

```solidity
// Only owner can withdraw (with minimum balance protection)
function withdrawFromTreasury(address to, uint256 amount) external onlyOwner;

// Emergency withdraw (owner only, no restrictions)
function emergencyWithdraw(address to, uint256 amount) external onlyOwner;

// Check if amount can be safely withdrawn
function canWithdrawAmount(uint256 amount) external view returns (bool);
```

### Treasury Safety Features

1. **Minimum Balance Protection**
   - Contract maintains minimum treasury balance
   - Prevents draining below operational requirements

2. **Authorized Depositors**
   - Only approved addresses can deposit
   - Treasury wallet is automatically authorized

3. **Owner-Only Withdrawals**
   - Only contract owner can withdraw
   - Emergency functions for critical situations

## 🛡️ Security Features

### Access Control
- **Owner**: Can upgrade, withdraw, pause, and configure
- **Authorized Depositors**: Can deposit to treasury
- **Players**: Can play games within daily limits

### Daily Limits
```solidity
// Check user's remaining games today
function getRemainingGames(address user) external view returns (uint256);

// Get detailed daily stats
function getUserDailyStats(address user) external view returns (
    uint256 gamesPlayedToday,
    uint256 maxGames,
    uint256 remainingGames,
    uint256 nextResetTime
);
```

### Circuit Breakers
- **Pausable**: Owner can pause all game activity
- **Treasury Balance Check**: Games blocked if insufficient treasury
- **Reentrancy Protection**: Prevents reentrancy attacks

## 📊 Monitoring & Analytics

### Contract Statistics
```solidity
function getContractStats() external view returns (
    uint256 totalGames,
    uint256 totalRewards,
    uint256 currentMaxGamesPerDay,
    bool isPaused
);
```

### Treasury Information
```solidity
function getContractInfo() external view returns (
    address tokenAddress,
    uint256 currentRewardAmount,
    uint256 treasuryBalance,
    uint256 minBalance,
    address treasury
);
```

## 🔧 Administrative Functions

### Configuration Updates
```bash
# Update reward amount (owner only)
contract.setRewardAmount(newAmount);

# Update daily game limits (owner only)
contract.setMaxGamesPerDay(newLimit);

# Update minimum treasury balance (owner only)
contract.setMinTreasuryBalance(newMinBalance);

# Authorize/deauthorize depositors (owner only)
contract.authorizeDepositor(depositorAddress, true/false);
```

### Emergency Controls
```bash
# Pause all game activity
contract.pause();

# Resume game activity
contract.unpause();

# Emergency token withdrawal
contract.emergencyWithdraw(recipientAddress, amount);
```

## 🧪 Testing Upgrades

### Local Testing Process

1. **Deploy initial version**
   ```bash
   pnpm run deploy:local:proxy
   ```

2. **Play some games to create state**
   ```bash
   pnpm run test:treasury
   ```

3. **Modify contract and upgrade**
   ```bash
   # Edit TreasuryCoinFlipUpgradeable.sol
   pnpm run upgrade:local
   ```

4. **Verify state preservation**
   - Treasury balance unchanged
   - Game history preserved
   - New functions available

## 📁 File Structure

```
contracts-evm/
├── contracts/
│   ├── TreasuryCoinFlipUpgradeable.sol  # Main upgradeable contract
│   ├── TreasuryCoinFlip.sol            # Original contract (for reference)
│   └── MockToken.sol                   # Test token
├── scripts/
│   ├── deploy-upgradeable.ts           # Initial proxy deployment
│   ├── upgrade.ts                      # Upgrade script
│   └── test-treasury-game.js           # Testing script
└── deployed-upgradeable-{network}.json # Deployment tracking
```

## 🚨 Troubleshooting

### Common Issues

1. **"caller is not the owner"**
   - Only contract owner can upgrade
   - Ensure you're using the deployer account

2. **"insufficient treasury balance"**
   - Treasury needs more tokens
   - Use `depositToTreasury()` or check balance

3. **"proxy admin error"**
   - UUPS proxy issue
   - Verify contract inherits UUPSUpgradeable

### Verification Commands

```bash
# Check current contract version
contract.version()

# Check if upgrade is needed
# Compare local code with deployed version

# Verify proxy is working
contract.getContractInfo()
```

## 🌐 Network-Specific Information

### Linea Mainnet
- **Chain ID**: 59144
- **RPC**: https://linea-mainnet.g.alchemy.com/v2/HwVNEcdMPyN4r2MKnaj2s
- **Token**: 0x38A67021bBe639caB6120c553719B5CFa60f3F18

### Linea Testnet (Sepolia)
- **Chain ID**: 59141
- **RPC**: https://linea-sepolia.g.alchemy.com/v2/HwVNEcdMPyN4r2MKnaj2s
- **Token**: Deployed mock token

## 📝 Best Practices

1. **Always test upgrades on testnet first**
2. **Verify state preservation after upgrades**
3. **Monitor treasury balance regularly**
4. **Use timelock for production upgrades**
5. **Keep deployment files backed up**
6. **Document all contract changes**

## 🎉 Summary

You now have a fully upgradeable treasury coin flip contract with:

- ✅ **Proxy pattern** for seamless upgrades
- ✅ **Treasury management** with safety controls
- ✅ **Daily limits** for player protection
- ✅ **Comprehensive admin controls**
- ✅ **Emergency functions** for critical situations
- ✅ **State preservation** across upgrades

The proxy address never changes, so your frontend and backend will continue working through all future upgrades! 