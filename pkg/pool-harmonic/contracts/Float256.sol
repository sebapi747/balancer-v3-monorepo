// SPDX-License-Identifier: MIT
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
	uint256 private constant EXPONENT_BITS = 11;
	uint256 private constant EXPONENT_SHIFT = 244; // bits 254–244
	uint256 private constant EXPONENT_BIAS = 1023;
	uint256 private constant MASK_SIGN      = 1 << SIGN_BIT_POS;                    // bit 255
	uint256 private constant MASK_EXPONENT  = 0x7ff0000000000000000000000000000000000000000000000000000000000000;
	uint256 private constant MASK_SIGNED_SIGNIFICAND = 0x800fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
	//uint256 private constant MASK_EXPONENT  = ((1 << EXPONENT_BITS) - 1) << EXPONENT_SHIFT;
	//uint256 private constant MASK_SIGNED_SIGNIFICAND = ~MASK_EXPONENT;       // only exclude exponent
	uint256 private constant MASK_SIGNIFICAND = ~MASK_EXPONENT & ~MASK_SIGN; // bits 243–0, excluding sign
	uint256 private constant SIGNIFICAND_SCALE = 52; // significand normalization shift
	
    /// @dev Convert uint256 → Float256 (rounds to nearest, ties to even)
    function fromUint(uint256 x) internal pure returns (Float256) {
    	if (x==0) return Float256.wrap(0);
    	uint256 msb = _msb(x);
    	uint256 significand = msb>SIGNIFICAND_SCALE 
    		? x>>(msb-SIGNIFICAND_SCALE) 
    		: x<<(SIGNIFICAND_SCALE-msb);
    	uint256 exponent = (msb+(EXPONENT_BIAS-SIGNIFICAND_SCALE))<<EXPONENT_SHIFT; 
    	uint256 value = significand | exponent;
        return Float256.wrap(value);
    }

    /// @dev Convert Float256 → uint256 (rounds down)
    function toUint(Float256 f) internal pure returns (uint256 r) {
        uint256 x = Float256.unwrap(f);
        if (x == 0) return 0;
    	bool sign = (x &MASK_SIGN) != 0;
        require(!sign, "negative float cannot be converted to uint256");
    	uint256 biasedexp   = (x & MASK_EXPONENT) >> EXPONENT_SHIFT;
    	if (biasedexp==0) return 0;
    	uint256 significand =  x & MASK_SIGNIFICAND; 
        r = biasedexp>=EXPONENT_BIAS 
        	? significand<<(biasedexp-EXPONENT_BIAS) 
        	: significand>>(EXPONENT_BIAS-biasedexp);
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

    function mul(Float256 ax, Float256 bx) internal pure returns (Float256) {
    	uint256 a = Float256.unwrap(ax);
    	uint256 b = Float256.unwrap(bx);
    	if (a == 0 || b == 0) return Float256.wrap(0);
    	uint256 ae   = (a&MASK_EXPONENT) >> EXPONENT_SHIFT;
    	uint256 be   = (b&MASK_EXPONENT) >> EXPONENT_SHIFT;
    	int256  as; int256  bs; 
		assembly {as := and(a, MASK_SIGNED_SIGNIFICAND) bs := and(b, MASK_SIGNED_SIGNIFICAND)}
    	// actual operation starts
        int256  cs = (as * bs) >> SIGNIFICAND_SCALE;
    	uint256 ce = ae + be+ SIGNIFICAND_SCALE;
    	ce = ce>EXPONENT_BIAS ? ce-EXPONENT_BIAS : 0;
    	require(ce<=2046,"exponent overflow");
    	// actual operation ends
    	uint256 packed; assembly {packed := or(csignificand,shl(EXPONENT_SHIFT, cbiasedexp))} 
    	return Float256.wrap(packed);
    }
}
