// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;


import './libs/Ownable.sol';
import './libs/IMiningWhiteList.sol';

interface IMiningPool {
    function addWhiteUsers(bytes memory whiteName, address[] memory _users) external;
    function delWhiteUsers(address[] memory _users) external;
}

contract MiningWhiteList is Ownable {

    uint public constant RATE_PERCISION = 10000;

    address public rooter;
    IMiningPool public miningPool;
    bytes[] public whiteNames;
    mapping (bytes32 => IMiningWhiteList.WhiteList) public whiteLists;
    mapping (bytes32 => address[]) public whiteUsers;

    event RooterChanged(address indexed from, address indexed to);

    modifier onlyRooter() {
        require(msg.sender == rooter, "Caller is not rooter");
        _;
    }

    constructor(address _rooter) {
        rooter = _rooter;
        emit RooterChanged(address(0), _rooter);
    }

    function setRooter(address _rooter) external onlyOwner {
        require(_rooter != address(0), "Invalid rooter");
        rooter = _rooter;
        emit RooterChanged(rooter, _rooter);
    }

    function setMiningPool(address _miningPool) external {
        require(address(0) != _miningPool, "Invalid mining pool");
        require(address(0) == address(miningPool), "Already set mining pool");
        miningPool = IMiningPool(_miningPool);
    }

    function getWhiteNameIndex(bytes memory name) internal view returns (uint32) {
        for (uint32 i = 0; i < whiteNames.length; i++) {
            if(keccak256(whiteNames[i]) == keccak256(name)) {
                return i;
            }
        }
        return type(uint32).max;
    }

    function setWhiteList(IMiningWhiteList.WhiteList calldata whitelist) public onlyRooter {
        require(whitelist.name.length != 0, "Invalid name");
        require(whitelist.rateAddition > 0, "Invalid rate addition");
        require(whitelist.rateAddition < RATE_PERCISION*10, "Invalid rate addition");
        require(whitelist.rateAdditionEndBlock > 0, "Invalid endBlock");
        whiteLists[keccak256(whitelist.name)] = whitelist;
        if(getWhiteNameIndex(whitelist.name) == type(uint32).max) {
            whiteNames.push(whitelist.name);
        }
    }

    function delWhiteList(bytes calldata name) public onlyRooter {
        require(name.length != 0, "Invalid name");
        uint32 index = getWhiteNameIndex(name);
        require(index != type(uint32).max, "Whitelist does not exist");

        bytes32 key = keccak256(name);
        require(whiteLists[key].name.length > 0, "Whitelist does not exist");
        require(whiteUsers[key].length == 0, "Whitelist is not empty");
        whiteNames[index] = whiteNames[whiteNames.length - 1];
        whiteNames.pop();
        delete whiteLists[key];
    }

    function getWhiteAddresses(bytes calldata name) public view returns (address[] memory){
        require(name.length != 0, "Invalid name");
        bytes32 key = keccak256(name);
        require(whiteLists[key].name.length > 0, "Whitelist does not exist");
        return whiteUsers[key];
    }

    function addWhiteAddresses(bytes calldata name, address[] memory users) public onlyRooter {
        require(name.length != 0, "Invalid name");
        bytes32 key = keccak256(name);
        require(whiteLists[key].name.length > 0, "Whitelist does not exist");
        
        miningPool.addWhiteUsers(name, users);
        for (uint i = 0; i < users.length; i++) {
            whiteUsers[key].push(users[i]);
        }
    }

    function delWhiteAddresses(bytes calldata name, address[] memory users, uint[] memory indexes) public onlyRooter {
        require(name.length != 0, "Invalid name");
        bytes32 key = keccak256(name);
        require(whiteLists[key].name.length > 0, "Whitelist does not exist");
        require(whiteUsers[key].length > 0, "WhiteList is empty");
        require(users.length == indexes.length, "Invalid user indexes");
        for (uint i = 0; i < users.length; i++) {
            require(whiteUsers[key][indexes[i]] == users[i], "User index wrong");
        }
        for (uint i = 0; i < users.length; i++) {
            if (whiteUsers[key][indexes[i]] == users[i]) {
                whiteUsers[key][indexes[i]] = whiteUsers[key][whiteUsers[key].length - 1];
                whiteUsers[key].pop();
            }
        }
        miningPool.delWhiteUsers(users);
    }

    function getWhitelist(bytes memory name) external view returns (IMiningWhiteList.WhiteList memory) {
        require(name.length != 0, "Invalid name");
        bytes32 key = keccak256(name);
        require(whiteLists[key].name.length > 0, "Whitelist does not exist");
        IMiningWhiteList.WhiteList memory whitelist = whiteLists[key];
        return whitelist;
    }

    function getWhitelists() public view returns (IMiningWhiteList.WhiteList[] memory) {
        IMiningWhiteList.WhiteList[] memory configs = new IMiningWhiteList.WhiteList[](whiteNames.length);
        for (uint i = 0; i < whiteNames.length; i++) {
            bytes32 key = keccak256(whiteNames[i]);
            configs[i] = whiteLists[key];
        }
        return configs;
    }
}
