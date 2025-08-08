// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISwapRouter {

    struct SwapResult {
        bool isBuy;
        address swapTo;
        uint balanceBefore;
        uint amountInput;
        uint amountOut;
    }

    function createPair(
        address mintToken,
        uint256 mintTokenAmount,
        address stableToken,
        uint256 stableTokenAmount,
        uint256 sellBurnRate,
        uint256 sellStopBurnSupply
    ) external;
    function setPoolFactory(address _poolFactory) external;
    function pairFor(address tokenA, address tokenB) external view returns (address pair);
    function factory() external view returns(address);
    function WETH() external view returns(address);
    function baseTokenOf(address pair) external view returns(address);
    function sellBurnRateOf(address pair) external view returns(uint);
    function sellStopBurnSupplyOf(address pair) external view returns(uint);
    function isWhiteList(address pair,address account) external view returns(bool);
    function setWhiteList(address pair,address account,bool status) external;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (SwapResult memory);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint , uint , uint );
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external;
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address token0, address token1) external view returns (uint256 amountOut);
    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory);
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, address token0, address token1) external view returns (uint256 amountIn);
    function getAmountsIn(uint256 amountOut, address[] memory path) external view returns (uint256[] memory amounts);
    function getReserves(address tokenA, address tokenB) external view returns (uint reserveA, uint reserveB);
}