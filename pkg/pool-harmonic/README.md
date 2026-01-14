# CHMM (Constant Harmonic Market Maker) Summary

**Core Concept**: New CFMM variant that generalizes CPMM using harmonic mean of inverse powers to reduce impermanent loss.
Only **p = 1, 2, 4** are supported for gas efficiency, simplicity, and reliable numerical behavior.
This is a minimal fork on balancer-v3-monorepo.

This implementation is based on the theory presented in: "Multi-Asset Constant Harmonic Market Maker" mchmm.pdf.

## Theoretical Foundation

The CHMM invariant ∑ γᵢ/Qᵢᵖ = constant provides:
- **Ruin protection**: Qᵢ → k > 0 as Xᵢ → 0
- **Unlimited upside**: Full exposure to appreciating assets
- **Dynamic rebalancing**: Portfolio weights wᵢ = aᵢXᵢᵐ/∑aⱼXⱼᵐ

See mchmm.pdf Sections 2-4 for detailed derivations.


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
- **Solution**: Created `Float256` custom 256-bit float (signed significand:int244, exponent:uint11)
- Binary base for efficiency: `value = significand × 2^{exponent-bias}`
- Only used in swap computation for numerical stability

**Purpose**: Tunable AMM where parameter `m = p/(p+1)` interpolates between CPMM (m→0, p→0) and HODL (m→1, p→∞).
In practice, we plan to use p=1 (m=0.5) or p=4 (m=0.8).

pkg/pool-harmonic/
├── contracts/
│   ├── HarmonicPool.sol                 ← main pool (template: WeightedPool.sol)
│   ├── HarmonicPoolFactory.sol          ← factory (template: WeightedPoolFactory.sol)
│   └── Float256.sol               		 ← performance 256bit floating point library 
│
├── test/
│   └── foundry/
│       ├── HarmonicPool.t.sol           ← full pool tests
│       ├── Float256.t.sol               ← pure float point math test
│       └── utils/
│           └── HarmonicPoolDeployer.sol ← deployment helper
│
└── README.md                            ← short description + equations + p meaning
