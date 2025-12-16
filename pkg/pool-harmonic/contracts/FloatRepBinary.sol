// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

library FloatRepBinary {
    uint256 private constant OFFSET = 52;
    uint256 private constant FACTOR = 1 << OFFSET;
    uint256 private constant SQRT_OFFSET = OFFSET / 2;
	/*
	This object will be stored as 80bit struct in Solidity

	This is less than half of the storage used by much of solidity int256 used  for
	fixed precision calculations. Although memory padding may nullify this advantage.
	For reference it is already better than the mantissa and exponent of IEEE754 float64:
	- Total bits: 64
	- Sign bit: 1 bit
	- Exponent: 11 bits (range: -1022 to +1023, biased by 1023)
	- Mantissa: 52 bits (+1 implicit = 53 bits of precision)
	- Dynamic range: ~10^-308 to ~10^308
	We get much better, althought we do not really need better than 
	the IEEE754 precision given chmm fees are much larger than the 1.54e-16 relative
	precision of float64 mantissa.
	
	another very exciting possibility is to use a packed int128 to store the mantissa and exponent
	*/
    struct Float {
        int64 mantissa;
        int16 exponent;
    }

    // ────────────────────────────── Conversion ──────────────────────────────
    function fromUint(uint256 x) internal pure returns (Float memory f) {
        if (x == 0) return f;	
        int256  exp = _bit_length(x) - int256(OFFSET);
        uint256 mant = exp>=0 ? x>>uint256(exp) : x << uint256(-exp);
        f.mantissa = int64(uint64(mant));
        f.exponent = int16(exp);
    }

    function toUint(Float memory f) internal pure returns (uint256) {
        if (f.mantissa == 0) return 0;
        require(f.mantissa>0,"negative float cannot be cast to unsigned");
        uint256 mant = uint256(uint64(f.mantissa));
        return f.exponent>=0 ? mant<<uint256(int256(f.exponent)) : mant>>uint256(int256(-f.exponent));
    }

	/*
	## uint256 Representations:
	- 0: `0x0000000000000000000000000000000000000000000000000000000000000000` (256 zero bits)
	- 1: `0x0000000000000000000000000000000000000000000000000000000000000001` (only LSB=1)
	- 2¹²⁸ - 1: `0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` (high 128 bits zero, low 128 bits one)
	- 2²⁵⁶ - 1: `0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` (all 256 bits one)
	- 2²⁵⁶: overflows 
	*/  
    function _bit_length(uint256 x) private pure returns (int256) {
    	if (x == 0) return 0; // optimisation 
        int256 msb = 0;
        // Binary search to find MSB position
        if (x >= 2**128) { x >>= 128; msb += 128; }
        if (x >= 2**64)  { x >>= 64;  msb += 64;  }
        if (x >= 2**32)  { x >>= 32;  msb += 32;  }
        if (x >= 2**16)  { x >>= 16;  msb += 16;  }
        if (x >= 2**8)   { x >>= 8;   msb += 8;   }
        if (x >= 2**4)   { x >>= 4;   msb += 4;   }
        if (x >= 2**2)   { x >>= 2;   msb += 2;   }
        if (x >= 2**1)   { msb += 1;              }
        return msb;
    }    

    // ────────────────────────────── Arithmetic ──────────────────────────────

    function add(Float memory a, Float memory b) internal pure returns (Float memory c) {
        if (a.exponent < b.exponent) (a, b) = (b, a);
        int256 diff = int256(a.exponent) - int256(b.exponent);
        c.mantissa = a.mantissa + (b.mantissa >> uint256(diff));
        c.exponent = a.exponent;
    }

    function sub(Float memory a, Float memory b) internal pure returns (Float memory c) {
        if (a.exponent < b.exponent) {
            int256 diff = int256(b.exponent) - int256(a.exponent);
            c.mantissa = -(b.mantissa + (a.mantissa >> uint256(diff)));
            c.exponent = b.exponent;
        } else {
            int256 diff = int256(a.exponent) - int256(b.exponent);
            c.mantissa = a.mantissa - (b.mantissa >> uint256(diff));
            c.exponent = a.exponent;
        }
    }

    function mul(Float memory a, Float memory b) internal pure returns (Float memory c) {
        c.mantissa = int64((int128(a.mantissa) * int128(b.mantissa)) >> OFFSET);
        c.exponent = a.exponent + b.exponent + int16(uint16(OFFSET));
    }

    function div(Float memory a, Float memory b) internal pure returns (Float memory c) {
        require(b.mantissa != 0, "div0");
        int128 num = int128(a.mantissa) * int128(int256(FACTOR));
        c.mantissa = int64(num / b.mantissa);
        c.exponent = a.exponent - b.exponent - int16(uint16(OFFSET));
    }

    // ────────────────────────────── Power & Root ──────────────────────────────

    function pow(Float memory a, uint256 p) internal pure returns (Float memory c) {
        if (p == 1) return a;
        if (p == 2) return mul(a, a);
        if (p == 4) { Float memory sq = mul(a, a); return mul(sq, sq); }
        revert("unsupported pow");
    }
    
    function sqrtInt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) >> 1; // z = 1 << ((x.bit_length()+1) // 2)  # well educated guess
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) >> 1;
        }
        return y;
    }

    function root(Float memory a, uint256 p) internal pure returns (Float memory c) {
        if (p == 1) return a;
        if (p == 4) return root(root(a, 2), 2);

        uint256 m = uint256(int256(a.mantissa));
        int256 exp = int256(a.exponent);

        uint256 sqrtMant = sqrtInt(exp % 2 == 0 ? m : m << 1);
        int256 newExp = (exp >> 1) - int256(SQRT_OFFSET);

        unchecked {
            c.mantissa = int64(uint64(sqrtMant << SQRT_OFFSET));
        }
        c.exponent = int16(newExp);
    }
}
