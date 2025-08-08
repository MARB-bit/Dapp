// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMiningPool {
    function changeOperatingAccount(address _operating) external;
    function setEpochReleaseRate(uint256 _epochReleaseRate) external;
    function setLphRate(uint256 _lphRate) external;
    function setUserSwapULimitRate(uint256 _userSwapULimitPoolRate, uint256 _userSwapULimitUserRate, uint256 _userSwapUEdgeRate) external;
}

contract MultiSigRooter {
    address public owner;
    IMiningPool public miningPool;

    // 管理员管理
    mapping(address => bool) public admins;
    uint256 public requiredSignatures;
    uint256 public adminCount;

    // 紧急暂停
    bool public paused;

    // 操作超时（单位：秒）
    uint256 public constant OPERATION_TIMEOUT = 24 * 60 * 60; // 24小时

    // 操作记录
    struct Operation {
        uint256 opType;                  // 操作类型
        address[] adminSigners;          // 已签名的管理员地址
        bool executed;                   // 是否已执行
        bool cancelled;                  // 是否已取消
        bytes data;                      // 方法参数数据
        uint256 timestamp;               // 创建时间戳
        bytes executedInfo;              // 执行错误信息
    }

    // Operations队列
    Operation[] public operations;

    // 操作类型常量
    uint256 public constant OP_CHANGE_OPERATING_ACCOUNT = 1;
    uint256 public constant OP_SET_EPOCH_RELEASE_RATE = 2;
    uint256 public constant OP_SET_LPH_RATE = 3;
    uint256 public constant OP_SET_USER_SWAP_U_LIMIT_RATE = 4;
    uint256 public constant OP_ADD_ADMINS = 5;
    uint256 public constant OP_REMOVE_ADMINS = 6;
    uint256 public constant OP_SET_REQUIRED_SIGNATURES = 7;

    event Paused();
    event Unpaused();
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event RequiredSignaturesChanged(uint256 oldValue, uint256 newValue);
    event OperationProposed(uint256 indexed operationId, uint256 opType, bytes data, uint256 timestamp);
    event OperationSigned(uint256 indexed operationId, address indexed signer);
    event OperationExecuted(uint256 indexed operationId, bool success, bytes info);
    event OperationCancelled(uint256 indexed operationId);

    modifier onlyOwner() {
        require(msg.sender == owner, "MultiSigRooter: Only owner can execute");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "MultiSigRooter: Only admin can execute");
        _;
    }

    modifier operationExists(uint256 opId) {
        require(opId < operations.length, "MultiSigRooter: Operation does not exist");
        _;
    }

    modifier notExecuted(uint256 opId) {
        require(!operations[opId].cancelled, "MultiSigRooter: Operation already cancelled");
        require(!operations[opId].executed, "MultiSigRooter: Operation already executed");
        _;
    }

    modifier notSigned(uint256 opId) {
        Operation storage op = operations[opId];
        for (uint i = 0; i < op.adminSigners.length; i++) {
            require(op.adminSigners[i] != msg.sender, "MultiSigRooter: Already signed");
        }
        _;
    }

    modifier notPaused() {
        require(!paused, "MultiSigRooter: Paused");
        _;
    }

    modifier notTimedOut(uint256 opId) {
        require(block.timestamp <= operations[opId].timestamp + OPERATION_TIMEOUT, "MultiSigRooter: Operation timed out");
        _;
    }

    constructor(address _miningPool, address[] memory _initialAdmins, uint256 _requiredSignatures) {
        require(_miningPool != address(0), "MultiSigRooter: Invalid mining pool address");
        require(_initialAdmins.length >= _requiredSignatures, "MultiSigRooter: Not enough initial admins");
        require(_requiredSignatures > 0, "MultiSigRooter: Required signatures must be greater than 0");

        owner = msg.sender;
        miningPool = IMiningPool(_miningPool);
        requiredSignatures = _requiredSignatures;

        // 添加初始管理员
        for (uint i = 0; i < _initialAdmins.length; i++) {
            require(_initialAdmins[i] != address(0), "MultiSigRooter: Invalid admin address");
            admins[_initialAdmins[i]] = true;
            adminCount++;
            emit AdminAdded(_initialAdmins[i]);
        }
    }

    // 紧急暂停
    function pause() public onlyOwner {
        paused = true;
        emit Paused();
    }
    function unpause() public onlyOwner {
        paused = false;
        emit Unpaused();
    }

    // ========== 多签名操作提案 =============
    function proposeAddAdmins(address[] calldata _admins, uint256 _newRequiredSignatures) public onlyAdmin notPaused {
        require(_admins.length > 0, "MultiSigRooter: Empty admin list");
        require(_newRequiredSignatures > 0 && _newRequiredSignatures <= adminCount + _admins.length, 
                "MultiSigRooter: Invalid new required signatures");
        bytes memory data = abi.encode(_admins, _newRequiredSignatures);
        _proposeOperation(OP_ADD_ADMINS, data);
    }
    function proposeRemoveAdmins(address[] calldata _admins, uint256 _newRequiredSignatures) public onlyAdmin notPaused {
        require(_admins.length > 0, "MultiSigRooter: Empty admin list");
        require(_newRequiredSignatures > 0 && _newRequiredSignatures <= adminCount - _admins.length, 
                "MultiSigRooter: Invalid new required signatures");
        bytes memory data = abi.encode(_admins, _newRequiredSignatures);
        _proposeOperation(OP_REMOVE_ADMINS, data);
    }
    function proposeChangeOperatingAccount(address _operating) public onlyAdmin notPaused {
        require(_operating != address(0), "MultiSigRooter: Invalid operating account");
        bytes memory data = abi.encode(_operating);
        _proposeOperation(OP_CHANGE_OPERATING_ACCOUNT, data);
    }
    function proposeSetEpochReleaseRate(uint256 _epochReleaseRate) public onlyAdmin notPaused {
        bytes memory data = abi.encode(_epochReleaseRate);
        _proposeOperation(OP_SET_EPOCH_RELEASE_RATE, data);
    }
    function proposeSetLphRate(uint256 _lphRate) public onlyAdmin notPaused {
        bytes memory data = abi.encode(_lphRate);
        _proposeOperation(OP_SET_LPH_RATE, data);
    }
    function proposeSetUserSwapULimitRate(
        uint256 _userSwapULimitPoolRate, 
        uint256 _userSwapULimitUserRate, 
        uint256 _userSwapUEdgeRate
    ) public onlyAdmin notPaused {
        bytes memory data = abi.encode(_userSwapULimitPoolRate, _userSwapULimitUserRate, _userSwapUEdgeRate);
        _proposeOperation(OP_SET_USER_SWAP_U_LIMIT_RATE, data);
    }
    function proposeSetRequiredSignatures(uint256 _newRequiredSignatures) public onlyAdmin notPaused {
        require(_newRequiredSignatures > 0 && _newRequiredSignatures <= adminCount, "MultiSigRooter: Invalid required signatures");
        bytes memory data = abi.encode(_newRequiredSignatures);
        _proposeOperation(OP_SET_REQUIRED_SIGNATURES, data);
    }

    function _proposeOperation(uint256 opType, bytes memory data) internal {
        uint256 operationId = operations.length;
        operations.push(Operation({
            opType: opType,
            adminSigners: new address[](0),
            executed: false,
            cancelled: false,
            data: data,
            timestamp: block.timestamp,
            executedInfo: bytes("")
        }));
        emit OperationProposed(operationId, opType, data, block.timestamp);
        _signOperation(operationId);
    }

    // ========== 多签名签名与执行 =============
    function signOperation(uint256 opId) public onlyAdmin notPaused operationExists(opId) notExecuted(opId) notSigned(opId) notTimedOut(opId) {
        _signOperation(opId);
    }
    function _signOperation(uint256 opId) internal {
        Operation storage op = operations[opId];
        op.adminSigners.push(msg.sender);
        if (op.adminSigners.length >= requiredSignatures) {
            executeOperation(opId);
        }
        emit OperationSigned(opId, msg.sender);
    }

    function executeOperation(uint256 opId) internal notExecuted(opId) notTimedOut(opId) {
        Operation storage op = operations[opId];
        bool success = false;
        bytes memory reason = bytes("");
        try this._executeOperation(opId) {
            success = true;
        } catch (bytes memory _reason) {
            success = false;
            reason = _reason;
        }
        op.executed = success;
        op.executedInfo = reason;
        emit OperationExecuted(opId, success, reason);
    }

    function _executeOperation(uint256 opId) external {
        require(msg.sender == address(this), "MultiSigRooter: Only self can call");
        Operation storage op = operations[opId];
        require(op.adminSigners.length >= requiredSignatures, "MultiSigRooter: Not enough signatures");
        require(!op.executed, "MultiSigRooter: Operation executed");
        require(!op.cancelled, "MultiSigRooter: Operation cancelled");
        require(block.timestamp <= op.timestamp + OPERATION_TIMEOUT, "MultiSigRooter: Operation timed out");
        if (op.opType == OP_CHANGE_OPERATING_ACCOUNT) {
            (address operatingAccount) = abi.decode(op.data, (address));
            miningPool.changeOperatingAccount(operatingAccount);
        } else if (op.opType == OP_SET_EPOCH_RELEASE_RATE) {
            (uint256 epochReleaseRate) = abi.decode(op.data, (uint256));
            miningPool.setEpochReleaseRate(epochReleaseRate);
        } else if (op.opType == OP_SET_LPH_RATE) {
            (uint256 lphRate) = abi.decode(op.data, (uint256));
            miningPool.setLphRate(lphRate);
        } else if (op.opType == OP_SET_USER_SWAP_U_LIMIT_RATE) {
            (uint256 userSwapULimitPoolRate, uint256 userSwapULimitUserRate, uint256 userSwapUEdgeRate) = 
                abi.decode(op.data, (uint256, uint256, uint256));
            miningPool.setUserSwapULimitRate(userSwapULimitPoolRate, userSwapULimitUserRate, userSwapUEdgeRate);
        } else if (op.opType == OP_ADD_ADMINS) {
            (address[] memory newAdmins, uint256 newRequiredSignatures) = abi.decode(op.data, (address[], uint256));
            _addAdmins(newAdmins);
            if (newRequiredSignatures != requiredSignatures) {
                uint256 oldValue = requiredSignatures;
                requiredSignatures = newRequiredSignatures;
                emit RequiredSignaturesChanged(oldValue, newRequiredSignatures);
            }
        } else if (op.opType == OP_REMOVE_ADMINS) {
            (address[] memory adminsToRemove, uint256 newRequiredSignatures) = abi.decode(op.data, (address[], uint256));
            _removeAdmins(adminsToRemove);
            if (newRequiredSignatures != requiredSignatures) {
                uint256 oldValue = requiredSignatures;
                requiredSignatures = newRequiredSignatures;
                emit RequiredSignaturesChanged(oldValue, newRequiredSignatures);
            }
        } else if (op.opType == OP_SET_REQUIRED_SIGNATURES) {
            (uint256 newRequiredSignatures) = abi.decode(op.data, (uint256));
            require(newRequiredSignatures > 0 && newRequiredSignatures <= adminCount, "MultiSigRooter: Invalid required signatures");
            uint256 oldValue = requiredSignatures;
            requiredSignatures = newRequiredSignatures;
            emit RequiredSignaturesChanged(oldValue, newRequiredSignatures);
        } else {
            revert("MultiSigRooter: Unknown operation type");
        }
    }

    // 内部函数：添加管理员
    function _addAdmins(address[] memory _admins) internal {
        for (uint i = 0; i < _admins.length; i++) {
            if (!admins[_admins[i]]) {
                admins[_admins[i]] = true;
                adminCount++;
                emit AdminAdded(_admins[i]);
            }
        }
    }
    // 内部函数：移除管理员
    function _removeAdmins(address[] memory _admins) internal {
        for (uint i = 0; i < _admins.length; i++) {
            if (admins[_admins[i]]) {
                admins[_admins[i]] = false;
                adminCount--;
                emit AdminRemoved(_admins[i]);
            }
        }
    }

    // 取消操作（只有owner可以取消）
    function cancelOperation(uint256 opId) public onlyOwner operationExists(opId) notExecuted(opId) {
        operations[opId].cancelled = true;
        emit OperationCancelled(opId);
    }

    // ========== 查询函数 =============
    function getOperation(uint256 opId) public view operationExists(opId) returns (
        uint256 opType,
        address[] memory adminSigners,
        bool executed,
        bool cancelled,
        bytes memory data,
        uint256 timestamp,
        bytes memory executedInfo
    ) {
        Operation storage op = operations[opId];
        return (op.opType, op.adminSigners, op.executed, op.cancelled, op.data, op.timestamp, op.executedInfo);
    }
    function getOperationsCount() public view returns (uint256) {
        return operations.length;
    }
    function isAdmin(address _address) public view returns (bool) {
        return admins[_address];
    }
    function getExecutedOperations(uint256 from, uint256 to) public view returns (Operation[] memory) {
        require(from < operations.length, "Invalid range");
        if (to > operations.length) {
            to = operations.length;
        }
        require(from < to, "Invalid range");
        require(to - from <= 100, "Invalid range");

        uint256 count = 0;
        for (uint256 i = from; i < to; i++) {
            if (operations[i].executed) count++;
        }
        Operation[] memory records = new Operation[](count);
        uint256 idx = 0;
        for (uint256 i = from; i < to; i++) {
            if (operations[i].executed) records[idx++] = operations[i];
        }
        return records;
    }
    function getPendingOperations(uint256 from, uint256 to) public view returns (Operation[] memory) {
        require(from < operations.length, "Invalid range");
        if (to > operations.length) {
            to = operations.length;
        }
        require(from < to, "Invalid range");
        require(to - from <= 100, "Invalid range");

        uint256 count = 0;
        for (uint256 i = from; i < to; i++) {
            if (!operations[i].executed && !operations[i].cancelled && block.timestamp <= operations[i].timestamp + OPERATION_TIMEOUT) count++;
        }
        Operation[] memory records = new Operation[](count);
        uint256 idx = 0;
        for (uint256 i = from; i < to; i++) {
            if (!operations[i].executed && !operations[i].cancelled && block.timestamp <= operations[i].timestamp + OPERATION_TIMEOUT) records[idx++] = operations[i];
        }
        return records;
    }
    function getCancelledOperations(uint256 from, uint256 to) public view returns (Operation[] memory) {
        require(from < operations.length, "Invalid range");
        if (to > operations.length) {
            to = operations.length;
        }
        require(from < to, "Invalid range");
        require(to - from <= 100, "Invalid range");

        uint256 count = 0;
        for (uint256 i = from; i < to; i++) {
            if (operations[i].cancelled) count++;
        }
        Operation[] memory records = new Operation[](count);
        uint256 idx = 0;
        for (uint256 i = from; i < to; i++) {
            if (operations[i].cancelled) records[idx++] = operations[i];
        }
        return records;
    }
    function getAdminCount() public view returns (uint256) {
        return adminCount;
    }
    function getRequiredSignatures() public view returns (uint256) {
        return requiredSignatures;
    }
    // 转移所有权
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "MultiSigRooter: Invalid new owner");
        owner = newOwner;
    }
}