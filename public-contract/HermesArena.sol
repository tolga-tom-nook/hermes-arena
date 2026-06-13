// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title HermesArena
/// @notice On-chain skill tournament for autonomous agents. Agents compete; best verified score wins.
/// @dev v1 is a deterministic multi-constraint knapsack arena. The contract is the judge.
contract HermesArena {
    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_TREASURY_BPS = 2_000;
    uint16 public constant MAX_ITEMS = 128;
    uint16 public constant MAX_CATEGORIES = 32;

    enum Phase { Created, CommitOpen, RevealOpen, Finalized, Cancelled }

    struct Item {
        uint32 value;
        uint32 weight;
        uint32 risk;
        uint16 category;
    }

    struct RoundConfig {
        uint96 entryFee;
        uint64 commitDeadline;
        uint64 revealDeadline;
        uint32 maxWeight;
        uint32 maxRisk;
        uint16 maxItems;
        uint32 maxEntrants;
        uint16 winnerBps;
        uint16 treasuryBps;
        uint16 reserveBps;
        bytes32 rulesHash;
        bool allowZeroEntry;
    }

    struct RoundState {
        bool finalized;
        bool cancelled;
        uint32 entrantCount;
        uint256 totalPool;
        address winner;
        uint256 bestScore;
        uint256 bestWeight;
        uint256 bestRisk;
        uint256 bestCommitBlock;
        bytes32 bestCommitment;
        uint256 winnerPayout;
        uint256 treasuryPayout;
        uint256 reservePayout;
    }

    struct Entrant {
        bool entered;
        bool revealed;
        bool refunded;
        bytes32 commitment;
        uint256 commitBlock;
        uint64 commitTimestamp;
    }

    address public immutable owner;
    address public immutable treasury;
    uint256 public nextRoundId = 1;
    uint256 public nextRoundReserve;
    bool public paused;
    bool private locked;

    mapping(uint256 => RoundConfig) public roundConfigs;
    mapping(uint256 => RoundState) public roundStates;
    mapping(uint256 => Item[]) private roundItems;
    mapping(uint256 => uint16[]) private roundCategoryLimits;
    mapping(uint256 => mapping(address => Entrant)) public entrants;
    mapping(address => uint256) public claimableBalances;

    event RoundCreated(uint256 indexed roundId, uint96 entryFee, uint64 commitDeadline, uint64 revealDeadline, uint32 maxEntrants, bytes32 rulesHash);
    event RoundEntered(uint256 indexed roundId, address indexed entrant, uint256 entryFee);
    event SolutionCommitted(uint256 indexed roundId, address indexed entrant, bytes32 commitment, uint256 commitBlock);
    event SolutionRevealed(uint256 indexed roundId, address indexed entrant, uint256 solutionMask, bytes32 salt);
    event ScoreAccepted(uint256 indexed roundId, address indexed entrant, uint256 score, uint256 totalWeight, uint256 totalRisk, uint256 itemCount);
    event ScoreRejected(uint256 indexed roundId, address indexed entrant, uint256 solutionMask, string reason);
    event LeaderUpdated(uint256 indexed roundId, address indexed leader, uint256 score, uint256 totalWeight, uint256 totalRisk, bytes32 commitment);
    event RoundFinalized(uint256 indexed roundId, address indexed winner, uint256 totalPool);
    event PayoutAllocated(uint256 indexed roundId, address indexed account, uint256 amount, string kind);
    event WithdrawalClaimed(address indexed account, uint256 amount);
    event RoundCancelled(uint256 indexed roundId, string reason);
    event RefundClaimed(uint256 indexed roundId, address indexed entrant, uint256 amount);
    event ReserveUpdated(uint256 indexed roundId, uint256 amountAdded, uint256 newReserve);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    error NotOwner();
    error PausedError();
    error Reentrancy();
    error BadRound();
    error BadTiming();
    error BadItems();
    error BadEntryFee();
    error BadPayoutSplit();
    error RoundFull();
    error AlreadyEntered();
    error NotEntered();
    error AlreadyRevealed();
    error BadCommitment();
    error Finalized();
    error Cancelled();
    error NotCancelled();
    error NothingToClaim();
    error NothingToRefund();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert PausedError();
        _;
    }

    modifier nonReentrant() {
        if (locked) revert Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    constructor(address treasury_) {
        require(treasury_ != address(0), "treasury=0");
        owner = msg.sender;
        treasury = treasury_;
    }

    receive() external payable {
        revert("direct deposits disabled");
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function createRound(
        RoundConfig calldata config,
        Item[] calldata items,
        uint16[] calldata categoryLimits
    ) external onlyOwner whenNotPaused returns (uint256 roundId) {
        _validateRoundConfig(config, items, categoryLimits);
        roundId = nextRoundId++;
        roundConfigs[roundId] = config;
        for (uint256 i; i < items.length; ++i) roundItems[roundId].push(items[i]);
        for (uint256 i; i < categoryLimits.length; ++i) roundCategoryLimits[roundId].push(categoryLimits[i]);
        emit RoundCreated(roundId, config.entryFee, config.commitDeadline, config.revealDeadline, config.maxEntrants, config.rulesHash);
    }

    function enter(uint256 roundId, bytes32 commitment) external payable whenNotPaused {
        RoundConfig storage cfg = roundConfigs[roundId];
        RoundState storage st = roundStates[roundId];
        if (cfg.revealDeadline == 0) revert BadRound();
        if (st.cancelled) revert Cancelled();
        if (st.finalized) revert Finalized();
        if (block.timestamp >= cfg.commitDeadline) revert BadTiming();
        if (msg.value != cfg.entryFee) revert BadEntryFee();
        if (st.entrantCount >= cfg.maxEntrants) revert RoundFull();
        Entrant storage e = entrants[roundId][msg.sender];
        if (e.entered) revert AlreadyEntered();
        e.entered = true;
        e.commitment = commitment;
        e.commitBlock = block.number;
        e.commitTimestamp = uint64(block.timestamp);
        st.entrantCount += 1;
        st.totalPool += msg.value;
        emit RoundEntered(roundId, msg.sender, msg.value);
        emit SolutionCommitted(roundId, msg.sender, commitment, block.number);
    }

    function reveal(uint256 roundId, uint256 solutionMask, bytes32 salt) external returns (bool valid, uint256 score, uint256 totalWeight, uint256 totalRisk, uint256 selectedCount) {
        RoundConfig storage cfg = roundConfigs[roundId];
        RoundState storage st = roundStates[roundId];
        if (cfg.revealDeadline == 0) revert BadRound();
        if (st.cancelled) revert Cancelled();
        if (st.finalized) revert Finalized();
        if (block.timestamp < cfg.commitDeadline || block.timestamp >= cfg.revealDeadline) revert BadTiming();
        Entrant storage e = entrants[roundId][msg.sender];
        if (!e.entered) revert NotEntered();
        if (e.revealed) revert AlreadyRevealed();
        if (commitmentFor(roundId, msg.sender, solutionMask, salt) != e.commitment) revert BadCommitment();

        e.revealed = true;
        emit SolutionRevealed(roundId, msg.sender, solutionMask, salt);
        string memory reason;
        (valid, score, totalWeight, totalRisk, selectedCount, reason) = scoreSolution(roundId, solutionMask);
        if (!valid) {
            emit ScoreRejected(roundId, msg.sender, solutionMask, reason);
            return (false, 0, totalWeight, totalRisk, selectedCount);
        }
        emit ScoreAccepted(roundId, msg.sender, score, totalWeight, totalRisk, selectedCount);
        if (_beatsLeader(st, score, totalWeight, totalRisk, e.commitBlock, e.commitment)) {
            st.winner = msg.sender;
            st.bestScore = score;
            st.bestWeight = totalWeight;
            st.bestRisk = totalRisk;
            st.bestCommitBlock = e.commitBlock;
            st.bestCommitment = e.commitment;
            emit LeaderUpdated(roundId, msg.sender, score, totalWeight, totalRisk, e.commitment);
        }
    }

    function finalize(uint256 roundId) external nonReentrant {
        RoundConfig storage cfg = roundConfigs[roundId];
        RoundState storage st = roundStates[roundId];
        if (cfg.revealDeadline == 0) revert BadRound();
        if (st.cancelled) revert Cancelled();
        if (st.finalized) revert Finalized();
        if (block.timestamp < cfg.revealDeadline) revert BadTiming();

        st.finalized = true;
        uint256 pool = st.totalPool;
        if (st.winner == address(0)) {
            st.reservePayout = pool;
            nextRoundReserve += pool;
            emit PayoutAllocated(roundId, address(this), pool, "reserve-no-valid-reveal");
            emit ReserveUpdated(roundId, pool, nextRoundReserve);
        } else {
            uint256 winnerAmount = (pool * cfg.winnerBps) / BPS;
            uint256 treasuryAmount = (pool * cfg.treasuryBps) / BPS;
            uint256 reserveAmount = pool - winnerAmount - treasuryAmount;
            st.winnerPayout = winnerAmount;
            st.treasuryPayout = treasuryAmount;
            st.reservePayout = reserveAmount;
            claimableBalances[st.winner] += winnerAmount;
            claimableBalances[treasury] += treasuryAmount;
            nextRoundReserve += reserveAmount;
            emit PayoutAllocated(roundId, st.winner, winnerAmount, "winner");
            emit PayoutAllocated(roundId, treasury, treasuryAmount, "treasury");
            emit PayoutAllocated(roundId, address(this), reserveAmount, "reserve");
            emit ReserveUpdated(roundId, reserveAmount, nextRoundReserve);
        }
        emit RoundFinalized(roundId, st.winner, pool);
    }

    function cancelRound(uint256 roundId, string calldata reason) external onlyOwner {
        RoundConfig storage cfg = roundConfigs[roundId];
        RoundState storage st = roundStates[roundId];
        if (cfg.revealDeadline == 0) revert BadRound();
        if (st.finalized) revert Finalized();
        if (st.cancelled) revert Cancelled();
        if (block.timestamp >= cfg.commitDeadline) revert BadTiming();
        st.cancelled = true;
        emit RoundCancelled(roundId, reason);
    }

    function claimRefund(uint256 roundId) external nonReentrant {
        RoundConfig storage cfg = roundConfigs[roundId];
        RoundState storage st = roundStates[roundId];
        if (!st.cancelled) revert NotCancelled();
        Entrant storage e = entrants[roundId][msg.sender];
        if (!e.entered || e.refunded) revert NothingToRefund();
        e.refunded = true;
        st.totalPool -= cfg.entryFee;
        _safeTransfer(msg.sender, cfg.entryFee);
        emit RefundClaimed(roundId, msg.sender, cfg.entryFee);
    }

    function claim() external nonReentrant {
        uint256 amount = claimableBalances[msg.sender];
        if (amount == 0) revert NothingToClaim();
        claimableBalances[msg.sender] = 0;
        _safeTransfer(msg.sender, amount);
        emit WithdrawalClaimed(msg.sender, amount);
    }

    function commitmentFor(uint256 roundId, address entrant, uint256 solutionMask, bytes32 salt) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), block.chainid, roundId, entrant, solutionMask, salt));
    }

    function scoreSolution(uint256 roundId, uint256 solutionMask) public view returns (bool valid, uint256 score, uint256 totalWeight, uint256 totalRisk, uint256 selectedCount, string memory reason) {
        RoundConfig storage cfg = roundConfigs[roundId];
        if (cfg.revealDeadline == 0) revert BadRound();
        Item[] storage items = roundItems[roundId];
        if (items.length < 256 && (solutionMask >> items.length) != 0) return (false, 0, 0, 0, 0, "oversized-solution");
        uint16[] memory categoryCounts = new uint16[](roundCategoryLimits[roundId].length);
        for (uint256 i; i < items.length; ++i) {
            if (((solutionMask >> i) & 1) == 1) {
                Item storage item = items[i];
                selectedCount += 1;
                totalWeight += item.weight;
                totalRisk += item.risk;
                score += item.value;
                categoryCounts[item.category] += 1;
                if (selectedCount > cfg.maxItems) return (false, 0, totalWeight, totalRisk, selectedCount, "too-many-items");
                if (totalWeight > cfg.maxWeight) return (false, 0, totalWeight, totalRisk, selectedCount, "overweight");
                if (totalRisk > cfg.maxRisk) return (false, 0, totalWeight, totalRisk, selectedCount, "over-risk");
                if (categoryCounts[item.category] > roundCategoryLimits[roundId][item.category]) return (false, 0, totalWeight, totalRisk, selectedCount, "category-limit");
            }
        }
        return (true, score, totalWeight, totalRisk, selectedCount, "");
    }

    function getItems(uint256 roundId) external view returns (Item[] memory) {
        return roundItems[roundId];
    }

    function getCategoryLimits(uint256 roundId) external view returns (uint16[] memory) {
        return roundCategoryLimits[roundId];
    }

    function getRoundPayouts(uint256 roundId) external view returns (uint256 winnerPayout, uint256 treasuryPayout, uint256 reservePayout) {
        RoundState storage st = roundStates[roundId];
        return (st.winnerPayout, st.treasuryPayout, st.reservePayout);
    }

    function phase(uint256 roundId) public view returns (Phase) {
        RoundConfig storage cfg = roundConfigs[roundId];
        RoundState storage st = roundStates[roundId];
        if (cfg.revealDeadline == 0) revert BadRound();
        if (st.cancelled) return Phase.Cancelled;
        if (st.finalized) return Phase.Finalized;
        if (block.timestamp < cfg.commitDeadline) return Phase.CommitOpen;
        if (block.timestamp < cfg.revealDeadline) return Phase.RevealOpen;
        return Phase.Created;
    }

    function _validateRoundConfig(RoundConfig calldata config, Item[] calldata items, uint16[] calldata categoryLimits) internal view {
        if (!config.allowZeroEntry && config.entryFee == 0) revert BadEntryFee();
        if (config.commitDeadline <= block.timestamp || config.revealDeadline <= config.commitDeadline) revert BadTiming();
        if (items.length == 0 || items.length > MAX_ITEMS) revert BadItems();
        if (categoryLimits.length == 0 || categoryLimits.length > MAX_CATEGORIES) revert BadItems();
        if (config.maxItems == 0 || config.maxItems > items.length || config.maxEntrants == 0) revert BadItems();
        if (config.winnerBps + config.treasuryBps + config.reserveBps != BPS) revert BadPayoutSplit();
        if (config.treasuryBps > MAX_TREASURY_BPS) revert BadPayoutSplit();
        for (uint256 i; i < items.length; ++i) {
            if (items[i].category >= categoryLimits.length) revert BadItems();
        }
    }

    function _beatsLeader(RoundState storage st, uint256 score, uint256 totalWeight, uint256 totalRisk, uint256 commitBlock, bytes32 commitment) internal view returns (bool) {
        if (st.winner == address(0)) return true;
        if (score != st.bestScore) return score > st.bestScore;
        if (totalWeight != st.bestWeight) return totalWeight < st.bestWeight;
        if (totalRisk != st.bestRisk) return totalRisk < st.bestRisk;
        if (commitBlock != st.bestCommitBlock) return commitBlock < st.bestCommitBlock;
        return uint256(commitment) < uint256(st.bestCommitment);
    }

    function _safeTransfer(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
