// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { FloatRepBinary } from "../../contracts/FloatRepBinary.sol";

contract FloatRepBinaryTest is Test {
    using FloatRepBinary for FloatRepBinary.Float;

    function testZeroConvertsCorrectly() public {
        FloatRepBinary.Float memory f = FloatRepBinary.fromUint(0);

        assertEq(f.mantissa, int64(0));
        assertEq(f.exponent, int16(0));
        assertEq(FloatRepBinary.toUint(f), 0);
    }

    function testToUintZeroGivesZero() public {
        FloatRepBinary.Float memory f;
        f.mantissa = int64(0);
        f.exponent = int16(-1000);
        assertEq(FloatRepBinary.toUint(f), 0);
    }

    function testFromUintOne() public {
        FloatRepBinary.Float memory f = FloatRepBinary.fromUint(1e18);
        assertEq(FloatRepBinary.toUint(f), 1e18);
    }

    function testRoundTrip(uint256 x) public { // fuzz test
        FloatRepBinary.Float memory f = FloatRepBinary.fromUint(x);
        uint256 back = FloatRepBinary.toUint(f);
        uint256 diff = back > x ? back - x : x - back;
        assertLe(diff<<52, x); // 2^-52 precision allowed
    }
}
