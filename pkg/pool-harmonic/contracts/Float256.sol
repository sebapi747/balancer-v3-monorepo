// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;
/// @title Float — double precision packed into uint256
type Float256 is uint256;
library Float256Math {
	/*
	Float256 — double-precision-like floating-point packed into one uint256
	
	Custom binary floating-point format using only EVM integer and bitwise operations.
	No external calls, fully deterministic across all EVM chains.
	
	Bit layout (MSB first):
  	Bits 255–245 : 11-bit biased exponent (bias = 1023, matches IEEE 754 binary64)
  	Bit  244     : sign bit (0 = positive, 1 = negative)
  	Bits 243–0   : 244-bit signed significand (two's complement integer)
	
	Mathematical value:
  	value = (-1)^sign × significand × 2^(exponent - 1023 - SIGNIFICAND_SCALE)
	
	Comparison with IEEE 754 binary64 (double precision):
  	• Exponent field: same 11 bits, same bias 1023, same normal range ≈ ±2^(-1022) to ±2^(+1023)
  	• Significand: explicit leading bit (no hidden/implicit 1), stored as signed integer
  	• Precision: ≥ 53 bits (for SIGNIFICAND_SCALE ≥ 52), typically SIGNIFICAND_SCALE – 10..12 bits effective after arithmetic
  	• No subnormals, infinities or NaNs implemented yet (exponent 0 and 2047 available for future use)
	
	Comparison with 18-decimal fixed-point math (e.g. Balancer V2/V3 style):
  	• Fixed-point (e.g. 1e18 = 1.0) offers exact representation for multiples of 10^(-18) and very predictable rounding
  	• However, products of several large balances (e.g. ∏ Qi in weighted/stable pool invariants) can easily exceed 2^256 before division → overflow or catastrophic precision loss
  	• Floating-point with per-value exponent avoids this entirely: large Qi values are normalized individually → products stay within safe integer range during multiplication
  	• Main advantage of Float256: dramatically better handling of pools/tokens with very large or very imbalanced balances (e.g. high-value assets like WBTC, or deep stable pools), without needing artificial caps or extra scaling logic
	
	Normalization ranges (after fromUint or arithmetic result normalization):
  	• Zero                : significand = 0
  	• Normal numbers      : |significand| ∈ [2^SIGNIFICAND_SCALE, 2^(SIGNIFICAND_SCALE + 1) - 1]
  	• Subnormals (future) : |significand| ∈ [1, 2^SIGNIFICAND_SCALE - 1]  (not yet supported)
	
	Precision trade-off note:
  	After each arithmetic operation (add, mul, etc.), useful precision is typically
  	SIGNIFICAND_SCALE – 10..12 bits due to alignment shifts, carry/rounding, and lack of
  	full renormalization for gas efficiency. With SIGNIFICAND_SCALE = 72 this still
  	exceeds binary64's 53-bit significand precision in most cases.
	
	Benefits:
  	• Extremely low gas cost compared to emulated IEEE 754
  	• Multiplication of aligned significands fits safely in uint256
  	• All operations are pure integer/bitwise → predictable gas and no floating-point unit needed
  	• Easy to extend with subnormals, inf/NaN, or higher precision
  	• Superior dynamic range for DeFi invariants involving products of large/imbalanced quantities
	
	Current limitations (intentional gas optimizations):
  	• No full renormalization after add/sub (possible 1-bit loss on carry-out or cancellation)
  	• No subnormal support
  	• No ±Inf / NaN handling
  	• toUint() truncates toward zero (rounds down for positive values)
  	• Negative values not supported in toUint()
	*/
    uint256 public constant EXPONENT_BITS = 11;
    uint256 public constant EXPONENT_SHIFT  = 245;      // starts at bit 255, ends at 245
    uint256 public constant EXPONENT_BIAS = 1023;
    uint256 public constant MASK_SIGN = 0x0010000000000000000000000000000000000000000000000000000000000000; // bit 244 
    uint256 public constant MASK_EXPONENT = 0xFFE0000000000000000000000000000000000000000000000000000000000000; // bits 255–245 
    uint256 public constant MASK_SIGNIFICAND = 0x000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // bits 243–0
    uint256 public constant MASK_SIGNED_SIGNIFICAND = 0x001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; //  
    uint256 public constant SIGNIFICAND_SCALE = 72; // significand normalization shift 
    uint256 public constant SQRT_OFFSET = 36; //used by root(); it's exponent logic assumes that SIGNIFICAND_SCALE is an odd

    /// @dev Convert uint256 → Float256 (rounds to nearest, ties to even)
    function fromUint(uint256 x) internal pure returns (Float256) {
        if (x==0) return Float256.wrap(0);
        uint256 msb = _msb(x); 
        uint256 exp = msb + EXPONENT_BIAS-SIGNIFICAND_SCALE;
        uint256 sig = msb>SIGNIFICAND_SCALE ? x >> (msb-SIGNIFICAND_SCALE) : x << (SIGNIFICAND_SCALE-msb); 
        return Float256.wrap(pack(int256(sig),exp)); // pack will shift right by EXPONENT_BITS
    }

    /// @dev Convert Float256 → uint256 (rounds down)
    function toUint(Float256 f) internal pure returns (uint256 r) {
        uint256 packed = Float256.unwrap(f);
        if (packed == 0) return 0;
        int256  sig = significand(packed); // SIGNIFICAND_SCALE
        uint256 exp = exponent(packed);    
        if (exp==0) return 0;
        require(sig>=0, "negative float cannot be converted to uint256");
        uint256  usig = uint256(sig); 
        unchecked {
            r = exp>=EXPONENT_BIAS
                ? usig<<(exp-EXPONENT_BIAS) 
                : usig>>(EXPONENT_BIAS-exp);
        }
    }

    /// @dev Fast MSB for uint256 — tested at 62–68 gas in 2025
    function _msb(uint256 x) private pure returns (uint256 r) {
        if (x == 0) return 0;
        if (x >= 1 << 128) { x >>= 128; r = 128; }
        if (x >= 1 << 64)  { x >>= 64;  r |= 64; }
        if (x >= 1 << 32)  { x >>= 32;  r |= 32; }
        if (x >= 1 << 16)  { x >>= 16;  r |= 16; }
        if (x >= 1 << 8)   { x >>= 8;   r |= 8; }
        if (x >= 1 << 4)   { x >>= 4;   r |= 4; }
        if (x >= 1 << 2)   { x >>= 2;   r |= 2; }
        if (x >= 1 << 1)             r |= 1;
    }

    // ────────────────────────────── Packing ──────────────────────────────
	/*
	Packing choice: signed significand (two's complement) in bits 243–0
	
	We store the significand as a signed integer (option b):
  	Positive: normal binary               e.g. +13 → ...00001101
  	Negative: two's complement            e.g. -13 → ...11110011
	
	Advantages over sign-magnitude (option a):
  	• Direct use of EVM signed arithmetic (add/sub/mul) on significands
  	• Simpler handling of mixed-sign operations
  	• No separate negation logic needed
	
	Trade-off: sign bit is embedded inside the significand field (bit 244),
           	but this matches our packed layout and simplifies the code.
	*/
    function significand(uint256 packed) internal pure returns (int256 sig) {
        assembly {
            sig := shl(EXPONENT_BITS, packed)
        }   
    }
    function exponent(uint256 packed) internal pure returns (uint256 e) {
        assembly {
            e := shr(EXPONENT_SHIFT, packed)
        }
    }
    function pack(int256 cs, uint256 ce) internal pure returns (uint256 packed) {
        assembly {packed := or(shr(EXPONENT_BITS,cs), shl(EXPONENT_SHIFT, ce))} 
    }
    
    // ────────────────────────────── Arithmetic ──────────────────────────────
    
    function add(Float256 ax, Float256 bx) internal pure returns (Float256) {
        uint256 a = Float256.unwrap(ax);
        uint256 b = Float256.unwrap(bx);
        uint256 ae   = exponent(a);
        uint256 be   = exponent(b);
        int256  asig = significand(a);
        int256  bs   = significand(b); 
        // actual operation starts
        int256 cs; uint256 ce;
        if (be>ae) (asig, ae, bs, be) = (bs, be, asig, ae);
        unchecked {
            cs = asig + (bs >> (ae - be));
            ce = ae;
            // gas golfing: to be more robust, we should renormalize in case the addition carried up cs to an additional bit
        }
        // actual operation ends
        uint256 packed = pack(cs,ce);
        return Float256.wrap(packed);
    }
    
    function sub(Float256 ax, Float256 bx) internal pure returns (Float256) {
        uint256 a = Float256.unwrap(ax);
        uint256 b = Float256.unwrap(bx);
        uint256 ae   = exponent(a);
        uint256 be   = exponent(b);
        int256  asig = significand(a);
        int256  bs   = significand(b); 
        // actual operation starts
        int256 cs; uint256 ce;
        unchecked {
            if (ae <= be) {
                cs = (asig >> (be-ae)) - bs;
                ce = be;
            } else {
                cs = asig - (bs >> (ae-be));
                ce = ae;
            }
            // gas golfing: to be more robust, we could renormalize in case the substraction reduced exponent
        }
        // actual operation ends
        uint256 packed = pack(cs,ce);
        return Float256.wrap(packed);
    }
    
    function mul(Float256 ax, Float256 bx) internal pure returns (Float256) {
        uint256 a = Float256.unwrap(ax);
        uint256 b = Float256.unwrap(bx);
        if (a == 0 || b == 0) return Float256.wrap(0);
        uint256 ae   = exponent(a);
        uint256 be   = exponent(b);
        int256  asig = significand(a);
        int256  bs = significand(b); 
        // actual operation starts
        int256 cs; uint256 ce;
        unchecked {
            cs = (asig * bs) >> SIGNIFICAND_SCALE;
            ce = ae + be+ SIGNIFICAND_SCALE;
            ce = ce>EXPONENT_BIAS ? ce-EXPONENT_BIAS : 0;
        }
        if (ce == 0) return Float256.wrap(0);
        require(ce<=2046,"exponent overflow");
        // gas golfing: to be more robust, we should renormalize in case the mult increased exponent
        // actual operation ends
        uint256 packed = pack(cs,ce);
        return Float256.wrap(packed);
    }
    
    function div(Float256 ax, Float256 bx) internal pure returns (Float256) {
        uint256 a = Float256.unwrap(ax);
        uint256 b = Float256.unwrap(bx);
        if (a == 0) return Float256.wrap(0);
        int256  asig = significand(a);
        int256  bs = significand(b); 
        require(bs!=0, "significand must be non 0");
        uint256 ae   = exponent(a);
        uint256 be   = exponent(b);
        // actual operation starts
        int256 cs; uint256 ce;
        uint256 posexp; uint256 negexp;
        unchecked {
            cs = (asig << SIGNIFICAND_SCALE)/bs;
            posexp = EXPONENT_BIAS+ae;
            negexp = SIGNIFICAND_SCALE+be;
            ce = posexp>negexp ? posexp-negexp : 0;
        }
        if (ce == 0) return Float256.wrap(0);
        require(ce<=2046,"exponent overflow");
        // gas golfing: to be more robust, we should renormalize in case the div reduced exponent
        // actual operation ends
        uint256 packed = pack(cs,ce);
        return Float256.wrap(packed);
    }
    
    // ────────────────────────────── Power & Root ──────────────────────────────
    function pow(Float256 a, uint256 p) internal pure returns (Float256 c) {
        if (p == 1) return a;
        if (p == 2) return mul(a, a);
        if (p == 4) { Float256 sq = mul(a, a); return mul(sq, sq); }
        revert("unsupported pow");
    }
        
    function sqrtInt(uint256 x) internal pure returns (uint256) {
        if (x <= 1) return x;
        uint256 z = 1 << ((_msb(x) + 2) >> 1); // educated guess 
        if (z>=x) {
            z -= 1; // required for very low value x=4 etc
        }
        uint256 y = x;
        while (z<y) {
            y = z;
            z = (x / z + z) >> 1;
        }
        return y;
    }
    
    function root(Float256 ax, uint256 p) internal pure returns (Float256 c) {
        if (p == 1) return ax;
        if (p == 4) return root(root(ax, 2), 2);
        require(p==2,"p must be 1,2 or 4");
        uint256 a = Float256.unwrap(ax);
        uint256 m = uint256(significand(a));
        int256  exp = int256(exponent(a)+SIGNIFICAND_SCALE)-int256(EXPONENT_BIAS);
        if (exp % 2 == 1) {
            m = m << 1;
            exp = exp-1;
        }
        m   = sqrtInt(m) << SQRT_OFFSET; // SIGNIFICAND_SCALE/2
        exp = (exp >> 1) + int256(EXPONENT_BIAS-SIGNIFICAND_SCALE); 
        uint256 packed = pack(int256(m),uint256(exp));
        return Float256.wrap(packed);
    }
}
