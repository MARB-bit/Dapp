// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IERC20.sol";
import "./libs/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract WhiteListReward is Ownable {
    using ECDSA for bytes32;

    // EIP-712 domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant CLAIM_TYPE_HASH = keccak256("Claim(address token,address user,uint256 amount,uint256 deadline,bytes32 nonce)");

    address public rooter;
    mapping(address => bool) public isSigner;
    address[] private signerList;
    uint256 public minSignatures;

    mapping(address => mapping(address => uint256)) public claimedReward;
    mapping(bytes32 => bool) public usedNonce;
    mapping(bytes32 => bool) public revokedNonce;

    event RooterChanged(address indexed from, address indexed to);
    event Revoked(bytes32 indexed nonce);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event MinSignaturesChanged(uint256 minSignatures);
    event Claimed(bytes32 indexed nonce, address indexed token, address indexed user, uint256 amount);

    modifier onlyRooter() {
        require(msg.sender == rooter, "Caller is not rooter");
        _;
    }

    constructor(address _rooter, address[] memory _signers, uint256 _minSignatures) {
        rooter = _rooter;
        emit RooterChanged(address(0), _rooter);

        require(_signers.length >= _minSignatures, "Not enough signers");
        for (uint256 i = 0; i < _signers.length; i++) {
            isSigner[_signers[i]] = true;
            signerList.push(_signers[i]);
        }
        minSignatures = _minSignatures;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("PreachRewardPool")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function setRooter(address _rooter) external onlyOwner {
        require(_rooter != address(0), "Invalid rooter");
        rooter = _rooter;
        emit RooterChanged(rooter, _rooter);
    }

    function addSigner(address signer) external onlyOwner {
        require(!isSigner[signer], "Already signer");
        isSigner[signer] = true;
        signerList.push(signer);
        emit SignerAdded(signer);
    }

    function removeSigner(address signer) external onlyOwner {
        require(isSigner[signer], "Not signer");
        isSigner[signer] = false;
        for (uint256 i = 0; i < signerList.length; i++) {
            if (signerList[i] == signer) {
                signerList[i] = signerList[signerList.length - 1];
                signerList.pop();
                break;
            }
        }
        emit SignerRemoved(signer);
    }

    function setMinSignatures(uint256 _minSignatures) external onlyOwner {
        require(_minSignatures > 0 && _minSignatures <= signerList.length, "Invalid minSignatures");
        minSignatures = _minSignatures;
        emit MinSignaturesChanged(_minSignatures);
    }

    function getSigners() external view returns (address[] memory) {
        return signerList;
    }

    function revoke(bytes32 nonce) external onlyRooter {
        revokedNonce[nonce] = true;
        emit Revoked(nonce);
    }

    function claim(
        address token,
        uint256 amount,
        uint256 deadline,
        bytes32 nonce,
        bytes[] calldata signatures
    ) external {
        require(token != address(0), "Invalid token");
        require(block.number <= deadline, "Expired");
        require(!usedNonce[nonce], "Nonce used");
        require(!revokedNonce[nonce], "Nonce revoked");
        require(signatures.length >= minSignatures, "Not enough signatures");
        require(amount > claimedReward[msg.sender][token], "No Reward to claim");
        uint claimAmount = amount - claimedReward[msg.sender][token];
        require(IERC20(token).balanceOf(address(this)) >= claimAmount, "Insufficient balance");

        // EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPE_HASH,
                token,
                msg.sender,
                amount,
                deadline,
                nonce
            )
        );
        // EIP-712 digest
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

        address[] memory encountered = new address[](signatures.length);
        uint256 validSignatures = 0;
        for (uint256 i = 0; i < signatures.length; i++) {
            address recovered = digest.recover(signatures[i]);
            require(isSigner[recovered], "Invalid signer");
            for (uint256 j = 0; j < validSignatures; j++) {
                require(encountered[j] != recovered, "Duplicate signer");
            }
            encountered[validSignatures] = recovered;
            validSignatures += 1;
        }
        require(validSignatures >= minSignatures, "Not enough valid signatures");

        usedNonce[nonce] = true;
        claimedReward[msg.sender][token] += claimAmount;
        require(IERC20(token).transfer(msg.sender, claimAmount), "Transfer failed");

        emit Claimed(nonce, token, msg.sender, claimAmount);
    }

    function getClaimedReward(address account, address token) external view returns (uint256) {
        return claimedReward[account][token];
    }
}