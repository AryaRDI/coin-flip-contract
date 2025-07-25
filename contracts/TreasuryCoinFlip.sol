// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TreasuryCoinFlip is Ownable, Pausable {
    IERC20 public immutable rewardToken;
    uint256 public constant REWARD_AMOUNT = 10 * 10**18; // 10 tokens (assuming 18 decimals)
    uint256 public constant GAME_TIMEOUT = 1 hours;
    
    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
    }
    
    struct Game {
        address creator;
        address joiner;
        bool creatorSide; // false=heads, true=tails
        bool isActive;
        bool resolved;
        uint256 createdAt;
    }
    
    mapping(bytes32 => Game) public games;
    bool private locked; // reentrancy guard
    
    // 🛡️ DAILY LIMIT PROTECTION
    mapping(address => mapping(uint256 => uint256)) public dailyGamesCount; // wallet => day => count
    uint256 public constant MAX_GAMES_PER_DAY = 2;
    
    event GameCreated(bytes32 indexed gameId, address indexed creator, bool side);
    event GameJoined(bytes32 indexed gameId, address indexed joiner);
    event GameResolved(bytes32 indexed gameId, address indexed winner, bool coinResult);
    event GameCancelled(bytes32 indexed gameId, address indexed creator);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    
    // 🛡️ DAILY LIMIT MODIFIER
    modifier dailyLimit() {
        uint256 today = block.timestamp / 1 days; // Get current day as number
        require(
            dailyGamesCount[msg.sender][today] < MAX_GAMES_PER_DAY,
            "Daily game limit exceeded"
        );
        _;
        dailyGamesCount[msg.sender][today]++; // Increment counter AFTER function executes
    }
    
    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }
    
    function createGame(bool side) external dailyLimit whenNotPaused returns(bytes32) {
        bytes32 gameId = keccak256(abi.encodePacked(msg.sender, block.timestamp, side));
        
        games[gameId] = Game({
            creator: msg.sender,
            joiner: address(0),
            creatorSide: side,
            isActive: true,
            resolved: false,
            createdAt: block.timestamp
        });
        
        emit GameCreated(gameId, msg.sender, side);
        return gameId;
    }
    
    function joinGame(bytes32 gameId) external dailyLimit nonReentrant whenNotPaused {
        Game storage game = games[gameId];
        
        require(game.isActive, "Game not active");
        require(game.joiner == address(0), "Game already full");
        require(msg.sender != game.creator, "Cannot join own game");
        require(!game.resolved, "Game already resolved");
        
        game.joiner = msg.sender;
        
        // Simple randomness using block data
        uint256 randomValue = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao, // More secure than block.difficulty in newer versions
            msg.sender,
            game.creator,
            gameId
        )));
        
        bool coinResult = (randomValue % 2 == 0); // false=heads, true=tails
        
        // Determine winner
        address winner = (coinResult == game.creatorSide) 
            ? game.creator 
            : game.joiner;
        
        // Mark as resolved
        game.isActive = false;
        game.resolved = true;
        
        // Transfer reward tokens from contract to winner
        require(
            rewardToken.transfer(winner, REWARD_AMOUNT),
            "Token transfer failed"
        );
        
        emit GameJoined(gameId, msg.sender);
        emit GameResolved(gameId, winner, coinResult);
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
    
    function getGameInfo(bytes32 gameId) external view returns (
        address creator,
        address joiner,
        bool creatorSide,
        bool isActive,
        bool isJoinable,
        bool resolved
    ) {
        Game memory game = games[gameId];
        return (
            game.creator,
            game.joiner,
            game.creatorSide,
            game.isActive,
            game.isActive && game.joiner == address(0) && !game.resolved,
            game.resolved
        );
    }
    
    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(rewardToken.transfer(to, amount), "Withdraw failed");
        emit EmergencyWithdraw(to, amount);
    }
    
    // View functions for treasury management
    function getTreasuryBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
    function getContractInfo() external view returns (
        address tokenAddress,
        uint256 rewardAmount,
        uint256 treasuryBalance
    ) {
        return (
            address(rewardToken),
            10 * 10**18, // Fixed reward amount of 10 tokens
            rewardToken.balanceOf(address(this))
        );
    }
    
    // 🛡️ DAILY LIMIT VIEW FUNCTIONS
    function getRemainingGames(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        uint256 played = dailyGamesCount[user][today];
        return played >= MAX_GAMES_PER_DAY ? 0 : MAX_GAMES_PER_DAY - played;
    }
    
    function getUserDailyStats(address user) external view returns (
        uint256 gamesPlayedToday,
        uint256 maxGamesPerDay,
        uint256 remainingGames,
        uint256 nextResetTime
    ) {
        uint256 today = block.timestamp / 1 days;
        uint256 played = dailyGamesCount[user][today];
        uint256 remaining = played >= MAX_GAMES_PER_DAY ? 0 : MAX_GAMES_PER_DAY - played;
        uint256 nextReset = (today + 1) * 1 days; // Midnight tomorrow
        
        return (played, MAX_GAMES_PER_DAY, remaining, nextReset);
    }
} 