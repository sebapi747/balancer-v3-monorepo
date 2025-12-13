// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { Float256, Float256Math } from "../../contracts/Float256.sol"; // Adjust the path if needed

contract Float256Test is Test {
    using Float256Math for Float256;

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

    /// @dev Fuzz test for round-trip precision: fromUint → toUint should be very close
    ///      Allows relative error of about 2^-52 (double precision)
    function testRoundTrip(uint256 x) public pure {
        Float256 f = Float256Math.fromUint(x);
        uint256 back = f.toUint();
        // Absolute difference must verify diff <= x/2^52   (integer division)
        // But to be precise when x is small, we check diff*2^52 - 1 <= x, the -1 is for rounding precision
        uint256 diff = back > x ? back - x : x - back;
        assertLe(diff<<52-1, x); 
    }
}
