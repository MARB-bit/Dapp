// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './libs/Utils.sol';
import './libs/ISwapRouter.sol';
import './libs/IPoolFactory.sol';
import './libs/SafeERC20.sol';
import './libs/SafeMath.sol';
import './libs/IERC20Metadata.sol';
import './libs/IDeployMiningPoolParams.sol';
import "./libs/IFomoPool.sol";
import './libs/IMiningWhiteList.sol';

contract MiningPool is IDeployMiningPoolParams {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint public constant LP_RELEASE_PERCISION = 1000000;
    uint public constant RATE_PERCISION = 10000;
    uint public constant UNIT_PERCISION = 1e12;

    uint256 public devClaimedMintToken;
    uint256 public epochReleaseRate;
    uint256 public epoch;
    address public creator;
    address public dev;
    address public rooter;
    address public operating;

    address public immutable factory;
    address public immutable pair;
    address public immutable stableToken;
    address public immutable mintToken;
    uint256 public immutable epochBlocks;
    uint256 public immutable startBlock;

    uint256 public totalLPH;
    uint256 public totalInvested;
    uint256 public usersBalance;
    uint256 public usersUnitAcc;

    uint256 public sellUserRate;
    uint256 public sellBuybackRate;
    uint256 public lphRate = 10400;
    uint256 public userSwapUEdgeRate = 1000;
    uint256 public userSwapULimitPoolRate = 500;
    uint256 public userSwapULimitUserRate = 5000;
    struct User {
        address leader;
        uint256 level;
        uint256 lph;
        uint256 investedAcc;
        uint256 rewardAcc;
        uint256 referencesRewardAcc;
        uint256 rewardDebt;
    }
    address[] public accounts;
    mapping(address => User) public users;
    mapping(address => address[]) public references;
    mapping (address => bytes) public inWhiteList; // user address : whitelist name

    uint256[4] public assignRewards;        // lph, preach, dev, dev stable token
    uint256[3] public assignRewardsRate;    // lph, preach, dev
    uint256[4] public assignBuyStableRate;  // lp, preach, fomo, dev
    address public preachRewardPool;
    IFomoPool public fomoPool;
    IMiningWhiteList public miningWhitelist;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRateParams();
    error InvalidRewardAmount();
    error InvalidWhiteName();
    error InvalidLPHRate();
    error InvalidLeader();
    error Unauthorized(address caller);
    error DisableReleaseFutureRewards();
    error UserAlreadyInWhite(address user);
    error InvalidEpochReleaseRate();
    error NotCreator(address user);

    event ReleaseRewards(uint removedLpAmount, uint remainLpAmount, uint rewardAmount, uint blockTime, uint epoch, uint addUnitAcc);
    event Buy(address indexed account, uint amountIn, uint lph, uint blockTime, uint32 uType);
    event Harvested(address indexed account, uint amount, uint blockTime);
    event NewUser(address indexed account, address indexed leader);
    event OperatingReceived(address indexed token, uint256 amount, uint64 indexed timestamp, uint8 indexed fromT);

    event ChangeFomoPool(address fomoPool);
    event ChangePreachRewardPool(address preachRewardPool);
    event ChangeAssignRewardsRate(uint256 releaseRateForLPH, uint256 releaseRateForPreach, uint256 releaseRateForDev);
    event ChangeOperatingAccount(address operating);
    event ChangeUserSwapULimitRates(uint256 userSwapUEdgeRate, uint256 userSwapULimitPoolRate, uint256 userSwapULimitUserRate);

    modifier onlyCreator() {
        if (msg.sender != creator) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyFactoryOwner() {
        if (msg.sender != IPoolFactory(factory).factoryOwner()) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyRooter() {
        if (msg.sender != rooter) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    constructor() {
        DeployMiningPoolParams memory params = IPoolFactory(msg.sender).deployParams();
        factory = params.factory;
        creator = tx.origin;
        rooter = params.creator;
        pair = params.pair;
        stableToken = params.stableToken;
        mintToken = params.mintToken;
        epochReleaseRate = params.epochReleaseRate;
        epochBlocks = params.epochBlocks;
        startBlock = params.startBlock;
        sellUserRate = params.sellUserRate;
        sellBuybackRate = params.sellBuybackRate;
        dev = tx.origin;

        assignRewardsRate[0] = params.rateForLPH;
        assignRewardsRate[1] = uint256(params.rateForPreach);
        assignRewardsRate[2] = uint256(params.rateForDev);
        assignBuyStableRate[0] = params.rateStableForPool;
        assignBuyStableRate[1] = params.rateStableForPreach;
        assignBuyStableRate[2] = params.rateStableForFomo;
        assignBuyStableRate[3] = params.rateStableForDev;
        preachRewardPool = params.preachRewardPool;
        fomoPool = IFomoPool(params.fomoPool);
        miningWhitelist = IMiningWhiteList(params.miningWhitelist);
        miningWhitelist.setMiningPool(address(this));
        operating = params.operating;

        address router = IPoolFactory(msg.sender).swapRouter();
        IERC20(params.stableToken).safeApprove(router,type(uint256).max);
        IERC20(params.mintToken).safeApprove(router,type(uint256).max);
        IERC20(params.pair).safeApprove(router,type(uint256).max);
    }

    function setRooter(address newRooter) public onlyFactoryOwner {
        if (newRooter == address(0)) {
            revert InvalidAddress();
        }
        rooter = newRooter;
    }

    function buy(uint amount, address leader) public {
        if(amount > 0 && amount < 20 * 10 ** IERC20Metadata(stableToken).decimals()) {
            revert InvalidAmount();
        }
        buy3(amount, leader, msg.sender);
    }

    function buy3(uint amount, address leader, address receiver) internal {

        User storage user = users[receiver];
        // New user, Set leader
        if(user.leader == address(0) && accounts.length == 0){
            if (amount == 0) {
                revert InvalidAmount();
            }
            if (receiver != creator) {
                revert NotCreator(receiver);
            }
            accounts.push(receiver);
            user.leader = address(1);
            user.level = 1;
            emit NewUser(receiver, address(1));
        }else if(user.leader == address(0)){
            if (amount == 0) {
                revert InvalidAmount();
            }
            if (users[leader].lph == 0) {
                revert InvalidLeader();
            }
            user.level = users[leader].level.add(1);
            user.leader = leader;
            accounts.push(receiver);
            references[leader].push(receiver);
            emit NewUser(receiver, leader);
        }
        // Reward
        if (user.lph > 0){
           userLphHarvest(user, receiver);
        }
        // invest
        if (amount > 0) {
            uint receivedAmount = _transferFrom(msg.sender, stableToken, amount);
            uint poolAmount = receivedAmount.mul(assignBuyStableRate[0]).div(RATE_PERCISION);
            uint preachAmount = receivedAmount.mul(assignBuyStableRate[1]).div(RATE_PERCISION);
            uint fomoAmount = receivedAmount.mul(assignBuyStableRate[2]).div(RATE_PERCISION);

            // swap & allocate
            ISwapRouter.SwapResult memory result = _addLiquidity(poolAmount);
            if (preachAmount > 0) {
                IERC20(stableToken).safeTransfer(preachRewardPool, preachAmount);
            }
            if (fomoAmount > 0) {
                uint buyPrice = result.amountInput * 1e18 / result.amountOut; // tokenIn per tokenOut
                IERC20(stableToken).approve(address(fomoPool), fomoAmount);
                fomoPool.participateLottery(msg.sender, buyPrice, block.timestamp, fomoAmount);
            }
            if (receivedAmount > (poolAmount + preachAmount + fomoAmount)) {
                uint devAmount = receivedAmount.sub(poolAmount).sub(preachAmount).sub(fomoAmount);
                IERC20(stableToken).safeTransfer(dev, devAmount);
            }

            // calc lph
            userLphInvest(user, receiver, receivedAmount, 1);
        }
        users[receiver].rewardDebt = usersUnitAcc.mul(users[receiver].lph).div(UNIT_PERCISION);
    }

    function buyBack(uint amount, address receiver) internal {
        User storage user = users[receiver];
        // Reward
        if (user.lph > 0){
            userLphHarvest(user, receiver);
        }
        // invest
        if (amount > 0) {
            _addLiquidity(amount);
            // calc lph
            userLphInvest(user, receiver, amount, 2);
        }
        users[receiver].rewardDebt = usersUnitAcc.mul(users[receiver].lph).div(UNIT_PERCISION);
    }

    function userLphHarvest(User storage user, address receiver) internal {
        if (user.lph == 0){
            return;
        }
        uint256 pending = user.lph.mul(usersUnitAcc).div(UNIT_PERCISION) - user.rewardDebt;
        if (pending > 0 && usersBalance >= pending) {
            usersBalance = usersBalance.sub(pending);
            IERC20(mintToken).safeTransfer(receiver, pending);
            user.rewardAcc = user.rewardAcc.add(pending);
            users[user.leader].referencesRewardAcc = users[user.leader].referencesRewardAcc.add(pending);
            emit Harvested(receiver, pending, block.timestamp);
        }
    }

    function userLphInvest(User storage user, address receiver, uint256 receivedAmount, uint32 uType) internal {
        if (receivedAmount == 0) {
            return;
        }
        // calc lph
        uint256 lph = uType == 1?getLPH(receivedAmount):receivedAmount.mul(100).div(10 ** IERC20Metadata(stableToken).decimals());
        if(uType == 1){
            bytes memory inWhite = inWhiteList[msg.sender];
            if(inWhite.length > 0){ // white addition
                IMiningWhiteList.WhiteList memory whitelist = miningWhitelist.getWhitelist(inWhite);
                if (whitelist.rateAddition > 0 && whitelist.rateAdditionEndBlock >= block.number) {
                    lph = lph.add(lph.mul(whitelist.rateAddition).div(RATE_PERCISION));
                }
            }
        }
        user.lph = user.lph.add(lph);
        totalLPH = totalLPH.add(lph);
        totalInvested = totalInvested.add(receivedAmount);
        user.investedAcc = user.investedAcc.add(receivedAmount);
        emit Buy(receiver, receivedAmount, lph, block.timestamp, uType);
    }

    function sell(uint amount) external {
        if (amount == 0) {
            revert InvalidAmount();
        }
        ISwapRouter router = ISwapRouter(IPoolFactory(factory).swapRouter());
        uint sellMax = getSellAmountMax(router, msg.sender);
        if(amount > sellMax) {
            revert InvalidAmount();
        }
        uint receivedAmount = _transferFrom(msg.sender, mintToken, amount);
        address[] memory path = new address[](2);
        path[0] = mintToken;
        path[1] = stableToken;
        ISwapRouter.SwapResult memory result = router.swapExactTokensForTokensSupportingFeeOnTransferTokens(receivedAmount, 1, path, address(this), type(uint256).max);

        uint toUserAmount = result.amountOut.mul(sellUserRate) / RATE_PERCISION;
        uint buyBackAmount = result.amountOut.mul(sellBuybackRate) / RATE_PERCISION;
        IERC20(stableToken).safeTransfer(msg.sender, toUserAmount);
        if (result.amountOut > (toUserAmount + buyBackAmount)) {
            uint toOperatingAmount = result.amountOut.sub(toUserAmount).sub(buyBackAmount);
            IERC20(stableToken).safeTransfer(operating, toOperatingAmount);
            emit OperatingReceived(stableToken, toOperatingAmount, uint64(block.timestamp), 1);
        }
        buyBack(buyBackAmount, msg.sender);
    }

    function getSellAmountMax(ISwapRouter router, address userAddress) public view returns (uint256 amountMintIn) {
        (uint reverseMint,uint reverseStable) = router.getReserves(mintToken, stableToken);
        User memory user = users[userAddress];
        // function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, address token0, address token1) public view override returns (uint amountIn)
        if(user.investedAcc >= reverseStable.mul(userSwapUEdgeRate).div(RATE_PERCISION)) {
            amountMintIn = router.getAmountIn(reverseStable.mul(userSwapULimitPoolRate).div(RATE_PERCISION), reverseMint,reverseStable, mintToken, stableToken);
        } else {
            amountMintIn = router.getAmountIn(user.investedAcc.mul(userSwapULimitUserRate).div(RATE_PERCISION), reverseMint, reverseStable, mintToken, stableToken);
        }
    }

    function claimLPHRewards() external {
        buy(0, address(0));
    }

    function releaseCheck() external view returns (uint256 curEpochIndex, bool canRelease) {
        curEpochIndex = epoch;
        canRelease = block.number > startBlock && (block.number.sub(startBlock + epochBlocks.mul(epoch))) > epochBlocks;
    }

    function releaseRewards() external {
        if (assignRewardsRate[0] + assignRewardsRate[1] + assignRewardsRate[2] != RATE_PERCISION) {
            revert InvalidRateParams();
        }
        if (!(block.number > startBlock && (block.number.sub(startBlock + epochBlocks.mul(epoch))) > epochBlocks)) {
            revert DisableReleaseFutureRewards();
        }

        uint lpAmount = IERC20(pair).balanceOf(address(this)).mul(epochReleaseRate) / LP_RELEASE_PERCISION;
        uint balanceBefore = IERC20(mintToken).balanceOf(address(this));
        _removeLiquidityForRewards(lpAmount);
        uint rewardAmount = IERC20(mintToken).balanceOf(address(this)).sub(balanceBefore);
        if (rewardAmount == 0) {
            revert InvalidRewardAmount();
        }

        uint rateForLPH = assignRewardsRate[0];
        uint rateForPreach = assignRewardsRate[1];
        uint rateForDev = assignRewardsRate[2];

        uint rewardForLPH = rewardAmount.mul(rateForLPH).div(RATE_PERCISION);
        uint addUnitAcc = rewardForLPH.mul(UNIT_PERCISION).div(totalLPH);
        usersUnitAcc = usersUnitAcc.add(addUnitAcc);
        usersBalance = usersBalance.add(rewardForLPH);

        uint rewardForDev = rewardAmount.mul(rateForDev).div(RATE_PERCISION);
        uint preachReward = rewardAmount.mul(rateForPreach).div(RATE_PERCISION);

        assignRewards[0] = assignRewards[0].add(rewardForLPH); // LPH
        assignRewards[1] = assignRewards[1].add(preachReward); // Preach
        assignRewards[2] = assignRewards[2].add(rewardForDev); // Dev
        if (preachReward > 0) {
            IERC20(mintToken).safeTransfer(preachRewardPool, preachReward);
        }
        epoch = epoch.add(1);
        emit ReleaseRewards(lpAmount, IERC20(pair).balanceOf(address(this)), rewardAmount, block.timestamp, epoch, addUnitAcc);
    }

    function setDev(address _dev) public onlyCreator {
        if(_dev == address(0)) {
            revert InvalidAddress();
        }   
        dev = _dev;
    }

    function devClaimRewardsFromRelease(uint256 amount) public {
        if (msg.sender != dev) {
            revert Unauthorized(msg.sender);
        }
        if(amount == 0 || amount > assignRewards[2].sub(devClaimedMintToken)) {
            revert InvalidAmount();
        }
        devClaimedMintToken = devClaimedMintToken.add(amount);
        IERC20(mintToken).safeTransfer(dev, amount);
    }

    function _transferFrom(address from,address token,uint amount) internal returns(uint receivedAmount){
        uint beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(from, address(this), amount);
        return IERC20(token).balanceOf(address(this)).sub(beforeBalance);
    }

    function _addLiquidity(uint _amount) internal returns (ISwapRouter.SwapResult memory) {
        uint amountHalf = _amount / 2;
        ISwapRouter router = ISwapRouter(IPoolFactory(factory).swapRouter());
        address[] memory path = new address[](2);
        path[0] = stableToken;
        path[1] = mintToken;
        ISwapRouter.SwapResult memory result = router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountHalf,1,path,address(this),type(uint256).max);
        (uint amountA, uint amountB,) = router.addLiquidity(stableToken, mintToken, amountHalf, result.amountOut, 1, 1, address(this), type(uint256).max);
        if(_amount > (result.amountInput+amountA)){
            uint256 toOperatingAmount = _amount.sub(result.amountInput).sub(amountA);
            IERC20(stableToken).safeTransfer(operating, toOperatingAmount);
            emit OperatingReceived(stableToken, toOperatingAmount, uint64(block.timestamp), 0);
        }
        if(result.amountOut > amountB){
            uint256 toOperatingAmount = result.amountOut.sub(amountB);
            IERC20(mintToken).safeTransfer(operating, toOperatingAmount);
            emit OperatingReceived(mintToken, toOperatingAmount, uint64(block.timestamp), 0);
        }
        return result;
    }

    function _removeLiquidityForRewards(uint lpAmount) internal {
        if(lpAmount == 0){
            return;
        }
        ISwapRouter router = ISwapRouter(IPoolFactory(factory).swapRouter());
        router.removeLiquidity(stableToken, mintToken, lpAmount, 1, 1, address(this), type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = stableToken;
        path[1] = mintToken;
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(IERC20(path[0]).balanceOf(address(this)),1,path,address(this),type(uint256).max);
    }

    function transferCreator(address newCreator) external onlyCreator {
        if (newCreator == address(0)) {
            revert InvalidAddress();
        }
        creator = newCreator;
    }

    function getAssignRewards() external view returns (uint256[4] memory) {
        return assignRewards;
    }

    function getReferences(address leader, uint startPos) external view
    returns (uint length, address[] memory data) {
        address[] memory refs = references[leader];
        length = uint(refs.length);
        if(startPos >= length) {
            return (length, new address[](0));
        }
        uint256 endPos = startPos + 10;
        if(endPos > length){
            endPos = length;
        }
        data = new address[](endPos - startPos);
        for(uint i = 0; i < 10 && (i+startPos) < endPos; i++) {
            data[i] = refs[i+startPos];
        }
    }

    function accountsCount() external view returns (uint) {
        return accounts.length;
    }

    function referencesCount(address account) external view returns (uint256) {
        return references[account].length;
    }

    function getLPH(uint256 amount) public view returns(uint256) {
        uint256 epochs = startBlock > block.number ? 0 : (block.number - startBlock) / epochBlocks;
        uint256 rise = Utils.lphRise(epochs, lphRate);
        return amount.mul(rise).div(10 ** IERC20Metadata(stableToken).decimals() * 100);
    }

    function getLPHRewardAcc(address account) external view returns (uint256) {
        User storage user = users[account];
        if (user.lph == 0){
            return 0;
        }
        return user.lph.mul(usersUnitAcc).div(UNIT_PERCISION).sub(user.rewardDebt).add(user.rewardAcc);
    }

    function changeFomoPool(IFomoPool newPool) public onlyFactoryOwner {
        if (address(newPool) == address(0)) {
            revert InvalidAddress();
        }
        fomoPool = newPool;
        emit ChangeFomoPool(address(fomoPool));
    }

    function changePreachRewardPool(address newPool) public onlyFactoryOwner {
        if (newPool == address(0)) {
            revert InvalidAddress();
        }
        preachRewardPool = newPool;
        emit ChangePreachRewardPool(preachRewardPool);
    }

    function changeOperatingAccount(address _operating) public onlyRooter {
        if(_operating == address(0)){
            revert InvalidAddress();
        }
        operating = _operating;
        emit ChangeOperatingAccount(operating);
    }

    function setEpochReleaseRate(uint256 _epochReleaseRate) public onlyRooter {
        if(_epochReleaseRate<1 || _epochReleaseRate > 15000){
            revert InvalidEpochReleaseRate();
        }
        epochReleaseRate = _epochReleaseRate;
    }

    function setLphRate(uint256 _lphRate) public onlyRooter {
        if(_lphRate < 10000 || _lphRate > 18000){
            revert InvalidLPHRate();
        }
        lphRate = _lphRate;
    }

    function setUserSwapULimitRate(uint256 _userSwapULimitPoolRate, uint256 _userSwapULimitUserRate, uint256 _userSwapUEdgeRate) public onlyRooter {
        if(_userSwapULimitPoolRate < 0 || _userSwapULimitPoolRate > RATE_PERCISION ||
            _userSwapULimitUserRate < 0 || _userSwapULimitUserRate > RATE_PERCISION ||
            _userSwapUEdgeRate < 0 || _userSwapUEdgeRate > RATE_PERCISION) {
            revert InvalidRateParams();
        }
        userSwapULimitPoolRate = _userSwapULimitPoolRate;
        userSwapULimitUserRate = _userSwapULimitUserRate;
        userSwapUEdgeRate = _userSwapUEdgeRate;
        emit ChangeUserSwapULimitRates(_userSwapUEdgeRate, _userSwapULimitPoolRate, _userSwapULimitUserRate);
    }

    function setAssignRewardsRate(uint256[3] memory _ratesForRelease) public onlyRooter {
        if (_ratesForRelease[0] + _ratesForRelease[1] + _ratesForRelease[2] != RATE_PERCISION) {
            revert InvalidRateParams();
        }
        assignRewardsRate[0] = _ratesForRelease[0];
        assignRewardsRate[1] = _ratesForRelease[1];
        assignRewardsRate[2] = _ratesForRelease[2];
        emit ChangeAssignRewardsRate(assignRewardsRate[0], assignRewardsRate[1], assignRewardsRate[2]);
    }

    function addWhiteUsers(bytes memory whiteName, address[] memory _users) external {
        if (msg.sender != address(miningWhitelist)) {
            revert Unauthorized(msg.sender);
        }
        if (whiteName.length == 0) {
            revert InvalidWhiteName();
        }
        for (uint i = 0; i < _users.length; i++) {
            if (_users[i] == address(0)) {
                revert InvalidAddress();
            }
            if (inWhiteList[_users[i]].length > 0) {
                revert UserAlreadyInWhite(_users[i]);
            }
        }
        for (uint i = 0; i < _users.length; i++) {
            inWhiteList[_users[i]] = whiteName;
        }
    }

    function delWhiteUsers(address[] memory _users) external {
        if (msg.sender != address(miningWhitelist)) {
            revert Unauthorized(msg.sender);
        }
        for (uint i = 0; i < _users.length; i++) {
            if (_users[i] == address(0)) {
                revert InvalidAddress();
            }
        }
        for (uint i = 0; i < _users.length; i++) {
            delete(inWhiteList[_users[i]]);
        }
    }
}