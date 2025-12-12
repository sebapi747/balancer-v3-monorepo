// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

library FloatRepBinary {
    uint256 private constant OFFSET = 60;
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
	
	If we get desperate, we might switch to int32 mantissa and exponent which would require to test
	precision as we get a theoretical 2.3e-10 mantissa precision (probably still ok compared to >1e-4 txn cost)
	or packing/unpacking of an int64 into an int53 mantissa and int11 exponent which requires much 
	shifting and temp variable allocation.
	*/
    struct Float {
        int64 mantissa;
        int16 exponent;
    }

    // ────────────────────────────── Conversion ──────────────────────────────

    function fromUint(uint256 x) internal pure returns (Float memory f) {
        if (x == 0) return f;	
        uint256 lz = _leadingZeros(x);
        int256 exp = int256(255 - lz) - int256(OFFSET);
        uint256 mant = exp<0 ? x << uint256(-exp) : x>>uint256(exp);
        f.mantissa = int64(uint64(mant));
        f.exponent = int16(exp);
    }

    function toUint(Float memory f) internal pure returns (uint256) {
        if (f.mantissa == 0) return 0;
        int256 exp = int256(f.exponent) - int256(OFFSET);
        if (exp <= 0) return 0;
        if (exp >= 256) revert("Float overflow");
        uint256 absMant = f.mantissa < 0 ? uint256(int256(-f.mantissa)) : uint256(int256(f.mantissa));
        return absMant >> uint256(int256(OFFSET) - exp);
    }

	// check this code, we should use define _bit_length()
    function _leadingZeros(uint256 x) private pure returns (uint256 lz) {
        uint256 t = x;
        if (t < 1 << 128) { lz += 128; t <<= 128; } 
        if (t < 1 << 192) { lz += 64;  t <<= 64;  }
        if (t < 1 << 224) { lz += 32;  t <<= 32;  }
        if (t < 1 << 240) { lz += 16;  t <<= 16;  }
        if (t < 1 << 248) { lz += 8;   t <<= 8;   }
        if (t < 1 << 252) { lz += 4;   t <<= 4;   }
        if (t < 1 << 254) { lz += 2;   t <<= 2;   }
        if (t < 1 << 255) lz += 1;
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
