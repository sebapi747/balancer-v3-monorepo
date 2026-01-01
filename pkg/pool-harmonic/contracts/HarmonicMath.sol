// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Float256, Float256Math} from "./Float256.sol";

library HarmonicMath {
    using Float256Math for Float256;

    error InvalidExponent();
    error NegativeAmount();
    error InsufficientLiquidity();

    uint256 internal constant _MIN_INVARIANT_RATIO = 0.95e18; // 95%
    uint256 internal constant _MAX_INVARIANT_RATIO = 1.05e18; // 105%

    function _checkP(uint256 p) internal pure {
        if (p != 1 && p != 2 && p != 4) revert InvalidExponent();
    }

    // ─────────────────────────────────────────────────────────────
    // Invariant computation: I = (Σ b_i^p )^(1/p)
    // ─────────────────────────────────────────────────────────────

    function computeInvariantDown(
        uint256[] memory balancesLiveScaled18,
        uint256 p
    ) internal pure returns (uint256) {
        _checkP(p);

        Float256 sumP = Float256Math.fromUint(0);
        for (uint256 i = 0; i < balancesLiveScaled18.length; ++i) {
            Float256 b = Float256Math.fromUint(balancesLiveScaled18[i]);
            sumP = sumP.add(b.pow(p));
        }

        Float256 inv;
        if (p == 1) {
            inv = sumP;
        } else if (p == 2) {
            inv = sumP.root(2);
        } else { // p == 4
            inv = sumP.root(4);           // or: root(root(sumP, 2), 2)
        }

        return inv.toUint();
    }

    function computeInvariantUp(
        uint256[] memory balancesLiveScaled18,
        uint256 p
    ) internal pure returns (uint256) {
        uint256 down = computeInvariantDown(balancesLiveScaled18, p);

        // Very conservative round-up: add 1 if any fractional part exists
        // (you can refine this later with proper fractional check if needed)
        return down + 1;
    }

    // ─────────────────────────────────────────────────────────────
    // Swap math – exact in
    // ─────────────────────────────────────────────────────────────

    function computeOutGivenExactIn(
        uint256 balanceInScaled18,
        uint256 amountInScaled18,
        uint256 balanceOutScaled18,
        uint256 p
    ) internal pure returns (uint256 amountOutScaled18) {
        _checkP(p);
        if (amountInScaled18 == 0) return 0;

        Float256 bIn  = Float256Math.fromUint(balanceInScaled18);
        Float256 delta = Float256Math.fromUint(amountInScaled18);
        Float256 bOut = Float256Math.fromUint(balanceOutScaled18);

        Float256 bInNew = bIn.add(delta);
        Float256 powIn  = bIn.pow(p);
        Float256 powOut = bOut.pow(p);
        Float256 powInNew = bInNew.pow(p);

        Float256 powOutNew = powIn.add(powOut).sub(powInNew);

        Float256 bOutNew;
        if (p == 1) {
            bOutNew = powOutNew;
        } else if (p == 2) {
            bOutNew = powOutNew.root(2);
        } else { // p == 4
            bOutNew = powOutNew.root(4);
        }

        Float256 deltaOut = bOut.sub(bOutNew);
        if (deltaOut.toUint() >= balanceOutScaled18) revert InsufficientLiquidity();

        amountOutScaled18 = deltaOut.toUint();
    }

    // ─────────────────────────────────────────────────────────────
    // Swap math – exact out (symmetric)
    // ─────────────────────────────────────────────────────────────

    function computeInGivenExactOut(
        uint256 balanceInScaled18,
        uint256 amountOutScaled18,
        uint256 balanceOutScaled18,
        uint256 p
    ) internal pure returns (uint256 amountInScaled18) {
        _checkP(p);
        if (amountOutScaled18 == 0) return 0;

        Float256 bIn  = Float256Math.fromUint(balanceInScaled18);
        Float256 delta = Float256Math.fromUint(amountOutScaled18);
        Float256 bOut = Float256Math.fromUint(balanceOutScaled18);

        if (delta.toUint() >= balanceOutScaled18) revert InsufficientLiquidity();

        Float256 bOutNew = bOut.sub(delta);
        Float256 powIn   = bIn.pow(p);
        Float256 powOut  = bOut.pow(p);
        Float256 powOutNew = bOutNew.pow(p);

        Float256 powInNew = powIn.add(powOut).sub(powOutNew);

        Float256 bInNew;
        if (p == 1) {
            bInNew = powInNew;
        } else if (p == 2) {
            bInNew = powInNew.root(2);
        } else { // p == 4
            bInNew = powInNew.root(4);
        }

        Float256 deltaIn = bInNew.sub(bIn);
        amountInScaled18 = deltaIn.toUint();
    }

    // ─────────────────────────────────────────────────────────────
    // Compute new balance after invariant change (join/exit)
    // ─────────────────────────────────────────────────────────────

    function computeBalanceOutGivenInvariant(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenIndex,
        uint256 invariantRatioScaled18,
        uint256 p
    ) internal pure returns (uint256 newBalanceScaled18) {
        _checkP(p);

        Float256 currentSumP = Float256Math.fromUint(0);
        Float256 thisTokenPow;

        for (uint256 i = 0; i < balancesLiveScaled18.length; ++i) {
            Float256 b = Float256Math.fromUint(balancesLiveScaled18[i]);
            Float256 bp = b.pow(p);
            currentSumP = currentSumP.add(bp);
            if (i == tokenIndex) thisTokenPow = bp;
        }

        Float256 ratio = Float256Math.fromUint(invariantRatioScaled18);
        Float256 targetSumP = currentSumP.mul(ratio.pow(p));

        Float256 sumWithout = currentSumP.sub(thisTokenPow);
        Float256 neededPow  = targetSumP.sub(sumWithout);

        Float256 newB;
        if (p == 1) {
            newB = neededPow;
        } else if (p == 2) {
            newB = neededPow.root(2);
        } else { // p == 4
            newB = neededPow.root(4);
        }

        newBalanceScaled18 = newB.toUint();
    }
}
