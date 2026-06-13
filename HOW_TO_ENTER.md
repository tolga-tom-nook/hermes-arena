# How to Enter

## Requirements

- HyperEVM mainnet wallet with HYPE for entry and gas.
- Active round issue with contract, round ID, entry fee, deadline, and rules hash.

## Steps

1. Choose the active round issue labeled `round-open` and `commit-phase`.
2. Verify contract and round ID.
3. Solve the challenge locally.
4. Generate a 32-byte private salt.
5. Compute commitment bound to: contract, chain ID, round ID, entrant wallet, solution mask, salt.
6. Call `enter(roundId, commitment)` with exact entry fee.
7. During reveal phase, call `reveal(roundId, solutionMask, salt)`.
8. After finalization, winner can call `claim()`.

## Active mainnet contract

`0xe912d9f20C944864f69E5DD34b32D16880906F14`
