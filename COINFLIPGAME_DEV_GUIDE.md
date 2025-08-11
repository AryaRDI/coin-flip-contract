## CoinFlipGameUpgradeable – Developer Guide (v3.2.0)

This document explains how to build against and operate the coin‑flip game contract implemented in `contracts-evm/contracts/CoinFlipBet.sol` (contract name: `CoinFlipGameUpgradeable`). It is UUPS‑upgradeable, timelocked for critical admin actions, and uses a hardened commit–reveal RNG with a backend signer.

### High‑level summary
- Two‑player coin‑flip with 2% protocol fee.
- Supports native ETH and whitelisted ERC‑20 tokens.
- Randomness: server commit–reveal mixed with a future blockhash.
- Four resolution paths: signer, public with revealed seed, fallback after grace, and emergency resolve.
- Emergency resolve by trusted signer to unblock games immediately.
- Critical admin actions are timelocked (2 hours) and require a queue+execute pattern.

### Contract stack
- Upgradeability: `UUPSUpgradeable`
- Ownership + Timelock: `OwnableUpgradeable` via `OwnableTimelockUpgradeable` (custom) with `TIMELOCK_DELAY = 2h`
- Pausing: `PausableUpgradeable`
- Reentrancy: `ReentrancyGuardUpgradeable`
- ERC‑20 safety: `SafeERC20`

## Contract Architecture Deep Dive

### Security-First Design Philosophy

The `CoinFlipGameUpgradeable` contract is designed with security as the primary concern, implementing multiple layers of protection against common smart contract vulnerabilities:

**1. Reentrancy Protection**
- All state-changing functions use `nonReentrant` modifier
- External calls (ETH transfers, ERC20 operations) happen after state changes
- Uses OpenZeppelin's battle-tested `ReentrancyGuardUpgradeable`

**2. Randomness Security**
- **Server Commit-Reveal**: Backend commits to a secret seed before it's needed
- **Blockhash Mixing**: Combines server seed with future blockhash for unpredictability
- **Game-Specific Entropy**: Each game has unique seed hash based on participants and stake
- **Multiple Resolution Paths**: Prevents single point of failure in randomness generation

**3. Economic Security**
- **Fee-on-Transfer Protection**: Explicitly checks token balance changes to reject fee-on-transfer tokens
- **Exact Balance Verification**: Ensures received amounts match expected amounts
- **Fee Booking**: Protocol fees are immediately booked to prevent stranding

**4. Access Control & Timelock**
- **Owner-Only Admin Functions**: Critical functions restricted to contract owner
- **2-Hour Timelock**: Admin changes require queue-then-execute pattern with 2-hour delay
- **Trusted Signer**: Separate role for resolution operations, can be different from owner

### Multi-Layer Randomness System

The contract implements a sophisticated randomness system with multiple fallback mechanisms:

#### Layer 1: Server Commit-Reveal + Blockhash (Most Secure)
**Path**: `resolveBySigner(id, seed)` - Used when server operates normally
- Server pre-commits to a secret seed using `keccak256(seed)`
- Game captures `serverEpoch` and `targetBlockNumber` (joinBlock + 1) at join time
- Resolution combines: `keccak256(serverSeed, seedHash, blockhash, targetBlockNumber)`
- **Advantages**: Unpredictable, verifiable, backend-controlled timing

#### Layer 2: Public Revealed Seed + Blockhash (Transparent)
**Path**: `resolveWithRevealed(id)` - Used when server reveals seed publicly
- Trusted signer calls `revealServerSeed()` to make seed public
- Anyone can then call `resolveWithRevealed()` after target block
- Same randomness formula but with public verification
- **Advantages**: Transparent, community verifiable, removes trust in resolution timing

#### Layer 3: Blockhash-Only Fallback (Emergency)
**Path**: `resolveWithFallback(id)` - Used when server fails
- After `RESOLVE_GRACE` period (6 hours), anyone can resolve using only blockhash
- Uses: `keccak256(seedHash, blockhash, targetBlockNumber)`
- **Advantages**: Guaranteed resolution, no server dependency

