# CHMM (Constant Harmonic Market Maker) Summary

**Core Concept**: New CFMM variant that generalizes CPMM using harmonic mean of inverse powers to reduce impermanent loss.

**Key Equations**:
1. **Binding Function**: `∑ γᵢ/Qᵢᵖ = constant` where `γᵢ = αᵢᵖ⁺¹/Xᵢ(0)ᵖ`
2. **Theta Definition**: `θᵢ = αᵢ/Xᵢ(0)` (for scale-invariant representation)
3. **Swap Formula** (γ-version, floating-point friendly):  
   `Qᵢ' = (γᵢ/(γᵢ/Qᵢᵖ + γⱼ/Qⱼᵖ - γⱼ/(Qⱼ+δQⱼ)ᵖ))¹/ᵖ`, then `δQᵢ = Qᵢ' - Qᵢ`
4. **Swap Formula** (θ-version, scale-invariant):  
   With `Q̃ᵢ = θᵢ/Qᵢ`:  
   `δQᵢ = θᵢ × (αᵢ/(αᵢQ̃ᵢᵖ + αⱼ(Q̃ⱼᵖ - Q̃ⱼ'ᵖ)))¹/ᵖ - Qᵢ` where `Q̃ⱼ' = θⱼ/(Qⱼ+δQⱼ)`

**Implementation Notes**:
- **Fixed-point issues**: Initially tried 10¹⁸ scaling (standard DeFi) but caused underflow for p=4  
  - Reduced to 10⁶ scaling works but loses precision (too approximative for real use)
- **Solution**: Created `FloatRepBinary` custom 80-bit float (mantissa:int64, exponent:int16)
- Binary base for efficiency: `value = mantissa × 2^exponent`
- Only used in swap computation for numerical stability

**Classes**:
- python `CHMM`: Base with float64 numpy
- python `CHMMFloatRepBinary`: Uses custom float for swaps
- python `FloatRepBinary`: Minimal float struct for on-chain efficiency. 
   The python implementation has two int but is not optimized yet.

**Purpose**: Tunable AMM where parameter `p` interpolates between CPMM (p→0) and HODL (p→∞).

pkg/pool-harmonic/
├── contracts/
│   ├── HarmonicPool.sol                 ← main pool (template: WeightedPool.sol)
│   ├── HarmonicPoolFactory.sol          ← factory (template: WeightedPoolFactory.sol)
│   ├── HarmonicMath.sol                 ← all CHMM math + swap formulas
│   └── FloatRepBinary.sol               ← custom 80-bit float struct + ops
│
├── test/
│   └── foundry/
│       ├── HarmonicPool.t.sol           ← full pool tests
│       ├── HarmonicMath.t.sol           ← pure math tests
│       └── utils/
│           └── HarmonicPoolDeployer.sol ← deployment helper
│
└── README.md                            ← short description + equations + p meaning
