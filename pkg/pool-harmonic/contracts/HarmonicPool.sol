// SPDX-License-Identifier: GPL-3.0-or-later
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

import { HarmonicMath } from "./HarmonicMath.sol";
import { FloatRepBinary } from "./FloatRepBinary.sol";

contract HarmonicPool is BalancerPoolToken, PoolInfo, Version, IBasePool {
    using FloatRepBinary for FloatRepBinary.Float;

    struct NewPoolParams {
        string name;
        string symbol;
        IERC20[] tokens;
        uint256 p;          // CHMM exponent
        string version;
    }

    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16;    // 10%

    uint256 internal immutable _p;

    error HarmonicPoolBptRateUnsupported();

    constructor(NewPoolParams memory params, IVault vault)
        BalancerPoolToken(vault, params.name, params.symbol)
        PoolInfo(vault)
        Version(params.version)
    {
        // Vault already validates token count, but we keep the check for clarity
        InputHelpers.ensureInputLengthMatch(params.tokens.length, params.tokens.length);

        _p = params.p;
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view virtual override returns (uint256) {
        uint256[] memory balances = request.balancesScaled18;

        if (request.kind == SwapKind.EXACT_IN) {
            return HarmonicMath.computeOutGivenExactIn(
                balances[request.indexIn],
                request.amountGivenScaled18,
                balances[request.indexOut],
                _p
            );
        } else {
            return HarmonicMath.computeInGivenExactOut(
                balances[request.indexIn],
                request.amountGivenScaled18,
                balances[request.indexOut],
                _p
            );
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

        return fn(balancesLiveScaled18, _p);
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view override returns (uint256) {
        return HarmonicMath.computeBalanceOutGivenInvariant(
            balancesLiveScaled18[tokenInIndex],
            invariantRatio,
            _p
        );
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
}