#### Layer 4: Emergency Resolve (Admin Override)
**Path**: `emergencyResolve(id, side)` - Used in exceptional circumstances
- Only `trustedSigner` can call
- Bypasses all waiting periods and randomness
- Directly specifies winning side (HEADS/TAILS)
- **Use Cases**: Technical issues, stuck games, dispute resolution

### Smart Contract Upgradeability

**UUPS Proxy Pattern**
- Implementation contract: `CoinFlipGameUpgradeable`
- Proxy: Standard ERC1967 transparent proxy
- Upgrade authorization: Owner-only with 2-hour timelock
- Storage layout: Uses OpenZeppelin's gap pattern for safe upgrades

**Storage Layout Protection**
```solidity
// Current storage variables (never reorder these)
mapping(uint256 => Game) public games;           // Slot 0
mapping(address => bool) public whitelist;       // Slot 1
mapping(address => uint256) public accFeeOf;     // Slot 2
uint256 public nextId;                           // Slot 3
// ... more variables

uint256[47] private __gap; // Reserve slots for future additions
```

### Token Support & Whitelisting

**Native ETH Support**
- ETH represented as `address(0)` in all mappings
- Whitelisted by default in `initialize()`
- Direct balance verification via `msg.value`

**ERC20 Token Security**
- **Whitelist-Only**: Only approved tokens via `setWhitelist()`
- **Balance-Diff Verification**: Prevents fee-on-transfer token exploits
- **SafeERC20**: Uses OpenZeppelin's safe transfer wrappers
- **Exact Amount Enforcement**: `require(received == expected)`

### Game State Machine

```
CREATED ──joinGame()──→ RESOLVING ──resolve*()──→ RESOLVED
   │                        │                       │
   │                        │                   withdraw()
   └─cancelGame()─→ CANCELLED                       │
                        ↑                          │
                        └──claimRefund()───────────┘
```

**State Transitions**
- `CREATED`: Game exists, waiting for second player
- `RESOLVING`: Both players joined, waiting for randomness resolution
- `RESOLVED`: Game finished, winner determined, payout available
- `CANCELLED`: Game cancelled or refunded, stakes returned

### Economic Model & Fee Structure

**Fee Calculation**
- **Protocol Fee**: 2% (200 basis points) of total pool
- **Pool Size**: 2 × stake (both players' contributions)
- **Winner Payout**: `pool - fee = stake × 2 × 0.98`
- **Fee Distribution**: Accumulated per token, withdrawable by owner

**Example (1 ETH game)**
- Creator stakes: 1 ETH
- Joiner stakes: 1 ETH  
- Total pool: 2 ETH
- Protocol fee: 0.04 ETH (2%)
- Winner receives: 1.96 ETH

### Timelock Security Pattern

All critical admin functions use a queue-then-execute pattern:

```solidity
modifier timelocked(bytes32 id) {
    if (queued[id] == 0) {
        queued[id] = block.timestamp + TIMELOCK_DELAY;
        emit Queued(id, queued[id]);
        return; // First call: queue only
    }
    require(block.timestamp >= queued[id], "Timelock not passed");
    delete queued[id];
    _; // Second call: execute
    emit Executed(id);
}
```

**Protected Functions**
- `setTrustedSigner()`: Change resolution authority
- `commitServerSeed()`: Add new epoch commitment  
- `setWhitelist()`: Add/remove token support
- `withdrawFees()`: Extract protocol revenue
- `pause()/unpause()`: Emergency controls
- `_authorizeUpgrade()`: Contract upgrades

### Gas Optimization Strategies

**Struct Packing**
- `Game` struct uses `uint40` for timestamps (sufficient until 2106)
- Enum packing in single storage slots
- Separate `GameRngData` to avoid storage layout changes

**Minimal External Calls**
- Single `safeTransferFrom` per token operation
- Batch balance checking with before/after pattern
- Early returns and validation ordering

**View Function Optimization**
- `listGames()` with pagination to prevent gas limit issues
- `getGame()` returns memory copy for efficient queries

### Key constants
- `FEE_BPS = 200` (2% of the total pool)
- `BPS_DEN = 10_000`
- `MIN_TIMEOUT = 24 hours` (join window)
- `RESOLVE_GRACE = 6 hours` (time to wait before public fallback/claimRefund)

### Data model
- `GameState`: `CREATED → RESOLVING → RESOLVED` or `CANCELLED`
- `Game` fields: `creator`, `joiner`, `token`, `stake` (per‑player), `creatorSide`, `state`, `winner`, `pool`, `createdAt`, `resolveBy`
- RNG snapshot per game (`gameRngOf`): `seedHash`, `targetBlockNumber` (join block + 1), `epoch`
- Fees: `accFeeOf[token]` tracks accrued protocol fee per token (ETH uses `address(0)`).
- Whitelist: `whitelist[token]` (ETH `address(0)` is allowed by default).
- Commit–reveal: `serverEpoch`, `epochCommitment[epoch]`, `revealedSeedOf[epoch]`.
- `trustedSigner`: backend address allowed to resolve early and reveal seed.

### Lifecycle
1) createGame(token, amount, side)
- Requirements:
  - `whitelist[token] == true`
  - `amount > 0`
  - ETH game: `msg.value == amount`
  - ERC‑20 game: `msg.value == 0`; exact `safeTransferFrom` amount must be received (no fee‑on‑transfer)
