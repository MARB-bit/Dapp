// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import './libs/IERC20Metadata.sol';
import './libs/IERC20.sol';

contract TestFomoPoolV1 {

    // These parameters can be modified to adjust the contract behavior for easier testing
    uint256 public MIN_PRIZE_POOL = 1000;  // Minimum Prize Pool Amount
    uint256 public EARLY_ROUND_DURATION = 115200;   // Draw time after meeting minimum amount for first 10 rounds (block count, 24 hours on Base chain)
    uint256 public NORMAL_ROUND_DURATION = 115200;  // Round duration starting from round 11 (block count, 24 hours on Base chain)
    uint256 public LUCKY_PRIZE_PERCENTAGE = 4500;  // Lucky prize percentage (45% = 4500/10000)
    uint256 public CONTRIBUTION_PRIZE_PERCENTAGE = 4500; // Contribution prize percentage (45% = 4500/10000)
    uint256 public ROLLOVER_PERCENTAGE = 1000;     // Rollover percentage (10% = 1000/10000)
    uint256 public EARLY_ROUNDS_LIMIT = 10;        // Early rounds limit
    uint256 public constant BASIS_POINTS = 10000;  // Basis points denominator
    // ========================================================

    // USDC contract address (needs to be set to USDC address on Base chain)
    IERC20 public immutable USDC;

    // Contract administrator
    address public owner;

    // Authorized mining pool contract address
    address public miningPool;

    // Participant information structure
    struct Participant {
        address wallet;        // Wallet address
        uint256 purchasePrice; // Purchase price (recorded value)
        uint256 purchaseTime;  // Purchase time (block number)
        uint256 round;         // Participation round
        uint256 usdcAmount;    // USDC amount transferred
    }

    // Round information structure
    struct RoundInfo {
        uint256 roundNumber;           // Round number
        uint256 totalPrizePool;        // Total prize pool amount
        uint256 startTime;             // Round start time (block number)
        uint256 lastTradeTime;         // Last trade time (block number, for Normal rounds)
        uint256 minPrizePoolReachedTime; // Time when minimum amount was reached (block number, for Early rounds)
        uint256 endTime;               // Round end time (block number)
        bool isFinalized;              // Whether completed

        // New: Lucky prize candidate and contribution prize circular queue for this round
        Participant luckyCandidate;
        Participant[10] contributionCandidates;
        uint256 contributionCount;
        uint256 contributionHead;
        // Prize information
        uint256 luckyPrizeAmount;           // Lucky prize amount
        uint256 contributionPrizeAmount;    // Total contribution prize amount
        uint256 contributionPrizePerAmount; // Contribution prize per person amount
    }

    // Current round
    uint256 public currentRound = 0;

    // Round information mapping
    mapping(uint256 => RoundInfo) public rounds;

    // User claimed rewards record: user address => round => whether claimed
    mapping(address => mapping(uint256 => bool)) public winnerRoundClaimed;

    // Events
    event ParticipantAdded(address indexed participant, uint256 round, uint256 purchasePrice, uint256 purchaseTime, uint256 usdcAmount);
    event RoundFinalized(uint256 indexed round, address luckyWinner, uint256 luckyPrizeAmount, uint256 contributionPrizeAmount, uint256 contributionPrizePerAmount, address[] contributionWinners);
    event RewardClaimed(address indexed winner, uint256 indexed round, uint256 amount, uint8 indexed winType);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyMiningPool() {
        require(msg.sender == miningPool, "Only mining pool can call this function");
        _;
    }

    constructor(address _usdcAddress) {
        USDC = IERC20(_usdcAddress);
        MIN_PRIZE_POOL = MIN_PRIZE_POOL * 10 ** IERC20Metadata(_usdcAddress).decimals();
        owner = msg.sender;
        _startNewRound();
    }

    /**
     * Set mining pool contract address (admin only)
     */
    function setMiningPool(address _miningPool) external onlyOwner {
        miningPool = _miningPool;
    }

        /**
     * Update test parameters (admin only)
     */
    function updateTestParameters(
        uint256 _minPrizePool,
        uint256 _earlyRoundDuration,
        uint256 _normalRoundDuration,
        uint256 _luckyPrizePercentage,
        uint256 _contributionPrizePercentage,
        uint256 _rolloverPercentage,
        uint256 _earlyRoundsLimit
    ) external onlyOwner {
        MIN_PRIZE_POOL = _minPrizePool;
        EARLY_ROUND_DURATION = _earlyRoundDuration;
        NORMAL_ROUND_DURATION = _normalRoundDuration;
        LUCKY_PRIZE_PERCENTAGE = _luckyPrizePercentage;
        CONTRIBUTION_PRIZE_PERCENTAGE = _contributionPrizePercentage;
        ROLLOVER_PERCENTAGE = _rolloverPercentage;
        EARLY_ROUNDS_LIMIT = _earlyRoundsLimit;

        // Ensure percentage sum does not exceed 100% (basis points)
        require(_luckyPrizePercentage + _contributionPrizePercentage + _rolloverPercentage <= BASIS_POINTS,
            "Total percentage cannot exceed 100%");
    }

    /**
     * Participate in lottery (only mining pool contract can call)
     * @param participant Participant wallet address
     * @param purchasePrice Purchase price (recorded value)
     * @param purchaseTime Purchase time (block number)
     * @param usdcAmount USDC amount transferred
     */
    function participateLottery(
        address participant,
        uint256 purchasePrice,
        uint256 purchaseTime,
        uint256 usdcAmount
    ) external onlyMiningPool {
        require(participant != address(0), "Invalid participant address");
        require(usdcAmount > 0, "USDC amount must be greater than 0");

        // Transfer USDC to contract
        require(USDC.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        // Check if round update is needed
        _checkAndUpdateRound(true);

        // Add to current round prize pool
        rounds[currentRound].totalPrizePool += usdcAmount;

        // After adding to prize pool, check if we should start countdown (only for early rounds)
        if (currentRound <= EARLY_ROUNDS_LIMIT &&
        rounds[currentRound].totalPrizePool >= MIN_PRIZE_POOL &&
            rounds[currentRound].minPrizePoolReachedTime == 0) {
            rounds[currentRound].minPrizePoolReachedTime = block.number;
        }

        // Create participant information
        Participant memory newParticipant = Participant({
            wallet: participant,
            purchasePrice: purchasePrice,
            purchaseTime: purchaseTime,
            round: currentRound,
            usdcAmount: usdcAmount
        });

        // Process prize positions
        _processParticipantForPrizes(newParticipant);

        emit ParticipantAdded(participant, currentRound, purchasePrice, purchaseTime, usdcAmount);
    }

    /**
     * Check and update round
     */
    function _checkAndUpdateRound(bool fromMining) internal {
        RoundInfo storage currentRoundInfo = rounds[currentRound];

        bool shouldUpdateRound = false;

        if (currentRound <= EARLY_ROUNDS_LIMIT) {
            // Early rounds: need prize pool > minimum amount and specified blocks elapsed since reaching minimum amount
            if (rounds[currentRound].totalPrizePool >= MIN_PRIZE_POOL &&
            rounds[currentRound].minPrizePoolReachedTime > 0 &&
                block.number >= rounds[currentRound].minPrizePoolReachedTime + EARLY_ROUND_DURATION) {
                shouldUpdateRound = true;
            }
        } else {
            // Later rounds: only need specified blocks elapsed (calculated from last trade time)
            if (block.number >= currentRoundInfo.lastTradeTime + NORMAL_ROUND_DURATION) {
                shouldUpdateRound = true;
            }
        }

        if (shouldUpdateRound) {
            _finalizeCurrentRound();
            _startNewRound();
        } else if (currentRound > EARLY_ROUNDS_LIMIT && fromMining) {
            // Later rounds, update last trade time when someone participates
            currentRoundInfo.lastTradeTime = block.number;
        }
    }
    

    /**
     * Finalize current round and automatically distribute prizes
     */
    function _finalizeCurrentRound() internal {
        RoundInfo storage roundInfo = rounds[currentRound];

        // Record round end time
        roundInfo.endTime = block.number;

        // Mark as completed
        roundInfo.isFinalized = true;

        // Calculate prize amounts (using basis points)
        uint256 totalPrize = roundInfo.totalPrizePool;
        uint256 luckyPrizeAmount = (totalPrize * LUCKY_PRIZE_PERCENTAGE) / BASIS_POINTS;
        uint256 contributionTotalPrize = (totalPrize * CONTRIBUTION_PRIZE_PERCENTAGE) / BASIS_POINTS;
        uint256 contributionPrizePerWinner = 0;

        // Distribute lucky prize
        if (roundInfo.luckyCandidate.wallet != address(0)) {
            rounds[currentRound].luckyPrizeAmount = luckyPrizeAmount;
        }

        // Distribute contribution prize
        address[] memory contributionWinners = new address[](roundInfo.contributionCount);
        if (roundInfo.contributionCount > 0) {
            contributionPrizePerWinner = contributionTotalPrize / roundInfo.contributionCount;
            rounds[currentRound].contributionPrizeAmount = contributionTotalPrize;
            rounds[currentRound].contributionPrizePerAmount = contributionPrizePerWinner;

            for (uint256 i = 0; i < roundInfo.contributionCount; i++) {
                address winner = roundInfo.contributionCandidates[i].wallet;
                if (winner != address(0)) {
                    contributionWinners[i] = winner;
                }
            }
        }

        // Emit round finalized event
        emit RoundFinalized(currentRound, roundInfo.luckyCandidate.wallet, luckyPrizeAmount,
            contributionTotalPrize, contributionPrizePerWinner, contributionWinners);
    }

    /**
     * Start new round
     */
    function _startNewRound() internal {
        RoundInfo memory roundInfo = rounds[currentRound];
        // Calculate rollover amount (10% from previous round, using basis points)
        uint256 rolloverAmount = (roundInfo.totalPrizePool * ROLLOVER_PERCENTAGE) / BASIS_POINTS;
        if (rolloverAmount + roundInfo.luckyPrizeAmount + roundInfo.contributionPrizeAmount > roundInfo.totalPrizePool) {
            rolloverAmount = roundInfo.totalPrizePool - roundInfo.luckyPrizeAmount - roundInfo.contributionPrizeAmount;
        }

        // Increment round
        currentRound++;

        // Initialize new round
        rounds[currentRound] = RoundInfo({
            roundNumber: currentRound,
            totalPrizePool: rolloverAmount,
            startTime: block.number,
            lastTradeTime: block.number,
            minPrizePoolReachedTime: 0,
            endTime: 0,
            isFinalized: false,
            luckyCandidate: Participant(address(0), 0, 0, 0, 0),
            contributionCandidates: [Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0),Participant(address(0),0,0,0,0)],
            contributionCount: 0,
            contributionHead: 0,
            luckyPrizeAmount: 0,
            contributionPrizeAmount: 0,
            contributionPrizePerAmount:0
        });

        // If rollover amount already reaches minimum amount when new round starts, immediately set reached time (only for early rounds)
        if (currentRound <= EARLY_ROUNDS_LIMIT && rolloverAmount >= MIN_PRIZE_POOL) {
            rounds[currentRound].minPrizePoolReachedTime = block.number;
        }
    }

    /**
     * Process participant's prize positions
     */
    function _processParticipantForPrizes(Participant memory participant) internal {
        RoundInfo storage round = rounds[currentRound];

        // Try lucky prize position
        Participant memory replacedLucky = _tryLuckyPrize(round, participant);

        if (replacedLucky.wallet != address(0)) {
            // Remove lucky prize user's contribution prize
            _removeParticipantContributionPrize(round, participant.wallet);
            // Try to put replaced user into contribution prize
            _tryContributionPrize(round, replacedLucky);
        } else if (round.luckyCandidate.wallet != participant.wallet) {
            // Remove user's previous contribution prize (if any)
            _removeParticipantContributionPrize(round, participant.wallet);
            // If didn't get lucky prize position, try contribution prize position
            _tryContributionPrize(round, participant);
        }
    }

    /**
     * Remove user's contribution prize record in current round
     */
    function _removeParticipantContributionPrize(RoundInfo storage round, address wallet) internal {
        // Check and remove contribution prize record
        for (uint256 i = 0; i < round.contributionCount; i++) {
            if (round.contributionCandidates[i].wallet == wallet) {
                // Overwrite current position with last element, then decrease count
                round.contributionCandidates[i] = round.contributionCandidates[round.contributionCount - 1];
                round.contributionCandidates[round.contributionCount - 1] = Participant(address(0), 0, 0, 0, 0);
                round.contributionCount--;
                break; // Exit when found, as same user can only appear once in contribution prize
            }
        }
    }

    /**
     * Try lucky prize position
     */
    function _tryLuckyPrize(RoundInfo storage round, Participant memory participant) internal returns (Participant memory) {
        Participant memory replaced;

        if (round.luckyCandidate.wallet == address(0)) {
            // Lucky prize position is empty, set directly
            round.luckyCandidate = participant;
        } else if (participant.purchasePrice > round.luckyCandidate.purchasePrice) {
            // New participant has higher purchase price, replace current lucky prize candidate
            replaced = round.luckyCandidate;
            round.luckyCandidate = participant;
        } else if (participant.purchasePrice == round.luckyCandidate.purchasePrice &&
            participant.purchaseTime < round.luckyCandidate.purchaseTime) {
            // Same purchase price but earlier time, replace current lucky prize candidate
            replaced = round.luckyCandidate;
            round.luckyCandidate = participant;
        }

        return replaced;
    }

    /**
     * Try contribution prize position
     */
    function _tryContributionPrize(RoundInfo storage round, Participant memory participant) internal {
        // If participant is current lucky prize candidate, should not appear in contribution prize simultaneously
        if (participant.wallet == round.luckyCandidate.wallet) return;

        if (round.contributionCount < 10) {
            // Still have empty slots, put directly
            round.contributionCandidates[round.contributionCount] = participant;
            round.contributionCount++;
        } else {
            // Need to compare time, replace earliest one
            uint256 earliestIndex = 0;
            uint256 earliestTime = round.contributionCandidates[0].purchaseTime;

            for (uint256 i = 1; i < 10; i++) {
                if (round.contributionCandidates[i].purchaseTime < earliestTime) {
                    earliestTime = round.contributionCandidates[i].purchaseTime;
                    earliestIndex = i;
                }
            }
            // If new participant has later time, replace earliest one
            if (participant.purchaseTime > earliestTime) {
                round.contributionCandidates[earliestIndex] = participant;
            }
        }
    }

    /**
     * Claim reward
     */
    function claimReward(uint256 roundNumber) external {
        require(roundNumber <= currentRound, "Invalid round");
        if (roundNumber < currentRound) {
            _claimReward(msg.sender, roundNumber);
        } else if (roundNumber == currentRound) {
            _checkAndUpdateRound(false);
            if (roundNumber == currentRound) { // update failed
                revert("current round not finalize");
            }
            _claimReward(msg.sender, roundNumber);
        }
    }

    function _claimReward(address winner, uint256 roundNumber) internal {
        require(rounds[roundNumber].isFinalized, "Round not finalized");
        require(!winnerRoundClaimed[msg.sender][roundNumber], "Reward already claimed");

        (uint8 winType, uint256 pendingReward) = _getRoundWinnerReward(winner, roundNumber);
        if (pendingReward > 0) {
            require(USDC.transfer(msg.sender, pendingReward), "USDC transfer failed");
            winnerRoundClaimed[msg.sender][roundNumber] = true;
            emit RewardClaimed(msg.sender, roundNumber, pendingReward, winType);
        }
    }

    function _getRoundWinnerReward(address winner, uint256 roundNumber) internal view returns (uint8, uint256) {
        RoundInfo memory round = rounds[roundNumber];
        if (!round.isFinalized) {
            return (0, 0);
        }
        if (winnerRoundClaimed[winner][roundNumber]) {
            return (0, 0);
        }

        if (winner == round.luckyCandidate.wallet && round.luckyPrizeAmount > 0) {
            return (1, round.luckyPrizeAmount);
        }
        bool isContributionWinner = false;
        for (uint i = 0; i < round.contributionCount; i++) {
            if (winner == round.contributionCandidates[i].wallet) {
                isContributionWinner = true;
                break;
            }
        }
        if (isContributionWinner && round.contributionPrizePerAmount > 0) {
            return (2, round.contributionPrizePerAmount);
        }
        return (0, 0);
    }

    /**
     * Get current block number (for frontend time display)
     */
    function getCurrentBlockNumber() external view returns (uint256) {
        return block.number;
    }

    /**
     * Get current round complete information
     */
    function getCurrentRoundInfo() public view returns (RoundInfo memory) {
        return getHistoricalRoundInfo(currentRound);
    }

    /**
     * Get historical round information
     */
    function getHistoricalRoundInfo(uint256 roundNumber) public view returns (RoundInfo memory) {
        require(roundNumber > 0 && roundNumber <= currentRound, "Invalid round number");
        RoundInfo memory roundInfo = rounds[roundNumber];
        return roundInfo;
    }

    /**
     * Batch get historical round information (simplified version)
     */
    function getHistoricalRoundsSummary(uint256 startRound, uint256 endRound) external view returns (RoundInfo[] memory) {
        require(startRound > 0 && startRound <= endRound, "Invalid round range");
        require(endRound <= currentRound, "End round exceeds current round");

        uint256 count = endRound - startRound + 1;
        RoundInfo[] memory historicalRounds = new RoundInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 roundNum = startRound + i;
            historicalRounds[i] = rounds[roundNum];
        }
        return historicalRounds;
    }

    /**
     * Check if user has claimed reward
     */
    function isRewardClaimed(address user, uint256 roundNumber) public view returns (bool) {
        return winnerRoundClaimed[user][roundNumber];
    }

    /**
     * Batch check user's reward status for multiple rounds
     */
    function getUserRewardStatus(address user, uint256[] calldata roundNumbers) public view returns (
        uint256[] memory pendingAmounts,
        bool[] memory claimedStatus
    ) {
        uint256 length = roundNumbers.length;
        pendingAmounts = new uint256[](length);
        claimedStatus = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 roundNum = roundNumbers[i];
            (, uint256 pendingReward) = _getRoundWinnerReward(user, roundNum);
            pendingAmounts[i] = pendingReward;
            claimedStatus[i] = winnerRoundClaimed[user][roundNum];
        }
    }


        /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
