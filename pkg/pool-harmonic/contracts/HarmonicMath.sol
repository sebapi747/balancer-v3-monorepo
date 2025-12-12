// SPDX-License-Identifier: GPL-3.0-or-later
// pkg/pool-harmonic/contracts/HarmonicMath.sol
pragma solidity ^0.8.24;

import {FloatRepBinary} from "./FloatRepBinary.sol";

library HarmonicMath {
    using FloatRepBinary for FloatRepBinary.Float;
    
	/// @dev Exact-in swap: user sends tokenIn, receives tokenOut
	/// @param balanceInScaled18 Balance of the input token (scaled 18 decimals)
	/// @param amountInScaled18 Exact amount of input token (scaled 18)
	/// @param balanceOutScaled18 Balance of the output token (scaled 18)
	/// @param p CHMM exponent parameter (p ≥ 1)
	/// @return amountOutScaled18 Amount of output token (scaled 18)
	function computeOutGivenExactIn(
    	uint256 balanceInScaled18,
    	uint256 amountInScaled18,
    	uint256 balanceOutScaled18,
    	uint256 p
	) internal pure returns (uint256 amountOutScaled18) {
    	// TODO: implement CHMM γ-version or θ-version
    	amountOutScaled18 = 0; // placeholder
	}
	
	/// @dev Exact-out swap: user wants output token, calculate input needed
	/// @param balanceInScaled18 Balance of the input token (scaled 18)
	/// @param amountOutScaled18 Exact amount of output token desired (scaled 18)
	/// @param balanceOutScaled18 Balance of the output token (scaled 18)
	/// @param p CHMM exponent parameter
	/// @return amountInScaled18 Amount of input token required (scaled 18)
	function computeInGivenExactOut(
    	uint256 balanceInScaled18,
    	uint256 amountOutScaled18,
    	uint256 balanceOutScaled18,
    	uint256 p
	) internal pure returns (uint256 amountInScaled18) {
    	// TODO: implement reverse CHMM formula
    	amountInScaled18 = 0; // placeholder
	}

	function computeInvariantUp(uint256[] memory, uint256) internal pure returns (uint256) {
    	return 1e18; // placeholder – will be replaced with real CHMM invariant
	}
	
	function computeInvariantDown(uint256[] memory, uint256) internal pure returns (uint256) {
    	return 1e18; // placeholder – will be replaced with real CHMM invariant
	}
	
	/// @dev Compute the new balance of a token after an unbalanced liquidity operation
	/// @param balanceScaled18 Current balance of the token (scaled 18)
	/// @param invariantRatio The ratio of new invariant to old invariant (scaled 18)
	/// @param p CHMM exponent parameter
	/// @return newBalanceScaled18 The new balance after the operation (scaled 18)
	function computeBalanceOutGivenInvariant(
    	uint256 balanceScaled18,
    	uint256 invariantRatio,
    	uint256 p
	) internal pure returns (uint256 newBalanceScaled18) {
    	// TODO: implement proper CHMM formula
    	newBalanceScaled18 = balanceScaled18; // placeholder (no change for now)
	}
	
	uint256 internal constant _MIN_INVARIANT_RATIO = 0.95e18; // 95%
	uint256 internal constant _MAX_INVARIANT_RATIO = 1.05e18; // 105%
}

