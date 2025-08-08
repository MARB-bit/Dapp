// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

interface IMiningWhiteList {
    function setMiningPool(address _miningPool) external;
    struct WhiteList {
        bytes name;
        uint32 rateAddition;
        uint256 rateAdditionEndBlock;
    }
    function getWhitelist(bytes memory name) external view returns (WhiteList memory);
}