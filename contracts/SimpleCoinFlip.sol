// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleCoinFlip {
    struct Game {
        address[2] players;
        uint256 betAmount;
        bool creatorSide; // false=heads, true=tails
        bool isActive;
        uint256 createdAt;
    }
    
    mapping(bytes32 => Game) public games;
    
    uint256 public constant GAME_TIMEOUT = 1 hours;
    bool private locked; // reentrancy guard

    event GameCreated(bytes32 indexed gameId, address indexed creator, bool side, uint256 amount);
    event GameJoined(bytes32 indexed gameId, address indexed joiner, uint256 amount);
    event GameResolved(bytes32 indexed gameId, address indexed winner, bool winningResult, uint256 payout);
    event GameCancelled(bytes32 indexed gameId, address indexed creator, uint256 refund);

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    function createGame(bool side) external payable returns(bytes32) {
        require(msg.value > 0, "Bet must be > 0");
        
        bytes32 gameId = keccak256(abi.encodePacked(msg.sender, block.timestamp, side, msg.value));
        
        games[gameId] = Game({
            players: [msg.sender, address(0)],
            betAmount: msg.value,
            creatorSide: side,
            isActive: true,
            createdAt: block.timestamp
        });
        
        emit GameCreated(gameId, msg.sender, side, msg.value);
        return gameId;
    }

    function joinGame(bytes32 gameId) external payable nonReentrant {
        Game storage game = games[gameId];
        
        require(game.isActive, "Game not active");
        require(game.players[1] == address(0), "Game already full");
        require(msg.value == game.betAmount, "Bet amount mismatch");
        require(msg.sender != game.players[0], "Cannot join own game");
        
        game.players[1] = msg.sender;
        
        emit GameJoined(gameId, msg.sender, msg.value);
        
        // Resolve game immediately using block hash for randomness
        _resolveGame(gameId);
    }
    
    function _resolveGame(bytes32 gameId) internal {
        Game storage game = games[gameId];
        
        require(game.isActive, "Game not active");
        require(game.players[1] != address(0), "Game not full");
        
        // Use block hash for randomness (simple but deterministic after the fact)
        // In production, you'd want to use VRF or commit-reveal scheme
        uint256 randomValue = uint256(blockhash(block.number - 1));
        bool headsWins = (randomValue % 2 == 0);
        
        // Creator wins when their choice matches the result
        address winner = (headsWins == game.creatorSide) 
            ? game.players[0] // creator wins
            : game.players[1]; // joiner wins
            
        uint256 payout = game.betAmount * 2;
        
        // Mark game as inactive before transfer
        game.isActive = false;
        
        // Transfer winnings
        (bool success, ) = payable(winner).call{value: payout}("");
        require(success, "Payout failed");
        
        emit GameResolved(gameId, winner, headsWins, payout);
    }
    
    // Allow creator to cancel if no one joins within timeout
    function cancelGame(bytes32 gameId) external nonReentrant {
        Game storage game = games[gameId];
        
        require(game.isActive, "Game not active");
        require(msg.sender == game.players[0], "Only creator can cancel");
        require(game.players[1] == address(0), "Game already joined");
        require(block.timestamp >= game.createdAt + GAME_TIMEOUT, "Game timeout not reached");
        
        uint256 refund = game.betAmount;
        game.isActive = false;
        
        (bool success, ) = payable(msg.sender).call{value: refund}("");
        require(success, "Refund failed");
        
        emit GameCancelled(gameId, msg.sender, refund);
    }
    
    // View function to check if game exists and is joinable
    function getGameInfo(bytes32 gameId) external view returns (
        address creator,
        address joiner,
        uint256 betAmount,
        bool creatorSide,
        bool isActive,
        bool isJoinable
    ) {
        Game memory game = games[gameId];
        return (
            game.players[0],
            game.players[1],
            game.betAmount,
            game.creatorSide,
            game.isActive,
            game.isActive && game.players[1] == address(0)
        );
    }
} 