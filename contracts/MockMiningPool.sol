// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";

contract MockMiningPool {
    using Strings for uint256;
    using Strings for address;

    address public operating;
    uint256 public epochReleaseRate;
    uint256 public lphRate;
    uint256 public userSwapULimitPoolRate;
    uint256 public userSwapULimitUserRate;
    uint256 public userSwapUEdgeRate;
    
    address public rooter;
    
    event ChangeOperatingAccount(address indexed operating);
    event SetEpochReleaseRate(uint256 epochReleaseRate);
    event SetLphRate(uint256 lphRate);
    event SetUserSwapULimitRate(uint256 userSwapULimitPoolRate, uint256 userSwapULimitUserRate, uint256 userSwapUEdgeRate);
    event RooterChanged(address indexed oldRooter, address indexed newRooter);

    modifier onlyRooter() {
        require(msg.sender == rooter, string(abi.encodePacked("Only rooter: ", Strings.toHexString(msg.sender), " rooter: ", Strings.toHexString(rooter))));
        _;
    }

    constructor() {
        // 设置默认值
        operating = address(0);
        epochReleaseRate = 1000;
        lphRate = 10400;
        userSwapULimitPoolRate = 500;
        userSwapULimitUserRate = 5000;
        userSwapUEdgeRate = 1000;
    }

    function setRooter(address _rooter) external {
        require(_rooter != address(0), "MockMiningPool: Invalid rooter address");
        address oldRooter = rooter;
        rooter = _rooter;
        emit RooterChanged(oldRooter, _rooter);
    }

    function changeOperatingAccount(address _operating) external onlyRooter {
        require(_operating != address(0), "MockMiningPool: Invalid operating account");
        operating = _operating;
        emit ChangeOperatingAccount(_operating);
    }

    function setEpochReleaseRate(uint256 _epochReleaseRate) external onlyRooter {
        require(_epochReleaseRate >= 1 && _epochReleaseRate <= 15000, "MockMiningPool: Invalid epoch release rate");
        epochReleaseRate = _epochReleaseRate;
        emit SetEpochReleaseRate(_epochReleaseRate);
    }

    function setLphRate(uint256 _lphRate) external onlyRooter {
        require(_lphRate >= 10000 && _lphRate <= 18000, "MockMiningPool: Invalid LPH rate");
        lphRate = _lphRate;
        emit SetLphRate(_lphRate);
    }

    function setUserSwapULimitRate(
        uint256 _userSwapULimitPoolRate, 
        uint256 _userSwapULimitUserRate, 
        uint256 _userSwapUEdgeRate
    ) external onlyRooter {
        require(_userSwapULimitPoolRate <= 10000, "MockMiningPool: Invalid pool rate");
        require(_userSwapULimitUserRate <= 10000, "MockMiningPool: Invalid user rate");
        require(_userSwapUEdgeRate <= 10000, "MockMiningPool: Invalid edge rate");
        
        userSwapULimitPoolRate = _userSwapULimitPoolRate;
        userSwapULimitUserRate = _userSwapULimitUserRate;
        userSwapUEdgeRate = _userSwapUEdgeRate;
        
        emit SetUserSwapULimitRate(_userSwapULimitPoolRate, _userSwapULimitUserRate, _userSwapUEdgeRate);
    }

    // 查询函数
    function getConfig() external view returns (
        address _operating,
        uint256 _epochReleaseRate,
        uint256 _lphRate,
        uint256 _userSwapULimitPoolRate,
        uint256 _userSwapULimitUserRate,
        uint256 _userSwapUEdgeRate
    ) {
        return (operating, epochReleaseRate, lphRate, userSwapULimitPoolRate, userSwapULimitUserRate, userSwapUEdgeRate);
    }
} 