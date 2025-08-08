// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Utils {
    function lphRise(uint256 _epoch, uint256 rate) internal pure returns(uint256) {
        if(_epoch == 0){
            return 10000;
        }
        uint256 base = rate;
        uint256 result = 1;
        while (_epoch > 0) {
            if (_epoch % 2 == 1) {
                if(result > 1){
                    result = result * base / 10000;
                }else{
                    result = result * base;
                }
            }
            base = base * base / 10000;
            _epoch = _epoch / 2;
        }
        return result;
    }
}