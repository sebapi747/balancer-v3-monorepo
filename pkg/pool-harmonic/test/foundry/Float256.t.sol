// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";
import { Float256, Float256Math } from "../../contracts/Float256.sol"; // Adjust the path if needed

contract Float256Test is Test {
    using Float256Math for Float256;

	function debugUint256Bits(string memory name, uint256 x) internal pure {
    	// Reuse the same logic for raw uint256/int256 debugging
    	string memory result = "";
    	for (uint256 i = 0; i < 256; i++) {
        	uint256 bitPos = i; //255 - i;
        	bool bit = (x & (1 << bitPos)) != 0;
        	result = string(abi.encodePacked(bit ? "1" : "0", result));
        	if (i % 8 == 7 && i != 255) result = string(abi.encodePacked(" ", result));
    	}
    	console.log(name, result);
    	// Sign bit
    	bool isNegative = (x & Float256Math.MASK_SIGN) != 0;
    	
    	// Exponent (bits 254–244)
    	uint256 biasedExp = (x & Float256Math.MASK_EXPONENT) >> Float256Math.EXPONENT_SHIFT;
    	
    	// Significand magnitude (bits 243–0, interpreted as uint)
    	uint256 sigMagnitude = x & Float256Math.MASK_SIGNIFICAND;
    	
    	// Try to interpret significand as signed (your current approach)
    	int256 sigSigned = Float256Math.significand(x);  // using your existing function
	
    	console.log(name);
    	console.log("  Raw uint256:       ", x);
    	console.log("  Sign bit (255):    ", isNegative ? "-1 (negative)" : "+1 (positive)");
    	console.log("  Biased exponent:   ", biasedExp);
    	console.log("    (true exp = biased - 1023, adjusted by -52 in format)");
    	console.log("  Significand (uint): 0x", vm.toString(sigMagnitude));
    	console.log("    decimal:         ", sigMagnitude);
    	console.log("  Significand (your signed interpretation): ", uint256(sigSigned)); // print as uint to see bits
    	console.log("    as int256:       ", sigSigned > 0 ? "+" : "", vm.toString(sigSigned));
	}

	function testDebugSigns() public pure {
    	Float256 pos13 = Float256Math.fromUint(13);
    	Float256 neg13 = Float256Math.fromUint(0).sub(pos13);
	
		//uint256 MASK_EXPONENT  = ((1 << Float256Math.EXPONENT_BITS) - 1) << Float256Math.EXPONENT_SHIFT;
    	//debugUint256Bits(" MASK_EXPONENT recalc:", MASK_EXPONENT);
    	//debugUint256Bits(" MASK_EXPONENT hard:", Float256Math.MASK_EXPONENT);
    	debugUint256Bits(" +13 packed:", Float256.unwrap(pos13));
    	debugUint256Bits("-13 manual:", Float256.unwrap(neg13));
	}

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

	// Helper to check relative error abs(a-b).2^52-1 <= x for  ~1 ulp
    function assertApproxEqUint(uint256 a, uint256 b, uint256 x, string memory err) internal pure {
        uint256 diff = a > b ? a - b : b - a;
        assertLe(diff << Float256Math.SIGNIFICAND_SCALE -1, x, err); // Allow abs(a-b).2^52-1 <= x 
    }
    
    function testRoundTrip(uint256 x) public pure {
        Float256 f = Float256Math.fromUint(x);
        uint256 back = f.toUint();
        assertApproxEqUint(x,back,back,"testRoundTrip");
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
   
	function testAddFuzz(uint256 x, uint256 y) public pure{
        vm.assume(x < (1 << 254));
        vm.assume(y < (1 << 254));
        Float256 fx = Float256Math.fromUint(x);
        Float256 fy = Float256Math.fromUint(y);
        Float256 result = fx.add(fy);
        assertApproxEqUint(result.toUint(), x + y,x+y, "add fuzz precision");
    } 
	function testSubFuzz(uint256 x, uint256 y) public pure{
        vm.assume(x < (1 << 254));
        vm.assume(y < (1 << 254));
        vm.assume(x>=y);
        Float256 fx = Float256Math.fromUint(x);
        Float256 fy = Float256Math.fromUint(y);
        Float256 xmy = fx.sub(fy);
        assertApproxEqUint(x-y, xmy.toUint(), x, "sub fuzz relative precision");
        //args=[12278727581453662187023, 11092866023091651188199 ]; // [1.227e22,1.109e22]
        x = 12278727581453662187023;
        y = 11092866023091651188199;
        x = 13;
        y = 1;
        fx = Float256Math.fromUint(x);
        fy = Float256Math.fromUint(y);
        Float256 zero = xmy.add(fy.sub(fx));
        console.log("x+zero:", vm.toString(Float256.unwrap(fx.add(zero))));
        console.log("x:", vm.toString(Float256.unwrap(fx)));
        assertEq(fx.add(zero).toUint(), x); //, x, "x+((x-y)+(y-x))= x");
    } 
	function testMulFuzz(uint256 x, uint256 y) public pure{
        vm.assume(x < (1 << 240));
        vm.assume(y < (1 << 16));
        Float256 fx = Float256Math.fromUint(x);
        Float256 fy = Float256Math.fromUint(y);
        uint256 expected = x * y; 
        uint256 result = fx.mul(fy).toUint();
        assertApproxEqUint(result, expected, expected, "mul fuzz precision");
    }
}
