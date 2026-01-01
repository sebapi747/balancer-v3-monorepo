// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IUnbalancedLiquidityInvariantRatioBounds } from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { Float256, Float256Math } from "./Float256.sol"; // Adjust the path if needed
import { HarmonicMath } from "./HarmonicMath.sol";

contract HarmonicPool is BalancerPoolToken, PoolInfo, Version, IBasePool {
    using Float256Math for Float256;

    struct NewPoolParams {
        string name;
        string symbol;
        IERC20[] tokens;
        uint256 p;          // CHMM exponent
        uint256[] alphas;           // scaled 1e18, sum ≈ 1e18, immutable
        string version;
    }

    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16;    // 10%

	uint256 private p;
    uint256[] private alphas;     // set at construction
    uint256[] private thetas;       // set once, during first join

    error HarmonicPoolBptRateUnsupported();

    constructor(NewPoolParams memory params, IVault vault)
        BalancerPoolToken(vault, params.name, params.symbol)
        PoolInfo(vault)
        Version(params.version)
    {
        // Vault already validates token count, but we keep the check for clarity
        InputHelpers.ensureInputLengthMatch(params.tokens.length, params.alphas.length);
        p = params.p;
        alphas = params.alphas;
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view virtual override returns (uint256) {
		// direction: positive = add to pool, negative = remove from pool
    		if (request.kind == SwapKind.EXACT_IN) {
        		// EXACT_IN: add amountGiven to tokenIn → compute amount removed from tokenOut
        		Float256 deltaOut = _computeDeltaOut(
            		request.indexIn,
            		request.indexOut,
            		Float256Math.fromUint18(request.amountGivenScaled18),           // δQi > 0
            		request.balancesScaled18);
        		return Float256Math.toUint18(deltaOut);
    		} else {
        		// EXACT_OUT: remove amountGiven from tokenOut → compute amount added to tokenIn
        		Float256 deltaIn = _computeDeltaIn(
            		request.indexIn,
            		request.indexOut,
            		Float256Math.fromUint18(request.amountGivenScaled18),           // δQj > 0
            		request.balancesScaled18);
        		return Float256Math.toUint18(deltaIn);
    		}
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18, Rounding rounding)
        public
        view
        override
        returns (uint256)
    {
        function(uint256[] memory, uint256) internal pure returns (uint256) fn = rounding == Rounding.ROUND_UP
            ? HarmonicMath.computeInvariantUp
            : HarmonicMath.computeInvariantDown;

        return fn(balancesLiveScaled18, p);
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view override returns (uint256) {
        return p;
    }

    // ─────────────────────────────────────────────────────────────
    // Interface implementations (no @inheritdoc needed if no base contract implements them)
    // ─────────────────────────────────────────────────────────────

    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    function getMinimumInvariantRatio() external pure returns (uint256) {
        return HarmonicMath._MIN_INVARIANT_RATIO;
    }

    function getMaximumInvariantRatio() external pure returns (uint256) {
        return HarmonicMath._MAX_INVARIANT_RATIO;
    }

    /// @inheritdoc IRateProvider
    function getRate() public pure override returns (uint256) {
        revert HarmonicPoolBptRateUnsupported();
    }
    
	// ─────────────────────────────────────────────────────────────
	// Internal helpers — each has very few locals → no stack-too-deep
	// ─────────────────────────────────────────────────────────────
    //  **Swap Formula** (θ-version, scale-invariant):  
   	//	With `Q̃ᵢ = θᵢ/Qᵢ`:  
   	//	`δQᵢ = θᵢ × (αᵢ/(αᵢQ̃ᵢᵖ + αⱼ(Q̃ⱼᵖ - Q̃ⱼ'ᵖ)))¹/ᵖ - Qᵢ` where `Q̃ⱼ' = θⱼ/(Qⱼ+δQⱼ)`
	function _computeDeltaOut(
    	uint256 i,
    	uint256 j,
    	Float256 deltaQi,                    // > 0 : amount added to token i
    	uint256[] memory balancesScaled18
	) private view returns (Float256 deltaQj) {
    	Float256 ai      = Float256.wrap(alphas[i]);
    	Float256 aj      = Float256.wrap(thetas[j]); // typo fix: was alphas[j]
    	Float256 thetai  = Float256.wrap(thetas[i]);
    	Float256 thetaj  = Float256.wrap(thetas[j]);
    	Float256 Qi   = thetai.div(Float256Math.fromUint18(balancesScaled18[i]));
    	Float256 Qj   = thetaj.div(Float256Math.fromUint18(balancesScaled18[j]));
    	Float256 QiNew = Qi.add(deltaQi);               // Qi + δQi
    	Float256 QjNew = _solveQjNew(Qi, QiNew, Qj, ai, aj, thetai, thetaj);
    	deltaQj = Qj.sub(QjNew);                        // positive = amount out
    	// Optional: if (deltaQj.toUint() > balancesScaled18[j]) revert InsufficientLiquidity();
	}
	
	function _computeDeltaIn(
    	uint256 i,
    	uint256 j,
    	Float256 deltaQj,                    // > 0 : amount removed from token j
    	uint256[] memory balancesScaled18
	) private view returns (Float256 deltaQi) {
    	// Symmetric — flip i ↔ j and negate sign on delta
    	Float256 deltaQiNeg = _computeDeltaOut(j, i, deltaQj, balancesScaled18);
    	deltaQi = Float256.wrap(0).sub(deltaQiNeg);  // make positive
	}
	
	// Core solver: given Qi → QiNew, find QjNew that keeps invariant constant
	function _solveQjNew(
    	Float256 Qi,
    	Float256 QiNew,
    	Float256 Qj,
    	Float256 ai,
    	Float256 aj,
    	Float256 thetai,
    	Float256 thetaj) private view returns (Float256 QjNew) {
    	Float256 Qti   = thetai.div(Qi);
    	Float256 QtiNew = thetai.div(QiNew);
    	Float256 Qtj   = thetaj.div(Qj);
    	Float256 diffPow = Qti.pow(p).sub(QtiNew.pow(p));
    	Float256 denom = ai.mul(diffPow).add(aj.mul(Qtj.pow(p)));
    	Float256 inner = aj.div(denom);           // αⱼ / denom
    	QjNew = thetaj.mul(inner.root(p));        // θⱼ × (…)^{1/p}
	}   
}
