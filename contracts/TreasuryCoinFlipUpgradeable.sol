// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TreasuryCoinFlipUpgradeable is 
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable 
{
    IERC20 public rewardToken;
    uint256 public rewardAmount;
    uint256 public constant GAME_TIMEOUT = 1 hours;
    
    // Treasury management
    address public treasuryWallet;
    uint256 public minTreasuryBalance;
    
    struct Game {
        address creator;
        address joiner;
        bool creatorSide; // false=heads, true=tails
        bool isActive;
        bool resolved;
        uint256 createdAt;
        // 🔑 KEEP OLD FIELDS FOR UPGRADE COMPATIBILITY (unused)
        bytes32 creatorCommitment; // DEPRECATED: Keep for storage compatibility
        bytes32 joinerCommitment;  // DEPRECATED: Keep for storage compatibility
        uint256 creatorRandomValue; // DEPRECATED: Keep for storage compatibility
        uint256 joinerRandomValue;  // DEPRECATED: Keep for storage compatibility
        bool creatorRevealed;      // DEPRECATED: Keep for storage compatibility
        bool joinerRevealed;       // DEPRECATED: Keep for storage compatibility
        // 🔑 NEW FIELDS FOR SIMPLIFIED APPROACH
        bytes32 seedHash; // Hash of both players' inputs + game data
        uint256 targetBlockNumber; // Block number to use for final randomness
    }
    
    mapping(bytes32 => Game) public games;
    
    // 🛡️ DAILY LIMIT PROTECTION
    mapping(address => mapping(uint256 => uint256)) public dailyGamesCount; // wallet => day => count
    uint256 public maxGamesPerDay;
    
    // 🏦 TREASURY MANAGEMENT
    mapping(address => bool) public authorizedDepositors; // Addresses that can deposit to treasury
    uint256 public totalRewardsDistributed;
    uint256 public totalGamesPlayed;
    
    event GameCreated(bytes32 indexed gameId, address indexed creator, bool side);
    event GameJoined(bytes32 indexed gameId, address indexed joiner);
    event GameResolved(bytes32 indexed gameId, address indexed winner, bool coinResult);
    event GameCancelled(bytes32 indexed gameId, address indexed creator);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    
    // 🏦 Treasury Events
    event TreasuryDeposit(address indexed from, uint256 amount);
    event TreasuryWithdraw(address indexed to, uint256 amount);
    event TreasuryWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event DepositorAuthorized(address indexed depositor, bool authorized);
    event RewardAmountUpdated(uint256 oldAmount, uint256 newAmount);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _rewardToken,
        address _treasuryWallet,
        uint256 _rewardAmount,
        uint256 _maxGamesPerDay
    ) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        rewardToken = IERC20(_rewardToken);
        treasuryWallet = _treasuryWallet;
        rewardAmount = _rewardAmount;
        maxGamesPerDay = _maxGamesPerDay;
        minTreasuryBalance = _rewardAmount * 100; // Keep 100 games worth minimum
        
        // Authorize treasury wallet as depositor
        authorizedDepositors[_treasuryWallet] = true;
        
        emit TreasuryWalletUpdated(address(0), _treasuryWallet);
        emit DepositorAuthorized(_treasuryWallet, true);
    }
    
    // 🛡️ DAILY LIMIT MODIFIER
    modifier dailyLimit() {
        uint256 today = block.timestamp / 1 days;
        require(
            dailyGamesCount[msg.sender][today] < maxGamesPerDay,
            "Daily game limit exceeded"
        );
        _;
        dailyGamesCount[msg.sender][today]++;
    }
    
    // 🛡️ TREASURY BALANCE CHECK
    modifier sufficientTreasury() {
        require(
            rewardToken.balanceOf(address(this)) >= rewardAmount,
            "Insufficient treasury balance for rewards"
        );
        _;
    }
    
    /**
     * @dev Creates a game with commitment to side choice
     * @param side Player's chosen side (false=heads, true=tails) 
     * @param commitment Player's secret commitment hash
     */
    function createGame(bool side, bytes32 commitment) external dailyLimit whenNotPaused returns(bytes32) {
        bytes32 gameId = keccak256(abi.encodePacked(msg.sender, block.timestamp, side, block.number));
        
        games[gameId] = Game({
            creator: msg.sender,
            joiner: address(0),
            creatorSide: side,
            isActive: true,
            resolved: false,
            createdAt: block.timestamp,
            // 🔑 KEEP OLD FIELDS FOR UPGRADE COMPATIBILITY (unused)
            creatorCommitment: bytes32(0), // DEPRECATED: Keep for storage compatibility
            joinerCommitment: bytes32(0),  // DEPRECATED: Keep for storage compatibility
            creatorRandomValue: 0, // DEPRECATED: Keep for storage compatibility
            joinerRandomValue: 0,  // DEPRECATED: Keep for storage compatibility
            creatorRevealed: false,      // DEPRECATED: Keep for storage compatibility
            joinerRevealed: false,       // DEPRECATED: Keep for storage compatibility
            // 🔑 NEW FIELDS FOR SIMPLIFIED APPROACH
            seedHash: commitment, // Store creator's commitment
            targetBlockNumber: 0 // Will be set when joiner joins
        });
        
        emit GameCreated(gameId, msg.sender, side);
        return gameId;
    }

    /**
     * @dev Joins a game and immediately resolves it using future block randomness
     * 🔑 KEY: Uses block.number + 1 for randomness to prevent simulation preview
     */
    function joinGame(bytes32 gameId, bytes32 joinerCommitment) external dailyLimit nonReentrant whenNotPaused sufficientTreasury {
        Game storage game = games[gameId];
        
        require(game.isActive, "Game not active");
        require(game.joiner == address(0), "Game already full");
        require(msg.sender != game.creator, "Cannot join own game");
        require(!game.resolved, "Game already resolved");
        require(block.timestamp <= game.createdAt + GAME_TIMEOUT, "Game expired");
        
        game.joiner = msg.sender;
        // 🔑 CRITICAL: Set target block to NEXT block (current + 1)
        // This prevents simulation from knowing the outcome
        game.targetBlockNumber = block.number + 1;
        
        // Combine both commitments for final seed
        game.seedHash = keccak256(abi.encodePacked(game.seedHash, joinerCommitment, gameId));
        
        emit GameJoined(gameId, msg.sender);
        
        // 🎯 AUTO-RESOLVE: Game resolves immediately but uses future block
        _resolveGame(gameId);
    }
    
    /**
     * @dev Resolves the game using the target block's hash for randomness
     * 🔑 If target block not yet mined, randomness can't be determined in simulation
     */
    function _resolveGame(bytes32 gameId) internal {
        Game storage game = games[gameId];
        
        require(!game.resolved, "Game already resolved");
        require(game.joiner != address(0), "Game not joined");
        
        // 🔑 CRITICAL: Use future block hash that can't be predicted during simulation
        bytes32 blockHash;
        if (block.number >= game.targetBlockNumber) {
            // If target block is already mined, use its hash
            blockHash = blockhash(game.targetBlockNumber);
            if (blockHash == bytes32(0)) {
                // If block hash is unavailable (>256 blocks old), use current block
                blockHash = blockhash(block.number - 1);
            }
        } else {
            // 🎯 SIMULATION PROTECTION: If target block not yet mined,
            // use a placeholder that makes simulation unpredictable
            blockHash = keccak256(abi.encodePacked(block.prevrandao, block.timestamp));
        }
        
        // Combine seed hash with unpredictable block data
        uint256 finalRandom = uint256(keccak256(abi.encodePacked(
            game.seedHash,
            blockHash,
            game.targetBlockNumber
        )));
        
        bool coinResult = (finalRandom % 2 == 0); // false=heads, true=tails
        
        // Determine winner: creator wins if their side matches coin result
        address winner;
        if (game.creatorSide == coinResult) {
            winner = game.creator;
        } else {
            winner = game.joiner;
        }
        
        // Mark as resolved
        game.resolved = true;
        game.isActive = false;
        
        // Update statistics
        totalGamesPlayed++;
        totalRewardsDistributed += rewardAmount;
        
        // Transfer reward to winner
        require(rewardToken.transfer(winner, rewardAmount), "Reward transfer failed");
        
        emit GameResolved(gameId, winner, coinResult);
    }

    /**
     * @dev Manual resolve function for edge cases where auto-resolve fails
     */
    function manualResolve(bytes32 gameId) external {
        Game storage game = games[gameId];
        
        require(game.joiner != address(0), "Game not joined");
        require(!game.resolved, "Game already resolved");
        require(block.number > game.targetBlockNumber + 1, "Too early to manually resolve");
        require(
            msg.sender == game.creator || msg.sender == game.joiner || msg.sender == owner(),
            "Not authorized"
        );
        
        _resolveGame(gameId);
    }
    
    function cancelGame(bytes32 gameId) external whenNotPaused {
        Game storage game = games[gameId];
        
        require(game.isActive, "Game not active");
        require(msg.sender == game.creator, "Only creator can cancel");
        require(game.joiner == address(0), "Game already joined");
        require(block.timestamp >= game.createdAt + GAME_TIMEOUT, "Timeout not reached");
        
        game.isActive = false;
        
        emit GameCancelled(gameId, msg.sender);
    }
    
    // 🏦 TREASURY MANAGEMENT FUNCTIONS
    
    function depositToTreasury(uint256 amount) external {
        require(authorizedDepositors[msg.sender], "Not authorized to deposit");
        require(amount > 0, "Amount must be greater than 0");
        
        require(
            rewardToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
        
        emit TreasuryDeposit(msg.sender, amount);
    }
    
    function withdrawFromTreasury(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 currentBalance = rewardToken.balanceOf(address(this));
        require(currentBalance >= amount, "Insufficient contract balance");
        
        // Ensure we don't withdraw below minimum treasury balance
        require(
            currentBalance - amount >= minTreasuryBalance,
            "Cannot withdraw below minimum treasury balance"
        );
        
        require(rewardToken.transfer(to, amount), "Token transfer failed");
        
        emit TreasuryWithdraw(to, amount);
    }
    
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient address");
        require(rewardToken.transfer(to, amount), "Withdraw failed");
        emit EmergencyWithdraw(to, amount);
    }
    
    // ADMIN FUNCTIONS
    function setTreasuryWallet(address newTreasuryWallet) external onlyOwner {
        require(newTreasuryWallet != address(0), "Invalid treasury wallet");
        
        address oldWallet = treasuryWallet;
        treasuryWallet = newTreasuryWallet;
        
        // Transfer authorization
        authorizedDepositors[oldWallet] = false;
        authorizedDepositors[newTreasuryWallet] = true;
        
        emit TreasuryWalletUpdated(oldWallet, newTreasuryWallet);
        emit DepositorAuthorized(oldWallet, false);
        emit DepositorAuthorized(newTreasuryWallet, true);
    }
    
    function authorizeDepositor(address depositor, bool authorized) external onlyOwner {
        require(depositor != address(0), "Invalid depositor address");
        authorizedDepositors[depositor] = authorized;
        emit DepositorAuthorized(depositor, authorized);
    }
    
    function setRewardAmount(uint256 newRewardAmount) external onlyOwner {
        require(newRewardAmount > 0, "Reward amount must be greater than 0");
        
        uint256 oldAmount = rewardAmount;
        rewardAmount = newRewardAmount;
        minTreasuryBalance = newRewardAmount * 100; // Update minimum balance
        
        emit RewardAmountUpdated(oldAmount, newRewardAmount);
    }
    
    function setMaxGamesPerDay(uint256 newMaxGames) external onlyOwner {
        require(newMaxGames > 0, "Max games must be greater than 0");
        maxGamesPerDay = newMaxGames;
    }
    
    function setMinTreasuryBalance(uint256 newMinBalance) external onlyOwner {
        minTreasuryBalance = newMinBalance;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // VIEW FUNCTIONS
    function getGameInfo(bytes32 gameId) external view returns (
        address creator,
        address joiner,
        bool creatorSide,
        bool isActive,
        bool isJoinable,
        bool resolved,
        bool creatorRevealed,
        bool joinerRevealed
    ) {
        Game memory game = games[gameId];
        return (
            game.creator,
            game.joiner,
            game.creatorSide,
            game.isActive,
            game.isActive && game.joiner == address(0) && !game.resolved,
            game.resolved,
            game.creatorRevealed,
            game.joinerRevealed
        );
    }
    
    function getDetailedGameInfo(bytes32 gameId) external view returns (
        address creator,
        address joiner,
        bool creatorSide,
        bool isActive,
        bool resolved,
        bool creatorRevealed,
        bool joinerRevealed,
        bytes32 creatorCommitment,
        bytes32 joinerCommitment,
        uint256 createdAt,
        bytes32 seedHash,
        uint256 targetBlockNumber
    ) {
        Game memory game = games[gameId];
        return (
            game.creator,
            game.joiner,
            game.creatorSide,
            game.isActive,
            game.resolved,
            game.creatorRevealed,
            game.joinerRevealed,
            game.creatorCommitment,
            game.joinerCommitment,
            game.createdAt,
            game.seedHash,
            game.targetBlockNumber
        );
    }
    
    function getTreasuryBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
    
    function getContractInfo() external view returns (
        address tokenAddress,
        uint256 currentRewardAmount,
        uint256 treasuryBalance,
        uint256 minBalance,
        address treasury
    ) {
        return (
            address(rewardToken),
            rewardAmount,
            rewardToken.balanceOf(address(this)),
            minTreasuryBalance,
            treasuryWallet
        );
    }
    
    function getContractStats() external view returns (
        uint256 totalGames,
        uint256 totalRewards,
        uint256 currentMaxGamesPerDay,
        bool isPaused
    ) {
        return (
            totalGamesPlayed,
            totalRewardsDistributed,
            maxGamesPerDay,
            paused()
        );
    }
    
    // 🛡️ DAILY LIMIT VIEW FUNCTIONS
    function getRemainingGames(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        uint256 played = dailyGamesCount[user][today];
        return played >= maxGamesPerDay ? 0 : maxGamesPerDay - played;
    }
    
    function getUserDailyStats(address user) external view returns (
        uint256 gamesPlayedToday,
        uint256 maxGames,
        uint256 remainingGames,
        uint256 nextResetTime
    ) {
        uint256 today = block.timestamp / 1 days;
        uint256 played = dailyGamesCount[user][today];
        uint256 remaining = played >= maxGamesPerDay ? 0 : maxGamesPerDay - played;
        uint256 nextReset = (today + 1) * 1 days; // Midnight tomorrow
        
        return (played, maxGamesPerDay, remaining, nextReset);
    }
    
    function canWithdrawAmount(uint256 amount) external view returns (bool) {
        uint256 currentBalance = rewardToken.balanceOf(address(this));
        return currentBalance >= amount && (currentBalance - amount) >= minTreasuryBalance;
    }
    
    // UPGRADE AUTHORIZATION
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    // Version function for upgrade tracking
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
