// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;
/// @title Float — double precision packed into uint256
type Float256 is uint256;
library Float256Math {
	/*
	Custom floating-point format with binary64-compatible precision
	------------------------------------------------------------------------
	This library implements floating-point arithmetic using only integer operations
	for the Ethereum Virtual Machine (EVM), which lacks native IEEE 754 support.
	IEEE 754 normal encoding is as follow:
		value = (-1)^sign x (1+Fraction/2^52) x 2^(exponent-1023)
		
	The format provides exactly the same precision (53-bit significand, ≈15–16 decimal digits)
	and effectively the same dynamic range as IEEE 754 binary64 (double precision),
	but uses a non-standard layout optimized for EVM integer and bitwise operations.
	
	Encoded value is stored in a single int256/uint256 with the following bit layout:
	
	- Bit 255          : sign bit (1 = negative, 0 = positive)
	- Bits 254–244     : 11-bit biased exponent (bias = 1023, same as binary64)
	- Bits 243–0       : explicit 243-bit unsigned significand magnitude (|significand|)
                    	(in practice, only the upper ≈53 bits are ever used)
	
	Representation:
    	value = (-1)^sign × significand × 2^(exponent − 1023 − 52)
	
	The significand is a 53-bit integer in the range:
	- 0                  for zero
	- [2⁵², 2⁵³ − 1]    for normal numbers (leading 1 is stored explicitly)
	- [1, 2⁵² − 1]       for subnormal numbers (if supported)
	
	Unlike IEEE binary64, there is no implicit leading bit — the full 53-bit significand
	is stored explicitly in the lower bits. This simplifies normalization, multiplication,
	and rounding at the expense of unused lower bits (≈190 zero padding bits).
	The link between our integer significand and ieee fraction is
		significand = (1+Fraction/2^52) x 2^52
	
	Special values (subnormals, infinities, NaNs) can be supported by reserving
	exponent values 0 and 2047, similar to IEEE. 
	
	Benefits:
	- Full binary64 precision and near-identical range
	- All operations use only EVM integer/bitwise instructions → extremely low gas
	- No external libraries, 100% deterministic across all EVM chains
	- Multiplication of significands (53 × 53 → 106 bits) fits safely in uint256
	*/
	uint256 private constant SIGN_BIT_POS = 255;
	uint256 public constant EXPONENT_BITS = 11;
	uint256 public constant EXPONENT_SHIFT = 244; // bits 254–244
	uint256 public constant EXPONENT_BIAS = 1023;
	uint256 public constant MASK_SIGN      = 0x8000000000000000000000000000000000000000000000000000000000000000; 
	uint256 public constant MASK_EXPONENT  = 0x7ff0000000000000000000000000000000000000000000000000000000000000;
	uint256 public constant MASK_SIGNED_SIGNIFICAND = 0x800fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
	//uint256 public constant MASK_SIGN  = 1 << SIGN_BIT_POS;                    // bit 255
	//uint256 private constant MASK_EXPONENT  = ((1 << EXPONENT_BITS) - 1) << EXPONENT_SHIFT;
	//uint256 private constant MASK_SIGNED_SIGNIFICAND = ~MASK_EXPONENT;       // only exclude exponent
	uint256 public constant MASK_SIGNIFICAND = ~MASK_EXPONENT & ~MASK_SIGN; // bits 243–0, excluding sign
	uint256 public constant SIGNIFICAND_SCALE = 60; // significand normalization shift
	
    /// @dev Convert uint256 → Float256 (rounds to nearest, ties to even)
    function fromUint(uint256 x) internal pure returns (Float256) {
    	if (x==0) return Float256.wrap(0);
    	uint256 msb = _msb(x); 
    	uint256 sig; uint256 exp;
    	unchecked {
    		sig = msb>SIGNIFICAND_SCALE 
    			? x>>(msb-SIGNIFICAND_SCALE) 
    			: x<<(SIGNIFICAND_SCALE-msb);
    		exp = (msb+(EXPONENT_BIAS-SIGNIFICAND_SCALE))<<EXPONENT_SHIFT; 
    	}
    	uint256 value = sig | exp;
        return Float256.wrap(value);
    }

    /// @dev Convert Float256 → uint256 (rounds down)
    function toUint(Float256 f) internal pure returns (uint256 r) {
        uint256 x = Float256.unwrap(f);
        if (x == 0) return 0;
    	bool sign = (x &MASK_SIGN) != 0;
        require(!sign, "negative float cannot be converted to uint256");
        uint256 biasedexp = (x & MASK_EXPONENT) >> EXPONENT_SHIFT;
    	if (biasedexp==0) return 0;
    	uint256 sig =  x & MASK_SIGNIFICAND; 
    	unchecked {
        r = biasedexp>=EXPONENT_BIAS 
        	? sig<<(biasedexp-EXPONENT_BIAS) 
        	: sig>>(EXPONENT_BIAS-biasedexp);
        }
    }

    /// @dev Fast MSB for uint256 — 62–68 gas, optimal in 2025
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
	   There are 2 possible packing choice given positive nb 13=0b000...00001101
	   depending if we want to use unsigned arithmetic
	   a) store sign bit + unisgned significand 
	      13=0b00....00001101, -13=0b10....00001101
	      -x = only flip bit sign of x
	      use unsigned arithmetic for mantissa => + calls - if signs differ
	   b) store signed int significand -> use signed int arithmetic for mantissa
	      13=0b00....00001101, -13=0b11...11110011 
	      4=0b00000100, -4=0b11111100
	      (in this case, encoding flips signs on the left, until the rightmost 1)
	      use signed arithmetic for mantissa => simpler code
	   In the following code, I try using b)
	   */ 
	// significand is an int-13 = 11110011
    function significand(uint256 packed) internal pure returns (int256 sig) {
    	assembly {
    		sig := and(packed, MASK_SIGNED_SIGNIFICAND)
			if and(packed,MASK_SIGN) { 
    			sig := or(sig, MASK_EXPONENT) 
			}
		}
    }
    function exponent(uint256 packed) internal pure returns (uint256 exp) {
    	exp = (packed&MASK_EXPONENT) >> EXPONENT_SHIFT;
    }
    function pack(int256 cs, uint256 ce) internal pure returns (uint256 packed) {
    	assembly {packed := or(and(cs,MASK_SIGNED_SIGNIFICAND), shl(EXPONENT_SHIFT, ce))} 
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
        	// gas golfing: to be more robust, we should renormalize in case the substraction reduced exponent
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
    	if (x == 0) return 0;
    	uint256 z = 1 << ((_msb(x) + 2) >> 1);   // educated guess 
    	if (z>=x) {
    		z -= 1;
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
		uint256 SQRT_OFFSET = SIGNIFICAND_SCALE/2;
        m   = sqrtInt(m) << SQRT_OFFSET;
        exp = (exp >> 1) + int256(EXPONENT_BIAS-SIGNIFICAND_SCALE); // - int256(SQRT_OFFSET) 
        uint256 packed = pack(int256(m),uint256(exp));
    	return Float256.wrap(packed);
    }
}
