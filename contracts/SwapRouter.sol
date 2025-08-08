
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './libs/IWETH.sol';
import './libs/IERC20.sol';
import './libs/ISwapFactory.sol';
import './libs/ISwapPair.sol';
import './libs/SafeMath.sol';
import './libs/TransferHelper.sol';
import './libs/Ownable.sol';

contract SwapRouter is Ownable {
    using SafeMath for uint256;

    address public immutable factory;
    address public immutable WETH;

    uint private constant RATE_PERCISION = 10000;

    mapping(address => address) public baseTokenOf;

    mapping(address => uint256) public sellBurnRateOf;
    mapping(address => uint256) public sellStopBurnSupplyOf;

    mapping(address => mapping(address => bool)) public isWhiteList;

    address public poolFactory;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'SwapRouter: EXPIRED');
        _;
    }

    modifier checkSwapPath(address[] calldata path){
        require(path.length == 2,"path length error");

        address pair = pairFor(path[0],path[1]);
        // address baseToken = baseTokenOf[pairFor(path[0],path[1])];
        // require(baseToken != address(0),"pair of path not found");
        // require(path[0] != baseToken || isWhiteList[pair][msg.sender], "buy disabled");
        require(isWhiteList[pair][msg.sender], "buy disabled");
        _;
    }

    event NewPairCreated(address caller, address pair, uint blockTime);

    constructor(address _factory) {
        factory = _factory;
        WETH = address(0);
    }

    receive() external payable {
        assert(msg.sender == WETH);
        // only accept ETH via fallback from the WETH contract
    }

    function pairFor(address tokenA, address tokenB) public view returns (address pair) {
        pair = ISwapFactory(factory).pairFor(tokenA, tokenB);
    }

    function createPair(
        address mintToken,
        uint256 mintTokenAmount,
        address stableToken,
        uint256 stableTokenAmount,
        uint256 sellBurnRate,
        uint256 sellStopBurnSupply
        ) external {
        require(msg.sender == poolFactory, "Sender must be poolFactory.");
        require(ISwapFactory(factory).getPair(mintToken, stableToken) == address(0), "Pair existed");
        require(sellBurnRate <= RATE_PERCISION, "sell burn token rate too big");
        require(mintTokenAmount > 0 && stableTokenAmount > 0, "Invalid mintTokenAmount or stableTokenAmount");

        address pair = ISwapFactory(factory).createPair(mintToken, stableToken);
        // ISwapPair(pair).mint(msg.sender);
        ISwapPair(pair).mint(poolFactory);

        baseTokenOf[pair] = stableToken;

        sellBurnRateOf[pair] = sellBurnRate;
        sellStopBurnSupplyOf[pair] = sellStopBurnSupply;

        isWhiteList[pair][msg.sender] = true;

        emit NewPairCreated(msg.sender, pair, block.timestamp);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal view returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        // if (ISwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
        //     ISwapFactory(factory).createPair(tokenA, tokenB);
        // }
        require(ISwapFactory(factory).getPair(tokenA, tokenB) != address(0),"pair not exists");
        
        (uint reserveA, uint reserveB) = ISwapFactory(factory).getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = ISwapFactory(factory).quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = ISwapFactory(factory).quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = pairFor(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ISwapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = pairFor(token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value : amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ISwapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        require(ISwapFactory(factory).getPair(tokenA, tokenB) != address(0),"pair not exists");

        address pair = pairFor(tokenA, tokenB);
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity);
        // send liquidity to pair
        (uint amount0, uint amount1) = ISwapPair(pair).burn(to);
        (address token0,) = ISwapFactory(factory).sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public  ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = ISwapFactory(factory).sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
            ISwapPair(pairFor(input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal returns(uint) {
        (address input, address output) = (path[0], path[1]);
        (address token0,) = ISwapFactory(factory).sortTokens(input, output);
        ISwapPair pair = ISwapPair(pairFor(input, output));
        uint amountInput;
        uint amountOutput;
        {// scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = ISwapFactory(factory).getAmountOut(amountInput, reserveInput, reserveOutput, input, output);
        }

        (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
        // address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
        pair.swap(amount0Out, amount1Out, _to, new bytes(0));

        return amountInput;
    }

    function _isBuy(address[] calldata path) internal view returns(bool) {
        return path[0] == baseTokenOf[pairFor(path[0],path[1])] ? true : false;
    }

    struct SwapTempVals {
        bool isBuy;
        address swapTo;
        uint balanceBefore;
        uint amountInput;
        uint amountOut;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) checkSwapPath(path) returns (SwapTempVals memory) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amountIn);

        SwapTempVals memory tempVals;
        tempVals.isBuy = _isBuy(path);
        tempVals.swapTo = to; // tempVals.isBuy ? to : address(this);

        tempVals.balanceBefore = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo);
        tempVals.amountInput = _swapSupportingFeeOnTransferTokens(path, tempVals.swapTo);
        tempVals.amountOut = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo).sub(tempVals.balanceBefore);
        require(tempVals.amountOut >= amountOutMin,'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        if(!tempVals.isBuy){
            _burnPairToken(path,tempVals.amountInput);
        }
        return tempVals;
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable ensure(deadline) checkSwapPath(path) returns (SwapTempVals memory) {
        require(path[0] == WETH, 'SwapRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value : amountIn}();
        assert(IWETH(WETH).transfer(pairFor(path[0], path[1]), amountIn));

        SwapTempVals memory tempVals;
        tempVals.isBuy = _isBuy(path);
        tempVals.swapTo = to; // tempVals.isBuy ? to : address(this);

        tempVals.balanceBefore = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo);
        tempVals.amountInput = _swapSupportingFeeOnTransferTokens(path, tempVals.swapTo);
        tempVals.amountOut = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo).sub(tempVals.balanceBefore);
        require(tempVals.amountOut >= amountOutMin,'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        if(!tempVals.isBuy){
            _burnPairToken(path,tempVals.amountInput);
        }
        return tempVals;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) checkSwapPath(path) returns (SwapTempVals memory) {
        require(path[path.length - 1] == WETH, 'SwapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amountIn);

        SwapTempVals memory tempVals;
        tempVals.isBuy = _isBuy(path);
        tempVals.swapTo = to; // tempVals.isBuy ? to : address(this);

        tempVals.balanceBefore = IERC20(path[path.length - 1]).balanceOf(address(this));
        tempVals.amountInput = _swapSupportingFeeOnTransferTokens(path, address(this));
        tempVals.amountOut = IERC20(path[path.length - 1]).balanceOf(address(this)).sub(tempVals.balanceBefore);
        require(tempVals.amountOut >= amountOutMin, 'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // IWETH(WETH).withdraw(tempVals.amountOut);

        if(!tempVals.isBuy){
            _burnPairToken(path,tempVals.amountInput);
        }else{
            IWETH(WETH).withdraw(tempVals.amountOut);
            TransferHelper.safeTransferETH(to, tempVals.amountOut);
        }
        return tempVals;
    }

    function _burnPairToken(address[] calldata path,uint amountInput) internal {
        address pair = pairFor(path[0], path[1]);

        uint burnedAmount = IERC20(path[0]).balanceOf(address(0));
        burnedAmount = burnedAmount.add(IERC20(path[0]).balanceOf(address(0x000000000000000000000000000000000000dEaD)));
        uint totalSupply = IERC20(path[0]).totalSupply().sub(burnedAmount);
        uint stopBurnSupply = sellStopBurnSupplyOf[pair];
        uint burnAmount = amountInput.mul(sellBurnRateOf[pair]) / RATE_PERCISION;
        if(burnAmount > 0 && totalSupply > stopBurnSupply){
            if(totalSupply.sub(burnAmount) < stopBurnSupply){
                burnAmount = totalSupply.sub(stopBurnSupply);
            }
            if(burnAmount > 0){
                ISwapPair(pair).burnToken(path[0],burnAmount);
            }
        }
    }

    function _flipPath(address[] calldata path) internal pure returns(address[] memory flipedPath){
        flipedPath  = new address[](2);
        flipedPath[0] = path[1];
        flipedPath[1] = path[0];
    }

    function setWhiteList(address pair,address account,bool status) external {
        require(msg.sender == poolFactory, "caller must be creator");
        isWhiteList[pair][account] = status;
    }

    function setPoolFactory(address _poolFactory) external {
        require(poolFactory == address(0), "poolFactory already set");
        poolFactory = _poolFactory;
    }

     // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        return ISwapFactory(factory).getReserves(tokenA, tokenB);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public view returns (uint256 amountB) {
        return ISwapFactory(factory).quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address token0, address token1) public view returns (uint256 amountOut){
        return ISwapFactory(factory).getAmountOut(amountIn, reserveIn, reserveOut, token0, token1);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, address token0, address token1) public view returns (uint256 amountIn){
        return ISwapFactory(factory).getAmountIn(amountOut, reserveIn, reserveOut, token0, token1);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts){
        return ISwapFactory(factory).getAmountsOut(amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts){
        return ISwapFactory(factory).getAmountsIn(amountOut, path);
    }
}