- Effects:
  - Assigns `id = nextId++`
  - Stores game in `CREATED`
  - Emits `GameCreated(id, creator, token, amount, side)`

2) joinGame(id)
- Requirements:
  - Game is `CREATED`
  - Sender is not creator (`"self join"`)
  - `block.timestamp <= createdAt + MIN_TIMEOUT` (else `"expired"`)
  - Pays stake (ETH or ERC‑20) as in create step
- Effects:
  - Sets `joiner`, `pool = 2*stake`, `state = RESOLVING`, `resolveBy = now + RESOLVE_GRACE`
  - Snapshots RNG: `epoch = serverEpoch`, `targetBlockNumber = block.number + 1`, `seedHash = keccak256(id, creator, joiner, token, stake)`
  - Emits `GameJoined(id, joiner)`

3) Resolution paths
- By signer: `resolveBySigner(id, seed)`
  - Only `trustedSigner`
  - Reverts if `block.number < targetBlockNumber` (`"too early"`)
  - Reverts if no commitment for `r.epoch` (`"no epoch commit"`)
  - Reverts if `keccak256(seed) != epochCommitment[r.epoch]` (`"seed !commit"`)
  - Uses server seed + seedHash + target blockhash to compute randomness; emits `ResolvedWithSigner`

- With revealed seed: `resolveWithRevealed(id)`
  - Anyone can call
  - Reverts if `revealedSeedOf[r.epoch] == 0` (`"no reveal"`)
  - Reverts if `block.number < targetBlockNumber` (`"too early"`)
  - Uses revealed seed + seedHash + blockhash; emits `ResolvedWithRevealed`

- Fallback (no seed): `resolveWithFallback(id)`
  - Anyone can call
  - Reverts if `block.timestamp < resolveBy` (`"grace"`)
  - Uses seedHash + blockhash; emits `ResolvedWithFallback`

- Emergency resolve: `emergencyResolve(id, side)`
  - Only `trustedSigner`
  - Only in `RESOLVING` state
  - Bypasses all waiting periods and randomness generation
  - Directly sets winner based on specified `CoinSide` (HEADS=0, TAILS=1)
  - Uses deterministic random number to trigger standard finalization logic
  - Emits `EmergencyResolved(id, side, winner)` and standard `GameResolved` events
  - **Use Cases**: Critical system issues, stuck randomness, dispute resolution

4) Withdraw
- `withdraw(id)`
  - Only `winner`
  - Only if `RESOLVED`
  - Reverts if already paid (`"paid"`)

5) Cancel / Refund
- `cancelGame(id)` → only creator, only in `CREATED`; refunds creator; `CANCELLED`.
- `claimRefund(id)` → public in `RESOLVING` after `RESOLVE_GRACE`; returns half to each; `CANCELLED`.

