const { ethers } = require("hardhat");

async function main() {
  console.log("🔍 Checking Daily Limit Configuration");
  console.log("=====================================");

  // Get contract instance
  const contractAddress = process.env.DEPLOYED_CONTRACT_ADDRESS || "0xb85eA89cdAf87De277C6Fa385E48e1b70bd55CA3";
  
  try {
    const contract = await ethers.getContractAt("TreasuryCoinFlipUpgradeable", contractAddress);
    
    // Get network info
    const network = await ethers.provider.getNetwork();
    console.log("📊 Contract Address:", contractAddress);
    console.log("📟 Network:", network.name, "Chain ID:", network.chainId);
    
    // Check signers
    const signers = await ethers.getSigners();
    console.log("👤 Available Signers:", signers.length);
    if (signers.length > 0) {
      console.log("👤 Primary Signer:", signers[0].address);
    }
    
    // Check contract configuration
    console.log("\n⚙️ Contract Configuration:");
    
    const maxGamesPerDay = await contract.maxGamesPerDay();
    console.log("   Max Games Per Day:", maxGamesPerDay.toString());
    
    const contractStats = await contract.getContractStats();
    console.log("   Total Games Played:", contractStats[0].toString());
    console.log("   Total Rewards Distributed:", ethers.formatEther(contractStats[1]), "tokens");
    console.log("   Contract Is Paused:", contractStats[3]);
    
    const contractInfo = await contract.getContractInfo();
    console.log("   Token Address:", contractInfo[0]);
    console.log("   Reward Amount:", ethers.formatEther(contractInfo[1]), "tokens per game");
    console.log("   Treasury Balance:", ethers.formatEther(contractInfo[2]), "tokens");
    
    // Check daily limit for test user
    if (signers.length > 0) {
      const testUser = signers[0].address;
      console.log("\n📈 Test User Daily Stats:", testUser);
      
      const userStats = await contract.getUserDailyStats(testUser);
      console.log("   Games Played Today:", userStats[0].toString());
      console.log("   Max Games Allowed:", userStats[1].toString());
      console.log("   Remaining Games:", userStats[2].toString());
      console.log("   Next Reset Time:", new Date(Number(userStats[3]) * 1000).toISOString());
      
      // Check current day calculation
      const currentBlock = await ethers.provider.getBlock('latest');
      const currentDay = Math.floor(currentBlock.timestamp / (24 * 60 * 60));
      console.log("\n🕐 Time Information:");
      console.log("   Current Block Timestamp:", currentBlock.timestamp);
      console.log("   Current Day (contract calculation):", currentDay);
      console.log("   Current Time:", new Date(currentBlock.timestamp * 1000).toISOString());
      
      // Show raw daily count for debugging
      const today = Math.floor(currentBlock.timestamp / (24 * 60 * 60));
      const rawCount = await contract.dailyGamesCount(testUser, today);
      console.log("   Raw Daily Count for Today:", rawCount.toString());
    }
    
    console.log("\n✅ Configuration check completed!");
    
  } catch (error) {
    console.error("❌ Error checking configuration:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 