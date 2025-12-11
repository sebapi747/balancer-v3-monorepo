// pkg/pool-harmonic/test/foundry/HarmonicMath.t.sol
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HarmonicMath} from "../../contracts/HarmonicMath.sol";

contract HarmonicMathTest is Test {
    function testCalcOutGivenIn() public pure {
        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 1000e18;

        uint256 out = HarmonicMath.computeOutGivenExactIn(
    		balances[0],  // balanceInScaled18
    		10e18,        // amountInScaled18
    		balances[1],  // balanceOutScaled18
    		4             // p
		);
        // TODO: assert reasonable value
    }
}
