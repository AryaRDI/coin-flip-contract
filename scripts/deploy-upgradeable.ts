import { ethers, upgrades } from "hardhat";
import fs from "fs";

async function main() {
    console.log("🚀 Deploying Upgradeable TreasuryCoinFlip");
    console.log("========================================");
    
    const [deployer] = await ethers.getSigners();
    const network = await ethers.provider.getNetwork();
    
    console.log("👤 Deploying with account:", deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)));
    console.log("🌐 Network:", network.name, `(Chain ID: ${network.chainId})`);
    
    // Check if already deployed
    const deploymentFileName = `deployed-upgradeable-${network.name}.json`;
    let existingDeployment: any = {};
    
    try {
        if (fs.existsSync(deploymentFileName)) {
            existingDeployment = JSON.parse(fs.readFileSync(deploymentFileName, 'utf8'));
            
            if (existingDeployment.proxyAddress) {
                console.log(`✅ Upgradeable contract already deployed on ${network.name}:`);
                console.log(`   📋 Proxy: ${existingDeployment.proxyAddress}`);
                console.log(`   🔧 Implementation: ${existingDeployment.implementationAddress}`);
                console.log(`   🪙 Token: ${existingDeployment.tokenAddress}`);
                console.log(`   📅 Deployed: ${existingDeployment.deployedAt}`);
                
                // Verify the proxy is working
                try {
                    const contract = await ethers.getContractAt("TreasuryCoinFlipUpgradeable", existingDeployment.proxyAddress);
                    const version = await contract.version();
                    console.log(`   📝 Version: ${version}`);
                    
                    console.log("\n📋 Use this proxy address for your backend:");
                    console.log(`   EVM_COINFLIP_ADDRESS=${existingDeployment.proxyAddress}`);
                    return existingDeployment.proxyAddress;
                } catch (error) {
                    console.log("⚠️ Proxy verification failed - redeploying...");
                }
            }
        }
    } catch (error) {
        console.log("📄 No existing deployment found");
    }
    
    // Determine treasury address and token configuration
    const treasuryAddress = process.env.TREASURY_ADDRESS || deployer.address;
    let tokenAddress: string;
    
    const isLocalNetwork = network.name === "localhost" || network.name === "hardhat";
    const isTestNetwork = network.name === "lineaTestnet" || network.name === "sepolia";
    
    if (isLocalNetwork || isTestNetwork) {
        console.log(`\n🧪 ${isTestNetwork ? 'Testnet' : 'Local network'} detected - deploying mock token...`);
        
        // Deploy mock token for local/testnet testing
        const MockToken = await ethers.getContractFactory("MockToken");
        const mockToken = await MockToken.deploy();
        await mockToken.waitForDeployment();
        
        tokenAddress = await mockToken.getAddress();
        console.log("✅ Mock token deployed to:", tokenAddress);
        
    } else {
        // Use real token for production networks (Linea mainnet)
        tokenAddress = "0x38A67021bBe639caB6120c553719B5CFa60f3F18";
        console.log("🌐 Production network - using real token:", tokenAddress);
    }
    
    console.log("🏦 Treasury:", treasuryAddress);
    console.log("🪙 Token:", tokenAddress);
    
    // Deploy upgradeable contract using OpenZeppelin Upgrades plugin
    console.log("\n📦 Deploying upgradeable TreasuryCoinFlip contract...");
    
    const TreasuryCoinFlipUpgradeable = await ethers.getContractFactory("TreasuryCoinFlipUpgradeable");
    
    // Initialize parameters
    const rewardAmount = ethers.parseEther("40"); // 10 tokens
    const maxGamesPerDay = 4;
    
    console.log("⚙️ Initialization parameters:");
    console.log(`   🎁 Reward Amount: ${ethers.formatEther(rewardAmount)} tokens`);
    console.log(`   🎮 Max Games Per Day: ${maxGamesPerDay}`);
    
    // Deploy proxy with initialization
    const proxy = await upgrades.deployProxy(
        TreasuryCoinFlipUpgradeable,
        [tokenAddress, treasuryAddress, rewardAmount, maxGamesPerDay],
        { 
            initializer: 'initialize',
            kind: 'uups' // Use UUPS proxy pattern
        }
    );
    
    await proxy.waitForDeployment();
    
    const proxyAddress = await proxy.getAddress();
    console.log("✅ Proxy deployed to:", proxyAddress);
    
    // Get implementation address
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log("🔧 Implementation deployed to:", implementationAddress);
    
    // Get contract info
    console.log("\n📊 Contract Information:");
    try {
        const contractInfo = await proxy.getContractInfo();
        console.log("  - Token Address:", contractInfo[0]);
        console.log("  - Reward Amount:", ethers.formatEther(contractInfo[1]), "tokens");
        console.log("  - Current Balance:", ethers.formatEther(contractInfo[2]), "tokens");
        console.log("  - Min Treasury Balance:", ethers.formatEther(contractInfo[3]), "tokens");
        console.log("  - Treasury Wallet:", contractInfo[4]);
        
        const version = await proxy.version();
        console.log("  - Contract Version:", version);
    } catch (error) {
        console.log("  ❌ Error getting contract info:", (error as Error).message);
    }
    
    // For local/testnet: Set up treasury with tokens
    if (isLocalNetwork || isTestNetwork) {
        console.log("\n🔧 Setting up treasury with tokens...");
        try {
            const mockToken = await ethers.getContractAt("MockToken", tokenAddress);
            
            // Give treasury wallet some tokens (1000 tokens)
            const treasuryAmount = ethers.parseEther("1000");
            if (treasuryAddress !== deployer.address) {
                await mockToken.transfer(treasuryAddress, treasuryAmount);
                console.log(`✅ Transferred ${ethers.formatEther(treasuryAmount)} tokens to treasury`);
            }
            
            // Approve contract to spend tokens (from treasury wallet)
            let signer = deployer;
            if (treasuryAddress !== deployer.address) {
                // In real scenario, treasury wallet would need to do this
                console.log("⚠️ Treasury wallet needs to approve contract to spend tokens:");
                console.log(`   tokenContract.approve("${proxyAddress}", "1000000000000000000000000"); // 1M tokens`);
            } else {
                // Treasury is deployer, we can approve directly
                const approvalAmount = ethers.parseEther("1000000"); // 1M tokens
                await mockToken.approve(proxyAddress, approvalAmount);
                console.log(`✅ Approved ${ethers.formatEther(approvalAmount)} tokens for contract`);
                
                // Deposit some tokens to the contract treasury
                const depositAmount = ethers.parseEther("5000"); // 5000 tokens (500 games worth)
                await proxy.depositToTreasury(depositAmount);
                console.log(`✅ Deposited ${ethers.formatEther(depositAmount)} tokens to contract treasury`);
            }
        } catch (error) {
            console.log("⚠️ Treasury setup failed:", (error as Error).message);
        }
    }
    
    // Save deployment info
    const deploymentInfo = {
        proxyAddress: proxyAddress,
        implementationAddress: implementationAddress,
        tokenAddress: tokenAddress,
        treasuryAddress: treasuryAddress,
        deployer: deployer.address,
        deployedAt: new Date().toISOString(),
        network: network.name,
        chainId: network.chainId.toString(),
        rewardAmount: rewardAmount.toString(),
        maxGamesPerDay: maxGamesPerDay,
        version: "1.0.0"
    };
    
    fs.writeFileSync(deploymentFileName, JSON.stringify(deploymentInfo, null, 2));
    console.log(`📄 Deployment info saved to ${deploymentFileName}`);
    
    console.log("\n🎉 Deployment successful!");
    console.log("===============================");
    console.log("📋 Next steps for backend:");
    console.log(`   EVM_COINFLIP_ADDRESS=${proxyAddress}`);
    console.log(`   GAME_TOKEN_ADDRESS=${tokenAddress}`);
    
    if (network.name === "lineaTestnet") {
        console.log(`   EVM_RPC_URL=https://linea-sepolia.g.alchemy.com/v2/HwVNEcdMPyN4r2MKnaj2s`);
    } else if (network.name === "linea") {
        console.log(`   EVM_RPC_URL=https://linea-mainnet.g.alchemy.com/v2/HwVNEcdMPyN4r2MKnaj2s`);
    }
    
    console.log("\n🔧 Key Features:");
    console.log("✅ Upgradeable contract (UUPS proxy pattern)");
    console.log("✅ Treasury deposit/withdraw functions");
    console.log("✅ Daily game limits protection");
    console.log("✅ Authorized depositor system");
    console.log("✅ Minimum treasury balance protection");
    console.log("✅ Comprehensive admin controls");
    
    console.log("\n📖 Usage:");
    console.log("- Treasury deposits: call depositToTreasury(amount)");
    console.log("- Treasury withdraws: only owner can call withdrawFromTreasury()");
    console.log("- Upgrades: only owner can upgrade using upgrade script");
    console.log("- Game limits: configurable per-user daily limits");
    
    return proxyAddress;
}

if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

export { main as deployUpgradeable }; 