### RNG/epoch semantics
- The game captures `serverEpoch` at join into `gameRngOf[id].epoch`.
- The backend must commit the seed for that epoch before resolving by signer.
- Sequence for signer path:
  1. Owner queues `commitServerSeed(commitment, epoch)`
  2. After 2h, owner executes it
  3. `trustedSigner` resolves with the matching `seed`
- For public reveal path, `trustedSigner` first calls `revealServerSeed(seed, epoch)`, then anyone can call `resolveWithRevealed` after `targetBlockNumber` is mined.
- If the exact `targetBlockNumber` blockhash is unavailable (older than 256 blocks), the implementation falls back to `block.number - 1`.

### Fees
- Fee is booked at finalization: `fee = pool * FEE_BPS / BPS_DEN`, `payout = pool - fee`, then `g.pool = payout` and `accFeeOf[token] += fee`.
- Admin can withdraw fees per token via `withdrawFees(token, amount)` (timelocked).

### Timelock pattern (critical admin ops)
These functions are guarded by `timelocked(...)`:
- `setTrustedSigner(newSigner)`
- `commitServerSeed(commitment, epoch)`
- `setWhitelist(token, allow)`
- `withdrawFees(token, amount)`
- `pause()` / `unpause()`
- `_authorizeUpgrade(newImplementation)`

Behavior:
- First call only queues; it emits `Queued(id, executeAfter)` and returns without applying the change.
- After 2 hours (`TIMELOCK_DELAY`), call again with the same parameters to execute; it applies the change and emits `Executed(id)`.

### Pausing
- `pause()` and `unpause()` are timelocked.
- When paused, `createGame` and `joinGame` revert with the OZ `EnforcedPause` custom error.

### Events
- `GameCreated(id, creator, token, stake, side)`
- `GameJoined(id, joiner)`
- `GameResolved(id, winner, loser, winSide, payout, fee)`
- `GameCancelled(id)`
- `Refunded(id)`
- `Whitelisted(token, isAllowed)`
- RNG/Signer:
  - `ServerCommitted(epoch, commitment)`
  - `ServerRevealed(epoch, seed)`
  - `ResolvedWithSigner(id, rnd)`
  - `ResolvedWithRevealed(id, rnd)`
  - `ResolvedWithFallback(id, rnd)`
  - `EmergencyResolved(id, winSide, winner)` - **New in v3.2.0**
  - `TrustedSignerUpdated(oldSigner, newSigner)`

### Revert reasons (selection)
- Game setup: `"token !whitelisted"`, `"zero stake"`, `"bad msg.value"`, `"eth sent"`, `"fee-on-transfer"`
- Join: `"self join"`, `"expired"`
- State guards: `"bad state"`
- Withdraw: `"!winner"`, `"paid"`
- Refund: `"grace"`
- RNG/signing: `"!trusted"`, `"no epoch commit"`, `"seed !commit"`, `"too early"`
- Direct transfers: `"direct eth"`, `"fallback"`
- Admin (OZ): `OwnableUnauthorizedAccount` for non‑owner admin attempts

### Upgradeability
- UUPS upgrade via `_authorizeUpgrade(newImplementation)` guarded by timelock and owner.
- Storage reserved with gaps; do not change ordering of existing state variables.
- `version()` returns the human‑readable contract version.

### Integration patterns
- Backend cron for RNG epoch:
  - Periodically queue+execute `commitServerSeed(commitment, nextEpoch)` on owner
  - Use a separate `trustedSigner` key to resolve games via `resolveBySigner`
  - Optionally, reveal with `revealServerSeed(seed, epoch)` to enable public resolution
- Frontend flow (ETH example, ethers v6):
  ```ts
  // Create
  await coinFlip.createGame(ethers.ZeroAddress, stake, 0, { value: stake });
  // Join
  await coinFlip.joinGame(id, { value: stake });
  // After resolution, winner calls
  await coinFlip.withdraw(id);
  ```
