// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libs/ERC20.sol";

contract MARB is ERC20 {

    constructor(string memory name_, string memory symbol_, uint256 totalSupply_, address mintTo_)
        ERC20(name_, symbol_) {
        _mint(mintTo_, totalSupply_);
    }
}
