// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBase.sol";

contract CoinFlip is VRFConsumerBase {
    bytes32 internal keyHash;
    uint256 internal fee;
    
    constructor(
        address _vrfCoordinator,
        address _link,
        bytes32 _keyHash,
        uint256 _fee
    ) VRFConsumerBase(_vrfCoordinator, _link) {
        keyHash = _keyHash;
        fee = _fee;
    }
    
    struct Game {
        address[2] players;
        uint256 betAmount;
        bool creatorSide; // false=heads, true=tails
        bool isActive;
        uint256 createdAt;
    }
    
    mapping(bytes32 => Game) public games;
    mapping(bytes32 => bytes32) public requestToGame; // requestId => gameId
    
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
        
        // Request randomness
        bytes32 requestId = requestRandomness(keyHash, fee);
        requestToGame[requestId] = gameId;
        
        emit GameJoined(gameId, msg.sender, msg.value);
    }

    // VRF callback
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        bytes32 gameId = requestToGame[requestId];
        Game storage game = games[gameId];
        
        require(game.isActive, "Game not active");
        
        bool headsWins = (randomness % 2 == 0);
        // Fixed logic: creator wins when their choice matches the result
        address winner = (headsWins == game.creatorSide) 
            ? game.players[0] // creator wins
            : game.players[1]; // joiner wins
            
        uint256 payout = game.betAmount * 2;
        
        // Mark game as inactive before transfer
        game.isActive = false;
        
        // Use call instead of transfer for better gas handling
        (bool success, ) = payable(winner).call{value: payout}("");
        require(success, "Payout failed");
        
        emit GameResolved(gameId, winner, headsWins, payout);
        
        // Cleanup
        delete requestToGame[requestId];
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
