// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiquidityPool is ERC20{
    IERC20 public token1;
    IERC20 public token2;
    address public owner;

    uint256 public constant FEE_PERCENT = 3; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 1000;

    constructor(address _token1, address _token2) 
        ERC20("Liquidity Provider Token", "LPT")
    {
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
        owner = msg.sender;
    }

    /**
     * @notice 유동성 풀에 토큰을 공급하여 LP 토큰을 받음
     * @param _token1Amount - 제공할 token1의 양
     * @param _token2Amount - 제공할 token2의 양
    */
    function provideLiquidity(uint _token1Amount, uint _token2Amount) external {
        require(_token1Amount > 0 && _token2Amount > 0, "Amount must be greater than 0");

        uint256 totalSupply = totalSupply();

        if(totalSupply > 0) {
            uint256 token1Reserve = token1.balanceOf(address(this));
            uint256 token2Reserve = token2.balanceOf(address(this));

            require(
                _token1Amount * token2Reserve == _token2Amount * token1Reserve,
                "Invalid ratio"
            );
        }

        token1.transferFrom(msg.sender, address(this), _token1Amount);
        token2.transferFrom(msg.sender, address(this), _token2Amount);

        uint256 liquidity;
        if(totalSupply == 0) {
            liquidity = sqrt(_token1Amount * _token2Amount);
        } else {
            liquidity = min(
                (_token1Amount * totalSupply) / token1.balanceOf(address(this)),
                (_token2Amount * totalSupply) / token2.balanceOf(address(this))
            );
        }

        _mint(msg.sender, liquidity);
    }

    /**
     * @notice 유동성 제거 및 LP 토큰을 소각하여 제공한 토큰을 반황받음
     * @param _lpAmount 소각할 LP 토큰 수량
    */
    function removeLiquidity(uint _lpAmount) external {
        require(balanceOf(msg.sender) >= _lpAmount, "Not enough LP tokens");

        uint token1Amount = (token1.balanceOf(address(this)) * _lpAmount) / totalSupply();
        uint token2Amount = (token2.balanceOf(address(this)) * _lpAmount) / totalSupply();

        _burn(msg.sender, _lpAmount);

        token1.transfer(msg.sender, token1Amount);
        token2.transfer(msg.sender, token2Amount);
    }

    /**
     * @notice token1을 token2로 교환
     * @param _amountIn 사용자가 제공할 token1의 양
     * @param _minAmountOut 최소한으로 받을 token1의 양 (슬리피지 방지)
    */
    function swapToken1ForToken2(uint _amountIn, uint256 _minAmountOut) external {
        uint256 amountOut = getAmountOut(_amountIn, token1.balanceOf(address(this)), token2.balanceOf(address(this)));

        require(amountOut >= _minAmountOut, "Slippage protection: Insufficient output amount");


        token1.transferFrom(msg.sender, address(this), _amountIn);
        token2.transfer(msg.sender, amountOut);
    }

    /**
     * @notice token2를 token1로 교환
     * @param _amountIn 사용자가 제공할 token2의 양
     * @param _minAmountOut 최소한으로 받을 token1의 양 (슬리피지 방지)
     */
    function swapToken2ForToken1(uint256 _amountIn, uint256 _minAmountOut) external {
        uint256 amountOut = getAmountOut(_amountIn, token2.balanceOf(address(this)), token1.balanceOf(address(this)));

        require(amountOut >= _minAmountOut, "Slippage protection: Insufficient output amount");

        token2.transferFrom(msg.sender, address(this), _amountIn);
        token1.transfer(msg.sender, amountOut);
    }

    /**
     * @notice AMM 모델을 기반으로 스왑 후 받을 토큰 양을 계산
     * @param _amountIn 입력 토큰의 양
     * @param _reserveIn 입력 토큰의 유동성 풀 내 잔액
     * @param _reserveOut 출력 토큰의 유동성 풀 내 잔액
     * @return amountOut 계산된 교환 비율에 따른 출력 토큰 양
     */
    function getAmountOut(uint256 _amountIn, uint256 _reserveIn, uint256 _reserveOut) public pure returns(uint256){
        require(_amountIn > 0, "Input amount must be greater than 0");
        require(_reserveIn > 0 && _reserveOut > 0, "Insufficient liquidity");

        uint256 amountInWithFee = _amountIn * (FEE_DENOMINATOR - FEE_PERCENT);
        return (amountInWithFee * _reserveOut) / ((_reserveIn * FEE_DENOMINATOR) + amountInWithFee);
    }

    function getBalanceToken() external view returns(uint256, uint256) {
        return (token1.balanceOf(address(this)), token2.balanceOf(address(this)));
    }

    function min(uint256 a, uint256 b) private pure returns(uint256) {
        return a < b ? a : b;
    }

    function sqrt(uint256 x) private pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while(z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
