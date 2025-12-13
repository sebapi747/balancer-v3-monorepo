// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { Float256, Float256Math } from "../../contracts/Float256.sol"; // Adjust the path if needed

contract Float256Test is Test {
    using Float256Math for Float256;

    function testPerfFromUint() public pure {
        for (uint256 i = 0; i < 1000; i++) {
        	Float256Math.fromUint(1000);
        }
    }
    function testPerfToUint() public pure {
        Float256 f = Float256Math.fromUint(1e18);
        for (uint256 i = 0; i < 1000; i++) {
        	f.toUint();
        }
    }
    
    function testZeroConvertsCorrectly() public pure {
        Float256 f = Float256Math.fromUint(0);
        assertEq(Float256.unwrap(f), 0);
        assertEq(f.toUint(), 0);
    }

    function testToUintZeroGivesZero() public pure {
        // Manually packed zero (sign=0, exp=0, sig=0)
        Float256 f = Float256.wrap(0);
        assertEq(f.toUint(), 0);
    }

    function testFromUintOne() public pure {
        Float256 f = Float256Math.fromUint(1);
        assertEq(f.toUint(), 1);
        // Larger integer
        f = Float256Math.fromUint(1e18);
        assertEq(f.toUint(), 1e18);
        // Power of two
        f = Float256Math.fromUint(1 << 100);
        assertEq(f.toUint(), 1 << 100);
    }

	// Helper to check relative error <= ~1 ulp
    function assertApproxEqUint(uint256 a, uint256 b, string memory err) internal pure {
        uint256 diff = a > b ? a - b : b - a;
        // Allow diff << 52 <= expected + 1
        assertLe(diff << 52 -1, b, err);
    }
    
    function testRoundTrip(uint256 x) public pure {
        Float256 f = Float256Math.fromUint(x);
        uint256 back = f.toUint();
        assertApproxEqUint(x,back,"testRoundTrip");
    }
    
    function testMul() public pure {
        Float256 x = Float256Math.fromUint(1564513);
        Float256 y = Float256Math.fromUint(3);
        Float256 z = x;
        uint256 zint = 1564513*3;
	    assertEq(x.mul(y).toUint(),zint);
        for (uint256 i = 0; i < 10; i++) {
        	x = z;
        	for (uint256 j= 0; j < 100; j++) {
        		x = x.mul(y);
			}
		}
    }
    
	function testMulFuzz(uint256 x, uint256 y) public pure{
        // Bound to avoid immediate overflow revert in expectation (but let mul handle it)
        vm.assume(x < (1 << 240));
        vm.assume(y < (1 << 16));
        Float256 fx = Float256Math.fromUint(x);
        Float256 fy = Float256Math.fromUint(y);
        uint256 expected = x * y; // may overflow uint256 — that's ok, we compare approx
        uint256 result = fx.mul(fy).toUint();
        assertApproxEqUint(result, expected, "mul fuzz precision");
    }
}
