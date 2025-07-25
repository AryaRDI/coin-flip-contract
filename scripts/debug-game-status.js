const { ethers } = require("hardhat");

// === CONFIG ===
const GAME_ID = process.env.GAME_ID || "0x9e62173babfa37fb004e8b6155b9ea22e45aab1464c559db2553730edca90b34";
const CONTRACT_ADDRESS = process.env.DEPLOYED_CONTRACT_ADDRESS || "0x1159fed833f27530D5AC855247c196b280202235";

async function main() {
  console.log("\uD83D\uDD0E Debugging Game Status");
  console.log("============================\n");
  console.log("Game ID:", GAME_ID);
  console.log("Contract:", CONTRACT_ADDRESS);

  const contract = await ethers.getContractAt("TreasuryCoinFlipUpgradeable", CONTRACT_ADDRESS);

  // 1. Fetch game info
  try {
    const gameInfo = await contract.getGameInfo(GAME_ID);
    console.log("\n\uD83D\uDCCB Game Info:");
    console.log("  Creator:", gameInfo.creator);
    console.log("  Joiner:", gameInfo.joiner);
    console.log("  Creator Side:", gameInfo.creatorSide ? "TAILS" : "HEADS");
    console.log("  Is Active:", gameInfo.isActive);
    console.log("  Is Joinable:", gameInfo.isJoinable);
    console.log("  Is Resolved:", gameInfo.resolved);
    console.log("  Block Number:", gameInfo.blockNumber?.toString?.() || gameInfo.blockNumber);
    if (gameInfo.resolved) {
      console.log("  Winner:", gameInfo.winner);
      console.log("  Coin Result:", gameInfo.coinResult ? "TAILS" : "HEADS");
    }
  } catch (err) {
    console.log("❌ Error fetching game info:", err.message);
  }

  // 2. Contract paused status
  try {
    const paused = await contract.paused();
    console.log("\n⏸ Contract Paused:", paused);
  } catch (err) {
    console.log("❌ Error fetching paused status:", err.message);
  }

  // 3. Treasury balance
  try {
    const treasuryBalance = await contract.getTreasuryBalance();
    console.log("\n💰 Treasury Balance:", ethers.formatEther(treasuryBalance), "tokens");
  } catch (err) {
    console.log("❌ Error fetching treasury balance:", err.message);
  }

  // 4. Print daily stats for creator and joiner
  try {
    const gameInfo = await contract.getGameInfo(GAME_ID);
    const addresses = [gameInfo.creator, gameInfo.joiner].filter(Boolean);
    for (const addr of addresses) {
      const stats = await contract.getUserDailyStats(addr);
      console.log(`\n\uD83D\uDCCA Daily Stats for ${addr}:`);
      console.log("  Games Played Today:", stats[0].toString());
      console.log("  Max Games Allowed:", stats[1].toString());
      console.log("  Remaining Games:", stats[2].toString());
      console.log("  Next Reset Time:", new Date(Number(stats[3]) * 1000).toISOString());
    }
  } catch (err) {
    console.log("❌ Error fetching user daily stats:", err.message);
  }

  // 5. Print recent events for this game ID
  try {
    const currentBlock = await ethers.provider.getBlockNumber();
    const fromBlock = Math.max(0, currentBlock - 499);
    const filters = [
      contract.filters.GameCreated(GAME_ID),
      contract.filters.GameJoined(GAME_ID),
      contract.filters.GameResolved(GAME_ID),
      contract.filters.GameCancelled(GAME_ID)
    ];
    for (const filter of filters) {
      const events = await contract.queryFilter(filter, fromBlock, currentBlock);
      for (const event of events) {
        console.log(`\n\uD83D\uDCE2 Event: ${event.event}`);
        console.log("  Block:", event.blockNumber);
        console.log("  Tx Hash:", event.transactionHash);
        console.log("  Args:", event.args);
      }
    }
  } catch (err) {
    console.log("❌ Error fetching events:", err.message);
  }

  // 6. Check if a specific wallet can play
  const WALLET_TO_CHECK = process.env.WALLET_TO_CHECK || "0x0c55eC220e2244dF545a54722672f8A4aD867BaD";
  try {
    const stats = await contract.getUserDailyStats(WALLET_TO_CHECK);
    const canPlay = stats[2] > 0n;
    console.log(`\n\uD83D\uDD11 Wallet ${WALLET_TO_CHECK} can play today:`, canPlay ? "✅ YES" : "❌ NO");
    console.log("  Games Played Today:", stats[0].toString());
    console.log("  Max Games Allowed:", stats[1].toString());
    console.log("  Remaining Games:", stats[2].toString());
    console.log("  Next Reset Time:", new Date(Number(stats[3]) * 1000).toISOString());
  } catch (err) {
    console.log(`❌ Error checking wallet ${WALLET_TO_CHECK} stats:`, err.message);
  }

  // 7. Simulate joinGame to debug 'Game not active' error
  try {
    const signers = await ethers.getSigners();
    const joiner = signers[1] || signers[0];
    console.log(`\n\uD83D\uDD27 Simulating joinGame as: ${joiner.address}`);
    // Print game state before
    const before = await contract.getGameInfo(GAME_ID);
    console.log("  [Before] isActive:", before.isActive, "isJoinable:", before.isJoinable, "resolved:", before.resolved);
    try {
      // ethers v6: use staticCall
      const tx = await contract.connect(joiner).joinGame.staticCall(GAME_ID);
      console.log("  ✅ joinGame simulation succeeded!", tx);
    } catch (err) {
      let reason = err.message || String(err);
      // Try to extract revert reason
      if (err.error && err.error.body) {
        try {
          const body = JSON.parse(err.error.body);
          reason = body.error && body.error.message ? body.error.message : reason;
        } catch {}
      }
      console.log("  ❌ joinGame simulation reverted:", reason);
    }
    // Print game state after
    const after = await contract.getGameInfo(GAME_ID);
    console.log("  [After] isActive:", after.isActive, "isJoinable:", after.isJoinable, "resolved:", after.resolved);
  } catch (err) {
    console.log("❌ Error simulating joinGame:", err.message);
  }

  // 8. Actually send joinGame transaction
//   try {
//     const signers = await ethers.getSigners();
//     const joiner = signers[1] || signers[0];
//     console.log(`\n🚀 Sending joinGame transaction as: ${joiner.address}`);
//     const tx = await contract.connect(joiner).joinGame(GAME_ID);
//     console.log("  ⏳ Waiting for confirmation... Tx Hash:", tx.hash);
//     const receipt = await tx.wait();
//     console.log("  ✅ Successfully joined the game! Block:", receipt.blockNumber);
//   } catch (err) {
//     let reason = err.message || String(err);
//     if (err.error && err.error.body) {
//       try {
//         const body = JSON.parse(err.error.body);
//         reason = body.error && body.error.message ? body.error.message : reason;
//       } catch {}
//     }
//     console.log("  ❌ joinGame transaction failed:", reason);
//   }

  console.log("\n✅ Debug complete.");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
}); 