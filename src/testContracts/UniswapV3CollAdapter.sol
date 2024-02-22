// SPDX-License-Identifier: MIT AND GPL-3.0
pragma solidity ^0.8.17;

import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IV3SwapRouter} from "../interface/uniswap/IV3SwapRouter.sol";
import {IStETH} from "../interface/IStETH.sol";
import {IWstETH} from "../interface/IWstETH.sol";

contract UniswapV3CollAdapter is IV3SwapRouter {
    IV3SwapRouter public immutable UNISWAP_ROUTER;
    IStETH public immutable stETH;
    IWstETH public immutable wstETH;

    constructor(address uniswapRouter_, address stETH_, address wstETH_) {
        UNISWAP_ROUTER = IV3SwapRouter(uniswapRouter_);
        stETH = IStETH(stETH_);
        wstETH = IWstETH(wstETH_);

        stETH.approve(wstETH_, type(uint256).max);
    }

    function exactInputSingle(
        ExactInputSingleParams memory params
    ) external payable returns (uint256 amountOut) {
        address tokenIn = params.tokenIn;
        address tokenOut = params.tokenOut;
        address recipient = params.recipient;

        params.recipient = address(this);

        require(tokenIn != tokenOut);

        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        if (tokenIn == address(stETH)) {
            params.tokenIn = address(wstETH);
            
            uint256 wstEthAmountBefore = IERC20(address(wstETH)).balanceOf(address(this));
            wstETH.wrap(params.amountIn);
            uint256 wstEthAmountAfter = IERC20(address(wstETH)).balanceOf(address(this));
            params.amountIn = wstEthAmountAfter - wstEthAmountBefore;
        }
        if (tokenOut == address(stETH)) {
            params.tokenOut = address(wstETH);
            params.amountOutMinimum = wstETH.getWstETHByStETH(params.amountOutMinimum);
        }

        IERC20(params.tokenIn).approve(address(UNISWAP_ROUTER), params.amountIn);
        
        // amountOut = wstETH if tokenOut is stETH
        amountOut = UNISWAP_ROUTER.exactInputSingle(params);

        IERC20(params.tokenIn).approve(address(UNISWAP_ROUTER), 0);

        if (tokenOut == address(stETH)) {
            uint256 stEthAmountBefore = IERC20(address(stETH)).balanceOf(address(this));
            wstETH.unwrap(amountOut);
            uint256 stEthAmountAfter = IERC20(address(stETH)).balanceOf(address(this));
            // Convert amountOut to stETH amount out
            amountOut = stEthAmountAfter - stEthAmountBefore;
        }

        IERC20(tokenOut).transfer(recipient, amountOut);
    }

    function exactOutputSingle(
        ExactOutputSingleParams memory params
    ) external payable returns (uint256 amountIn) {
        address tokenIn = params.tokenIn;
        address tokenOut = params.tokenOut;
        uint256 amountInMax = params.amountInMaximum;
        address recipient = params.recipient;

        params.recipient = address(this);

        require(tokenIn != tokenOut);
        
        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountInMaximum);

        if (tokenIn == address(stETH)) {
            params.tokenIn = address(wstETH);
            
            uint256 wstEthAmountBefore = IERC20(address(wstETH)).balanceOf(address(this));
            wstETH.wrap(params.amountInMaximum);
            uint256 wstEthAmountAfter = IERC20(address(wstETH)).balanceOf(address(this));
            params.amountInMaximum = wstEthAmountAfter - wstEthAmountBefore;
        }
        if (tokenOut == address(stETH)) {
            params.tokenOut = address(wstETH);
            params.amountOut = wstETH.getWstETHByStETH(params.amountOut);
        }

        IERC20(params.tokenIn).approve(address(UNISWAP_ROUTER), params.amountInMaximum);

        amountIn = UNISWAP_ROUTER.exactOutputSingle(params);

        IERC20(params.tokenIn).approve(address(UNISWAP_ROUTER), 0);

        if (amountIn < params.amountInMaximum) {
            uint256 refundAmount = params.amountInMaximum - amountIn;
            
            if (tokenIn == address(stETH)) {
                uint256 stEthAmountBefore = IERC20(address(stETH)).balanceOf(address(this));
                wstETH.unwrap(params.amountInMaximum - amountIn);
                uint256 stEthAmountAfter = IERC20(address(stETH)).balanceOf(address(this));
                // Refund amountIn
                refundAmount = stEthAmountAfter - stEthAmountBefore;
                amountIn = amountInMax - refundAmount;
            }
            
            IERC20(tokenIn).transfer(msg.sender, refundAmount);
        }

        if (tokenOut == address(stETH)) {
            uint256 stEthAmountBefore = IERC20(address(stETH)).balanceOf(address(this));
            wstETH.unwrap(params.amountOut);
            uint256 stEthAmountAfter = IERC20(address(stETH)).balanceOf(address(this));
            // Convert amountOut to stETH amount out
            params.amountOut = stEthAmountAfter - stEthAmountBefore;
        }

        IERC20(tokenOut).transfer(recipient, params.amountOut);
    }
}
