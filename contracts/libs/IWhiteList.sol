// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IWhiteList {
    struct WhiteListConfig {
        bytes name;
        uint32 rate;
        uint256 endBlock;
    }
    struct WhiteListOption {
        bool isActive;
        WhiteListConfig config;
    }

    function setPoolFactory(address newRooter) external;
    function setRooter(address newRooter) external;
    function getCurrentWhiteConfig(address user) external view returns (WhiteListOption memory);
}