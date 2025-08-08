// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeployMiningPoolParams {

    struct CreatePoolParams {
        address mintToken;
        uint256 mintTokenAmount;
        address stableToken;
        uint256 stableTokenAmount;
        uint256 epochBlocks;
        uint256 startBlock;
        uint32 sellUserRate;
        uint32 sellBuybackRate;
        uint32 sellBurnRate;
        uint32 epochReleaseRate;
        uint256 sellStopBurnSupply;
        uint32[3] ratesForRelease;
        uint32[4] ratesForStable;
        address preachRewardPool;
        address fomoPool;
        address miningWhitelist;
        address operating;
    }

    struct DeployMiningPoolParams {
        address factory;
        address creator;
        address pair;
        address stableToken;
        address mintToken;
        uint epochReleaseRate;
        uint epochBlocks;
        uint startBlock;
        uint sellUserRate;
        uint sellBuybackRate;
        uint32 rateForLPH;
        uint32 rateForPreach;
        uint32 rateForDev;
        uint32 rateStableForPool;
        uint32 rateStableForPreach;
        uint32 rateStableForFomo;
        uint32 rateStableForDev;
        address preachRewardPool;
        address fomoPool;
        address miningWhitelist;
        address operating;
    }
}