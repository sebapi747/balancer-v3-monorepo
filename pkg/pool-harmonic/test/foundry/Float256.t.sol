// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";
import { Float256, Float256Math } from "../../contracts/Float256.sol"; // Adjust the path if needed

contract Float256Test is Test {
    using Float256Math for Float256;

	function bitfieldtostring(uint256 x) internal pure returns (string memory) {
    	// Reuse the same logic for raw uint256/int256 debugging
    	string memory result = "";
    	for (uint256 i = 0; i < 256; i++) {
        	uint256 bitPos = i; //255 - i;
        	bool bit = (x & (1 << bitPos)) != 0;
        	result = string(abi.encodePacked(bit ? "1" : "0", result));
        	if (i % 8 == 7 && i != 255) result = string(abi.encodePacked(" ", result));
    	}
    	return result;
	}
	
	function debugUint256Bits(string memory name, uint256 x) internal pure {
    	// Reuse the same logic for raw uint256/int256 debugging
    	string memory result = bitfieldtostring(x);
    	bool isNegative = (x & Float256Math.MASK_SIGN) != 0;
    	uint256 biasedExp = Float256Math.exponent(x);
    	int256 significand = Float256Math.significand(x);
    	uint256 sigSignificand; assembly{sigSignificand:= significand}  // using your existing function
    	console.log("int256 ",name);
    	console.log("  raw uint256:       ", x);
    	console.log("  raw bitfield:      ", result);
    	console.log("Interpretation as packed Float256:");
    	console.log("  Sign bit (255):    ", isNegative ? "-1 (negative)" : "+1 (positive)");
    	console.log("  Biased exponent:   ", biasedExp);
    	console.log("  Significand:       ", significand); 
    	console.log("  Significand bits:  ", bitfieldtostring(sigSignificand)); 
	}

	function testDebugSigns() public pure {
    	Float256 pos13 = Float256Math.fromUint(13);
    	Float256 neg13 = Float256Math.fromUint(0).sub(pos13);
		//debugUint256Bits(" +13 packed:", Float256.unwrap(pos13));
    	//debugUint256Bits("-13 manual:", Float256.unwrap(neg13));
    	Float256 zero = pos13.add(neg13);
        assertEq(zero.toUint(),0);
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
        Float256 f = Float256.wrap(0);
        assertEq(f.toUint(), 0);
    }

    function testFromUintOne() public pure {
        Float256 f = Float256Math.fromUint(1);
        assertEq(f.toUint(), 1);
        f = Float256Math.fromUint(1e18);
        assertEq(f.toUint(), 1e18);
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
        Float256 ymx = fy.sub(fx);
        Float256 zero = ymx.add(xmy);
        assertEq(zero.toUint(),0);
        assertEq(xmy.add(ymx).toUint(),0);
        /*
        x = 13;
        fx = Float256Math.fromUint(x);
        Float256 mx   = Float256Math.fromUint(0).sub(fx);
        Float256 zero = fx.add(mx);
        debugUint256Bits("x:", Float256.unwrap(fx));
        debugUint256Bits("-x:", Float256.unwrap(mx));
        debugUint256Bits("x+(-x):", Float256.unwrap(zero));
        uint256 a = Float256.unwrap(fx);
    	uint256 b = Float256.unwrap(mx);
    	uint256 ae   = Float256Math.exponent(a);
    	uint256 be   = Float256Math.exponent(b);
    	int256  asig = Float256Math.significand(a);
    	int256  bs   = Float256Math.significand(b); 
    	// actual operation starts
    	int256 cs; uint256 ce;
    	if (be>ae) (asig, ae, bs, be) = (bs, be, asig, ae);
    	unchecked {
			cs = asig + (bs >> (ae - be));
			ce = ae;
			// gas golfing: to be more robust, we should renormalize in case the addition carried up cs to an additional bit
    	}
    	// actual operation ends
    	uint256 packed = Float256Math.pack(cs,ce);
    	console.log("ae:       ", ae); 
    	console.log("as:       ", asig); 
    	console.log("be:       ", be); 
    	console.log("bs:       ", bs); 
    	console.log("ce:       ", ce); 
    	console.log("cs:       ", cs); 
    	console.log("packed:       ", packed); 
        debugUint256Bits("packed:", packed);
        //console.log("x+zero:", vm.toString(Float256.unwrap(fx.add(zero))));
        //console.log("x:", vm.toString(Float256.unwrap(fx)));
        //assertApproxEqUint(fx.add(zero).toUint(), x, x, "x+((x-y)+(y-x))= x");
        assertEq(ce,be+1);*/
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
