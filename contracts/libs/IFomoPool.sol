// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

interface IFomoPool {
    function participateLottery(
        address participant, 
        uint256 purchasePrice, 
        uint256 purchaseTime,
        uint256 stableAmount
    ) external;
}