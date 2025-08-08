// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './libs/ISwapFactory.sol';
import './libs/ISwapPair.sol';
import './libs/Ownable.sol';
import './MiningPool.sol';
import './libs/TransferHelper.sol';

contract PoolFactory is Ownable, IPoolFactory {
    using SafeERC20 for IERC20;

    DeployMiningPoolParams private tempDeployParams;

    uint private constant RATE_PERCISION = 10000;
    uint public miningPoolsLength;
    address public override swapRouter;
    mapping(uint256 => address) public miningPools;
    mapping(address => address) public pair2miningPool;

    error InvalidSwapRouter();
    error InvalidStableToken();
    error InvalidMintToken();
    error InvalidAmount();
    error InvalidEpochBlocks();
    error InvalidEpochReleaseRate();
    error InvalidAssignRewardsRate();
    error MiningPoolAlreadyExisted();
    error InvalidInitLpAmount();
    error InvalidFactory();
    error InvalidStartBlock();


    event MiningPoolCreated(address caller,address miningPool,uint blockTime);

    constructor(address _swapRouter){
        if(_swapRouter == address(0)){
            revert InvalidSwapRouter();
        }
        swapRouter = _swapRouter;
        ISwapRouter(swapRouter).setPoolFactory(address(this));
    }

    function createPool(CreatePoolParams calldata params) external {
        if(params.stableToken == address(0)){
            revert InvalidStableToken();
        }
        if(params.mintToken == address(0)){
            revert InvalidMintToken();
        }
        if(params.mintTokenAmount <= 0){
            revert InvalidAmount();
        }
        if(params.stableTokenAmount <= 0){
            revert InvalidAmount();
        }
        if(params.epochBlocks == 0){
            revert InvalidEpochBlocks();
        }
        if(params.epochReleaseRate > RATE_PERCISION){
            revert InvalidEpochReleaseRate();
        }
        if(params.ratesForRelease[0] + params.ratesForRelease[1] + params.ratesForRelease[2] != RATE_PERCISION) {
            revert InvalidAssignRewardsRate();
        }

        address pair = ISwapRouter(swapRouter).pairFor(params.mintToken, params.stableToken);
        if(pair2miningPool[pair] != address(0)){
            revert MiningPoolAlreadyExisted();
        }

        TransferHelper.safeTransferFrom(params.mintToken, msg.sender, pair, params.mintTokenAmount);
        TransferHelper.safeTransferFrom(params.stableToken, msg.sender, pair, params.stableTokenAmount);

        ISwapRouter(swapRouter).createPair(
            params.mintToken, params.mintTokenAmount, params.stableToken, params.stableTokenAmount,
            uint256(params.sellBurnRate), params.sellStopBurnSupply
        );

        uint256 initLpAmount = IERC20(pair).balanceOf(address(this));
        if(initLpAmount == 0){
            revert InvalidInitLpAmount();
        }
        if(ISwapPair(pair).factory() != ISwapRouter(swapRouter).factory()){
            revert InvalidFactory();
        }
        if(params.startBlock < block.number){
            revert InvalidStartBlock();
        }

        tempDeployParams.creator = owner();
        tempDeployParams.factory = address(this);
        tempDeployParams.pair = pair;
        tempDeployParams.stableToken = params.stableToken;
        tempDeployParams.mintToken = params.mintToken;
        tempDeployParams.epochReleaseRate = params.epochReleaseRate;
        tempDeployParams.epochBlocks = params.epochBlocks;
        tempDeployParams.startBlock = params.startBlock;
        tempDeployParams.sellUserRate = params.sellUserRate;
        tempDeployParams.sellBuybackRate = params.sellBuybackRate;
        tempDeployParams.rateForLPH = params.ratesForRelease[0];
        tempDeployParams.rateForDev = params.ratesForRelease[1];
        tempDeployParams.rateForPreach = params.ratesForRelease[2];
        tempDeployParams.rateStableForPool = params.ratesForStable[0];
        tempDeployParams.rateStableForPreach = params.ratesForStable[1];
        tempDeployParams.rateStableForFomo = params.ratesForStable[2];
        tempDeployParams.rateStableForDev = params.ratesForStable[3];
        tempDeployParams.preachRewardPool = params.preachRewardPool;
        tempDeployParams.fomoPool = params.fomoPool;
        tempDeployParams.miningWhitelist = params.miningWhitelist;
        tempDeployParams.operating = params.operating;

        address miningPool = address(new MiningPool{
            salt: keccak256(abi.encode(params.stableToken, params.mintToken, miningPoolsLength))
        }());

        IERC20(pair).safeTransfer(miningPool, initLpAmount);
        delete tempDeployParams;
        pair2miningPool[pair] = miningPool;
        ISwapRouter(swapRouter).setWhiteList(pair, miningPool, true);

        uint len = miningPoolsLength;
        miningPools[len] = miningPool;
        miningPoolsLength = len + 1;

        emit MiningPoolCreated(msg.sender, miningPool, block.timestamp);
    }

    function factoryOwner() external view override returns(address){
        return owner();
    }

    function deployParams() external view override returns(DeployMiningPoolParams memory){
        DeployMiningPoolParams memory item = tempDeployParams;
        return item;
    }
}