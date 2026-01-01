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
    	console.log("  exp bitfield:      ", bitfieldtostring(biasedExp));
    	console.log("  sig bitfield:      ", bitfieldtostring(sigSignificand));
    	console.log("Interpretation as packed Float256:");
    	console.log("  Sign bit (255):    ", isNegative ? "-1 (negative)" : "+1 (positive)");
    	console.log("  Biased exponent:   ", biasedExp);
    	console.log("  Significand:       ", significand); 
    	console.log("  Significand bits:  ", bitfieldtostring(sigSignificand)); 
	}

	function testAAADebugSigns() public pure {
    	Float256 pos13 = Float256Math.fromUint(13);
    	Float256 neg13 = Float256Math.fromUint(0).sub(pos13);
    	Float256 pos15 = Float256Math.fromUint(15);
    	Float256 pos28 = Float256Math.fromUint(28);
    	// 13: 1101 with SIGNIFICAND_SCALE
    	// exp: msb=3 
		/*debugUint256Bits(" +13 packed:", Float256.unwrap(pos13));
		debugUint256Bits(" +15 packed:", Float256.unwrap(pos15));
		debugUint256Bits(" add 13+15 packed:", Float256.unwrap(pos13.add(pos15)));
		debugUint256Bits(" +28 packed:", Float256.unwrap(pos28));*/
    	//debugUint256Bits("-13 manual :", Float256.unwrap(neg13));
    	Float256 zero = pos13.add(neg13);
    	//debugUint256Bits("0 zero:", Float256.unwrap(zero));
        assertEq(zero.toUint(),0);
        assertEq(pos13.add(pos15).toUint(),28);
	}

    function testSpeedFromUint() public pure {
        for (uint256 i = 0; i < 1000; i++) {
        	Float256Math.fromUint(1000);
        }
    }
    function testSpeedToUint() public pure {
        Float256 f = Float256Math.fromUint(1e18);
        for (uint256 i = 0; i < 1000; i++) {
        	f.toUint();
        }
    }
    
    function testACZeroConvertsCorrectly() public pure {
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
    function assertApproxEqUint(uint256 a, uint256 b, uint256 x, uint256 tolerance, string memory err) internal pure {
        uint256 diff = a > b ? a - b : b - a;
        assertLe(diff << (Float256Math.SIGNIFICAND_SCALE-Float256Math.EXPONENT_BITS-tolerance) -1, x, err); // Allow abs(a-b).2^52-1 <= x 
    }
    
    function testRoundTrip(uint256 x) public pure {
        vm.assume(x < (1 << (Float256Math.SIGNIFICAND_SCALE-11)));
        assertEq(Float256Math.fromUint(x).toUint(),x);
    }
	function testAdd() public pure{
        Float256 fy = Float256Math.fromUint(2115565);
        assertEq(Float256Math.fromUint(450).add(fy).toUint(), 450+2115565);
        assertEq(Float256Math.fromUint(2115565).add(fy).toUint(), 2115565+2115565);
    }    
	function testSub() public pure{
        Float256 fy = Float256Math.fromUint(21);
        assertEq(Float256Math.fromUint(450).sub(fy).toUint(), 450-21);
        assertEq(Float256Math.fromUint(2115565).sub(fy).toUint(), 2115565-21);
    }     
    function testMul() public pure {
        Float256 x = Float256Math.fromUint(1564513);
        Float256 y = Float256Math.fromUint(3);
        Float256 z = x;
        uint256 zint = 1564513*3;
	    assertEq(x.mul(y).toUint(),zint);
    }
      
	function testAddFuzz(uint256 x, uint256 y) public pure{
        vm.assume(x < (1 << (255-11-Float256Math.SIGNIFICAND_SCALE-1)));
        vm.assume(y < (1 << (255-11-Float256Math.SIGNIFICAND_SCALE-1)));
        Float256 fx = Float256Math.fromUint(x);
        Float256 fy = Float256Math.fromUint(y);
        Float256 result = fx.add(fy);
        assertApproxEqUint(result.toUint(), x + y,x+y,0, "add fuzz precision");
    } 
	function testSubFuzz(uint256 x, uint256 y) public pure{
        vm.assume(x < (1 << (200-11-Float256Math.SIGNIFICAND_SCALE)));
        vm.assume(y < (1 << (200-11-Float256Math.SIGNIFICAND_SCALE)));
        vm.assume(x>=y);
        Float256 fx = Float256Math.fromUint(x);
        Float256 fy = Float256Math.fromUint(y);
        Float256 xmy = fx.sub(fy);
        // Helper to check relative error abs(a-b).2^52-1 <= x for  ~1 ulp
        assertApproxEqUint(x-y, xmy.toUint(), x, 2, "sub fuzz failed");
    } 
	function testMulFuzz(uint256 x, uint256 y) public pure{
        vm.assume(x < (1 << 240));
        vm.assume(y < (1 << 16));
        Float256 fx = Float256Math.fromUint(x);
        Float256 fy = Float256Math.fromUint(y);
        uint256 expected = x * y; 
        uint256 result = fx.mul(fy).toUint();
        assertApproxEqUint(result, expected, expected,0, "mul fuzz precision");
    }
  
	function testDivExamples() public pure{
		uint256 a = 51; uint256 b = 3;
        assertEq(Float256Math.fromUint(a*b).div(Float256Math.fromUint(b)).toUint(), a);
        a = 3546347; b = 4325636;
        assertEq(Float256Math.fromUint(a*b).div(Float256Math.fromUint(b)).toUint(), a);
    }
      
	function testDivFuzz(uint256 x, uint256 y) public pure{
        vm.assume(x < (1 << 52));
        vm.assume(y < (1 << 52));
        vm.assume(y > 0);
        uint256 result = Float256Math.fromUint(x*y).div(Float256Math.fromUint(y)).toUint();
        assertApproxEqAbs(result, x, 1);
    }
  
    function testSqrtInt() public pure {
    	// Perfect squares
    	assertEq(Float256Math.sqrtInt(0), 0);
    	assertEq(Float256Math.sqrtInt(1), 1);
    	assertEq(Float256Math.sqrtInt(4), 2);
    	assertEq(Float256Math.sqrtInt(9), 3);
    	assertEq(Float256Math.sqrtInt(16), 4);
    	assertEq(Float256Math.sqrtInt(25), 5);
    	assertEq(Float256Math.sqrtInt(144), 12);
    	assertEq(Float256Math.sqrtInt(1024), 32);
    	assertEq(Float256Math.sqrtInt(65536), 256);
    	assertEq(Float256Math.sqrtInt(100000000), 10000);
	
    	// Non-perfect squares → should floor
    	assertEq(Float256Math.sqrtInt(2), 1);
    	assertEq(Float256Math.sqrtInt(3), 1);
    	assertEq(Float256Math.sqrtInt(8), 2);
    	assertEq(Float256Math.sqrtInt(10), 3);
    	assertEq(Float256Math.sqrtInt(15), 3);
    	assertEq(Float256Math.sqrtInt(26), 5);
    	assertEq(Float256Math.sqrtInt(99), 9);
    	assertEq(Float256Math.sqrtInt(100000001), 10000);
	
    	// Larger values near uint256 bounds
    	assertEq(Float256Math.sqrtInt(1 << 128), 1 << 64);
    	assertEq(Float256Math.sqrtInt(1 << 200), 1 << 100);
	}
	
	function testPowBasic() public pure {
    	// p = 1 → should return the input unchanged
    	assertEq(Float256Math.fromUint(7).pow(1).toUint(), 7);
    	assertEq(Float256Math.fromUint(0).pow(1).toUint(), 0);
    	assertEq(Float256Math.fromUint(1).pow(1).toUint(), 1);
    	assertEq(Float256Math.fromUint(1000000).pow(1).toUint(), 1000000);
	
    	// p = 2 → square
    	assertEq(Float256Math.fromUint(5).pow(2).toUint(), 25);
    	assertEq(Float256Math.fromUint(10).pow(2).toUint(), 100);
    	assertEq(Float256Math.fromUint(100).pow(2).toUint(), 10000);
    	assertEq(Float256Math.fromUint(0).pow(2).toUint(), 0);
	
    	// p = 4 → square of square
    	assertEq(Float256Math.fromUint(3).pow(4).toUint(), 81);
    	assertEq(Float256Math.fromUint(4).pow(4).toUint(), 256);
    	assertEq(Float256Math.fromUint(10).pow(4).toUint(), 10000);
	}
	
	function testRootBasic() public pure {
    	// p = 1 → identity
    	assertEq(Float256Math.fromUint(42).root(1).toUint(), 42);
    	assertEq(Float256Math.fromUint(0).root(1).toUint(), 0);
    	assertEq(Float256Math.fromUint(1).root(1).toUint(), 1);
	
    	// p = 2 → square root (floors)
    	assertEq(Float256Math.fromUint(16).root(2).toUint(), 4);
    	assertEq(Float256Math.fromUint(25).root(2).toUint(), 5);
    	assertEq(Float256Math.fromUint(26).root(2).toUint(), 5); // floors
    	assertEq(Float256Math.fromUint(9).root(2).toUint(), 3);
    	assertEq(Float256Math.fromUint(2).root(2).toUint(), 1);
    	assertEq(Float256Math.fromUint(0).root(2).toUint(), 0);
    	
    	// p = 4 → fourth root = sqrt(sqrt(x))
    	assertEq(Float256Math.fromUint(81).root(4).toUint(), 3);
    	assertEq(Float256Math.fromUint(256).root(4).toUint(), 4);
    	assertEq(Float256Math.fromUint(625).root(4).toUint(), 5);
    	assertEq(Float256Math.fromUint(10000).root(4).toUint(), 10);
    	assertEq(Float256Math.fromUint(2401).root(4).toUint(), 7); // 7⁴ = 2401
	}
	
	function testPowAndRootRoundtrip() public pure {
    	// pow → root should approximately recover original (for perfect powers)
    	uint256[] memory bases = new uint256[](5);
    	bases[0] = 2;
    	bases[1] = 3;
    	bases[2] = 5;
    	bases[3] = 10;
    	bases[4] = 16;
    	for (uint256 i = 0; i < bases.length; i++) {
	    	Float256 f = Float256Math.fromUint(bases[i]);
	    	// b² → √ → should get back b (or very close)
        	assertEq(f.pow(2).root(2).toUint(), bases[i]);
	    	// b⁴ → ⁴√ → should get back b
        	assertEq( f.pow(4).root(4).toUint(), bases[i]);
    	}
	}	

    function testSpeedAdd() public pure {
        Float256 x = Float256Math.fromUint(1564513);
        Float256 y = Float256Math.fromUint(3);
        Float256 z = x;
        uint256 zint = 1564513*3;
	    // gas test for kflops
        for (uint256 i = 0; i < 10; i++) {
        	x = z;
        	for (uint256 j= 0; j < 100; j++) {
        		x = x.add(y);
			}
		}
    }
    function testSpeedSub() public pure {
        Float256 x = Float256Math.fromUint(1564513);
        Float256 y = Float256Math.fromUint(3);
        Float256 z = x;
        uint256 zint = 1564513*3;
	    // gas test for kflops
        for (uint256 i = 0; i < 10; i++) {
        	x = z;
        	for (uint256 j= 0; j < 100; j++) {
        		x = x.sub(y);
			}
		}
    }   
    function testSpeedMul() public pure {
        Float256 x = Float256Math.fromUint(1564513);
        Float256 y = Float256Math.fromUint(3);
        Float256 z = x;
        uint256 zint = 1564513*3;
	    // gas test for kflops
        for (uint256 i = 0; i < 10; i++) {
        	x = z;
        	for (uint256 j= 0; j < 100; j++) {
        		x = x.mul(y);
			}
		}
    }
    function testSpeedDiv() public pure {
        Float256 x = Float256Math.fromUint(1564513);
        Float256 y = Float256Math.fromUint(3);
        Float256 z = x;
        uint256 zint = 1564513*3;
	    // gas test for kflops
        for (uint256 i = 0; i < 10; i++) {
        	x = z;
        	for (uint256 j= 0; j < 100; j++) {
        		x = x.div(y);
			}
		}
    }    
	function testSpeedRoot4() public pure {
		Float256 f = Float256Math.fromUint(145456445);
		for (uint256 i = 0; i < 1000; i++) {
    		f.root(4);
    	}
	}	
	function testSpeedRoot2() public pure {
		Float256 f = Float256Math.fromUint(145456445);
		for (uint256 i = 0; i < 1000; i++) {
    		f.root(2);
    	}
	}	
}
