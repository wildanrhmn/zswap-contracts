// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ZSwap
 * @dev A decentralized exchange for swapping ERC20 tokens with liquidity provision
 */
contract ZSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public swapFee = 30;
    
    struct Pair {
        bool exists;
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalLiquidity;
    }
    
    struct UserLiquidity {
        uint256 amount;
        uint256 share;
    }
    
    mapping(address => mapping(address => Pair)) public pairs;
    mapping(address => mapping(address => mapping(address => UserLiquidity))) public userLiquidity;
    
    event PairCreated(address indexed token0, address indexed token1);
    event LiquidityAdded(address indexed user, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    
    /**
     * @dev Constructor
     * @param _initialOwner The address to set as the owner of the contract
     */
    constructor(address _initialOwner) Ownable(_initialOwner) {}
    
    /**
     * @dev Sort tokens to ensure the pair is created consistently
     * @param tokenA The first token
     * @param tokenB The second token
     * @return token0 The token with the lower address
     * @return token1 The token with the higher address
     */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "ZSwap: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZSwap: ZERO_ADDRESS");
    }
    
    /**
     * @dev Create a new liquidity pair
     * @param tokenA The first token
     * @param tokenB The second token
     */
    function createPair(address tokenA, address tokenB) external {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        require(!pairs[token0][token1].exists, "ZSwap: PAIR_EXISTS");
        
        pairs[token0][token1] = Pair({
            exists: true,
            reserve0: 0,
            reserve1: 0,
            totalLiquidity: 0
        });
        
        emit PairCreated(token0, token1);
    }
    
    /**
     * @dev Add liquidity to a pair
     * @param tokenA The first token
     * @param tokenB The second token
     * @param amountADesired The desired amount of the first token
     * @param amountBDesired The desired amount of the second token
     * @param amountAMin The minimum amount of the first token
     * @param amountBMin The minimum amount of the second token
     * @return amountA The amount of the first token added
     * @return amountB The amount of the second token added
     * @return liquidityMinted The amount of liquidity minted
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) external nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidityMinted) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Pair storage pair = pairs[token0][token1];
        require(pair.exists, "ZSwap: PAIR_DOES_NOT_EXIST");
        
        if (pair.reserve0 == 0 && pair.reserve1 == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint256 amountBOptimal = quote(amountADesired, pair.reserve0, pair.reserve1);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "ZSwap: INSUFFICIENT_B_AMOUNT");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = quote(amountBDesired, pair.reserve1, pair.reserve0);
                require(amountAOptimal <= amountADesired, "ZSwap: EXCESSIVE_INPUT_AMOUNT");
                require(amountAOptimal >= amountAMin, "ZSwap: INSUFFICIENT_A_AMOUNT");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }
        
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amountB);
        
        uint256 liquidity;
        if (pair.totalLiquidity == 0) {
            liquidity = Math.sqrt(amountA * amountB) - 1000;
        } else {
            liquidity = Math.min(
                (amountA * pair.totalLiquidity) / pair.reserve0,
                (amountB * pair.totalLiquidity) / pair.reserve1
            );
        }
        
        require(liquidity > 0, "ZSwap: INSUFFICIENT_LIQUIDITY_MINTED");
        
        pair.reserve0 += amountA;
        pair.reserve1 += amountB;
        pair.totalLiquidity += liquidity;
        
        UserLiquidity storage userLiq = userLiquidity[token0][token1][msg.sender];
        userLiq.amount += liquidity;
        userLiq.share = (userLiq.amount * FEE_DENOMINATOR) / pair.totalLiquidity;
        
        emit LiquidityAdded(msg.sender, token0, token1, amountA, amountB, liquidity);
        
        return (amountA, amountB, liquidity);
    }
    
    /**
     * @dev Remove liquidity from a pair
     * @param tokenA The first token
     * @param tokenB The second token
     * @param liquidity The amount of liquidity to remove
     * @param amountAMin The minimum amount of the first token
     * @param amountBMin The minimum amount of the second token
     * @return amountA The amount of the first token removed
     * @return amountB The amount of the second token removed
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Pair storage pair = pairs[token0][token1];
        require(pair.exists, "ZSwap: PAIR_DOES_NOT_EXIST");
        
        UserLiquidity storage userLiq = userLiquidity[token0][token1][msg.sender];
        require(userLiq.amount >= liquidity, "ZSwap: INSUFFICIENT_LIQUIDITY");
        
        amountA = (liquidity * pair.reserve0) / pair.totalLiquidity;
        amountB = (liquidity * pair.reserve1) / pair.totalLiquidity;
        
        require(amountA >= amountAMin, "ZSwap: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "ZSwap: INSUFFICIENT_B_AMOUNT");
        
        pair.reserve0 -= amountA;
        pair.reserve1 -= amountB;
        pair.totalLiquidity -= liquidity;
        
        userLiq.amount -= liquidity;
        if (userLiq.amount == 0) {
            userLiq.share = 0;
        } else {
            userLiq.share = (userLiq.amount * FEE_DENOMINATOR) / pair.totalLiquidity;
        }
        
        IERC20(token0).safeTransfer(msg.sender, amountA);
        IERC20(token1).safeTransfer(msg.sender, amountB);
        
        emit LiquidityRemoved(msg.sender, token0, token1, amountA, amountB, liquidity);
        
        return (amountA, amountB);
    }
    
    /**
     * @dev Swap tokens
     * @param amountIn The amount of tokens to swap
     * @param amountOutMin The minimum amount of output tokens
     * @param path The path of the swap
     * @param to The address to send the output tokens to
     * @return amounts The amounts of tokens in the path
     */
    function swap(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(path.length >= 2, "ZSwap: INVALID_PATH");
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address token0, address token1) = sortTokens(path[i], path[i + 1]);
            
            bool isToken0 = path[i] == token0;
            
            Pair storage pair = pairs[token0][token1];
            require(pair.exists, "ZSwap: PAIR_DOES_NOT_EXIST");
            
            uint256 amountOut = getAmountOut(
                amounts[i],
                isToken0 ? pair.reserve0 : pair.reserve1,
                isToken0 ? pair.reserve1 : pair.reserve0
            );
            
            amounts[i + 1] = amountOut;
            
            if (isToken0) {
                pair.reserve0 += amounts[i];
                pair.reserve1 -= amountOut;
            } else {
                pair.reserve1 += amounts[i];
                pair.reserve0 -= amountOut;
            }
            
            if (i < path.length - 2) {
                amounts[i + 1] = amountOut;
            } else {
                IERC20(path[i + 1]).safeTransfer(to, amountOut);
            }
            
            emit Swap(msg.sender, path[i], path[i + 1], amounts[i], amounts[i + 1]);
        }
        
        require(amounts[amounts.length - 1] >= amountOutMin, "ZSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        
        return amounts;
    }
    
    /**
     * @dev Quote the amount of output tokens for an input amount
     * @param amountA The amount of input tokens
     * @param reserveA The reserve of input tokens
     * @param reserveB The reserve of output tokens
     * @return amountB The amount of output tokens
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        require(amountA > 0, "ZSwap: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "ZSwap: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }
    
    /**
     * @dev Calculate the amount of output tokens for an input amount
     * @param amountIn The amount of input tokens
     * @param reserveIn The reserve of input tokens
     * @param reserveOut The reserve of output tokens
     * @return amountOut The amount of output tokens
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountOut) {
        require(amountIn > 0, "ZSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "ZSwap: INSUFFICIENT_LIQUIDITY");
        
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - swapFee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }
    
    /**
     * @dev Calculate the amount of input tokens for an output amount
     * @param amountOut The amount of output tokens
     * @param reserveIn The reserve of input tokens
     * @param reserveOut The reserve of output tokens
     * @return amountIn The amount of input tokens
     */
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountIn) {
        require(amountOut > 0, "ZSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "ZSwap: INSUFFICIENT_LIQUIDITY");
        
        uint256 numerator = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) * (FEE_DENOMINATOR - swapFee);
        amountIn = (numerator / denominator) + 1;
    }
    
    /**
     * @dev Set the swap fee
     * @param _swapFee The new swap fee
     */
    function setSwapFee(uint256 _swapFee) external onlyOwner {
        require(_swapFee <= 500, "ZSwap: FEE_TOO_HIGH");
        uint256 oldFee = swapFee;
        swapFee = _swapFee;
        emit FeeUpdated(oldFee, _swapFee);
    }
    
    /**
     * @dev Get the pair info
     * @param tokenA The first token
     * @param tokenB The second token
     * @return exists Whether the pair exists
     * @return reserve0 The reserve of the first token
     * @return reserve1 The reserve of the second token
     * @return totalLiquidity The total liquidity
     */
    function getPair(address tokenA, address tokenB) external view returns (
        bool exists,
        uint256 reserve0,
        uint256 reserve1,
        uint256 totalLiquidity
    ) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Pair storage pair = pairs[token0][token1];
        return (pair.exists, pair.reserve0, pair.reserve1, pair.totalLiquidity);
    }
    
    /**
     * @dev Get the user liquidity info
     * @param tokenA The first token
     * @param tokenB The second token
     * @param user The user address
     * @return amount The amount of liquidity
     * @return share The share of total liquidity
     */
    function getUserLiquidity(address tokenA, address tokenB, address user) external view returns (
        uint256 amount,
        uint256 share
    ) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        UserLiquidity storage userLiq = userLiquidity[token0][token1][user];
        return (userLiq.amount, userLiq.share);
    }
}