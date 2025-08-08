// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IDeployMiningPoolParams.sol';

interface IPoolFactory is IDeployMiningPoolParams {
    function deployParams() external view returns(DeployMiningPoolParams memory paras);
    function factoryOwner() external view returns(address);
    function swapRouter() external view returns(address);
    function miningPoolsLength() external view returns(uint256);
    function miningPools(uint256 index) external view returns(address);
    function pair2miningPool(address pair) external view returns(address);
}