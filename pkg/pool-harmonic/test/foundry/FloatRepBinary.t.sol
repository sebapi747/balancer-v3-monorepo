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

    function testRoundTrip(uint256 x) public {
        vm.assume(x > 0);
        vm.assume(x <= 1e30); // safe range for our 60-bit mantissa

        FloatRepBinary.Float memory f = FloatRepBinary.fromUint(x);
        uint256 back = FloatRepBinary.toUint(f);

        assertApproxEqAbs(back, x, 1); // ±1 wei error allowed
    }
}