- Admin fee withdrawal:
  ```ts
  // Queue
  await coinFlip.withdrawFees(ethers.ZeroAddress, amount);
  // ...wait >= 2h...
  // Execute
  await coinFlip.withdrawFees(ethers.ZeroAddress, amount);
  ```

### Testing tips
- Epoch alignment: The game snapshots `epoch = 1` by default at join; commit to epoch 1 in tests unless you explicitly increment `serverEpoch`.
- Mine at least one block after join before resolving (`targetBlockNumber = joinBlock + 1`).
- To test blockhash fallback, mine >256 blocks past `targetBlockNumber`.
- Timelock: call once to queue, advance time by >=2h, call again to execute.
- For ERC‑20 tests, mint/approve exact `stake` amounts and ensure `whitelist[token] = true` (timelocked).

### Security considerations
- Reentrancy is guarded; external calls use `SafeERC20` and native transfers are performed last.
- Contract blocks direct ETH via `receive()` and `fallback()`.
- Fee‑on‑transfer tokens are rejected for stake transfers (`"fee-on-transfer"`).
- Emergency resolution is limited to `trustedSigner` and only from `RESOLVING`.

## Internal Implementation Details

### Core Internal Functions

**`_collectStake(token, amount, from, msgValue)`**
- Handles both ETH and ERC20 token collection
- ETH: Validates `msg.value == amount`
- ERC20: Validates `msg.value == 0` and checks balance diff to prevent fee-on-transfer exploits
- Uses `SafeERC20.safeTransferFrom()` for ERC20 transfers

**`_payout(token, to, amount)`**
- Handles both ETH and ERC20 token payouts
- ETH: Uses low-level `call{value}()` with success check
- ERC20: Uses `SafeERC20.safeTransfer()`
- Called for withdrawals, cancellations, and refunds

**`_finalizeResolution(id, rnd)`**
- Common resolution logic used by all resolution paths
- Determines winner based on: `(rnd & 1 == 0) ? HEADS : TAILS`
- Calculates and books protocol fee: `fee = pool * 200 / 10000`
- Sets winner, updates state to `RESOLVED`
- Emits `GameResolved(id, winner, loser, winSide, payout, fee)`

### Randomness Implementation

**Seed Hash Generation** (at join time):
```solidity
seedHash = keccak256(abi.encodePacked(id, creator, joiner, token, stake))
```

**Final Random Number** (resolution):
- **With Server Seed**: `keccak256(serverSeedI, seedHash, blockhash, targetBlock)`
- **Fallback Only**: `keccak256(seedHash, blockhash, targetBlock)`
- **Emergency**: Deterministic `(side == HEADS) ? 0 : 1`

Where `serverSeedI = keccak256(serverSeed, gameId)` for game-specific uniqueness.

**Blockhash Fallback Logic**:
```solidity
bytes32 bh = blockhash(targetBlockNumber);
if (bh == bytes32(0)) {
    bh = blockhash(block.number - 1); // Fallback for old blocks
}
```

### Storage Optimization

**Game Struct Packing** (192 bytes):
```solidity
struct Game {
    address creator;      // 20 bytes
    address joiner;       // 20 bytes  
    address token;        // 20 bytes
    uint256 stake;        // 32 bytes
    CoinSide creatorSide; // 1 byte (enum)
    GameState state;      // 1 byte (enum)
    address winner;       // 20 bytes
    uint256 pool;         // 32 bytes
    uint40 createdAt;     // 5 bytes (timestamp)
    uint40 resolveBy;     // 5 bytes (timestamp)
}
```

**Separate RNG Data** (avoids storage layout conflicts):
```solidity
struct GameRngData {
    bytes32 seedHash;           // 32 bytes
    uint256 targetBlockNumber;  // 32 bytes
    uint64 epoch;              // 8 bytes
}
```

### File index
- Contract: `contracts-evm/contracts/CoinFlipBet.sol` (`CoinFlipGameUpgradeable`)
- Test proxy (for local tests): `contracts-evm/contracts/mocks/ERC1967Proxy.sol` (`TestProxy`)
- Example tests: `contracts-evm/test/CoinFlipGameUpgradeable.ts`


