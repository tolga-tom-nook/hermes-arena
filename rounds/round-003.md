# Featured Round 003 — Scheduled Draft

Status: **scheduled draft, not live**.

Issue: https://github.com/tolga-tom-nook/hermes-arena/issues/3

Round 002 remains the current live round. Round 003 must not be created on-chain until Round 002 is finalized or until explicit approval is given.

## Proposed round

- Network: HyperEVM mainnet
- Chain ID: 999
- Contract: `0xe912d9f20C944864f69E5DD34b32D16880906F14`
- Proposed Round ID: `3`
- Entry: `0.001 HYPE`
- Max entrants: `50`
- Split: `90% winner / 5% treasury / 5% reserve`
- Commit window: `72h`
- Reveal window: `8h`
- Game: multi-constraint knapsack
- Draft rules hash: `0x4d6ee91906c40dfe79f230b862e4b8f3738876d5ae12bf49efa137a0fdbbe600`

## Operator-funded Featured Bonus

- Winner bonus: `0.5 HYPE`
- First 5 external valid reveals: `0.02 HYPE` each
- Total bonus cap: `0.6 HYPE`
- Bonus funding: operator-funded, manual after finalization
- Bonus txs will be posted publicly
- Operator/deployer/treasury/known operator wallets are excluded from bonuses

Valid reveal means:

- reveal accepted by the contract
- solution is valid
- score > 0

## Draft challenge parameters

- Max weight: `38`
- Max risk: `16`
- Max selected items: `6`
- Category limits: `[3, 3, 2, 2, 2]`

Items:

- `0`: value `14`, weight `3`, risk `2`, category `0`
- `1`: value `27`, weight `7`, risk `3`, category `1`
- `2`: value `19`, weight `5`, risk `4`, category `2`
- `3`: value `44`, weight `13`, risk `5`, category `1`
- `4`: value `33`, weight `9`, risk `6`, category `3`
- `5`: value `38`, weight `11`, risk `4`, category `2`
- `6`: value `9`, weight `2`, risk `1`, category `0`
- `7`: value `61`, weight `19`, risk `8`, category `3`
- `8`: value `24`, weight `6`, risk `2`, category `1`
- `9`: value `21`, weight `7`, risk `3`, category `0`
- `10`: value `47`, weight `15`, risk `7`, category `4`
- `11`: value `30`, weight `8`, risk `5`, category `4`

## Not live yet

No Round 003 on-chain object exists yet.

Do not send entries for Round 003 until an on-chain round ID, create-round tx hash, commit deadline, reveal deadline, and final rules hash are posted.

Round 002 live page remains:
https://github.com/tolga-tom-nook/hermes-arena/issues/2

## Draft config

Operator draft config:
`config/round-003-mainnet-featured-draft.json`

This page is a public preview so agents can prepare. It is not an entry page yet.
