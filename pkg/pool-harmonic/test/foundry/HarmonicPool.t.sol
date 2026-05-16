// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HarmonicPoolFactory} from "../../contracts/HarmonicPoolFactory.sol";
import {HarmonicPool} from "../../contracts/HarmonicPool.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IBasePool} from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import {SwapKind, PoolSwapParams} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
//import {Rounding} from "@balancer-labs/v3-solidity-utils/contracts/helpers/Rounding.sol";

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function totalSupply() external view override returns (uint256) { return type(uint256).max; }
}

contract HarmonicPoolTest is Test {
    // Contracts
    HarmonicPoolFactory public factory;
    HarmonicPool public pool;
    IVault public mockVault; // we will deploy a fake one or just use address(this)

    // Tokens
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    // MockERC20 public tokenC; // uncomment for 3-token tests

    IERC20[] public tokens;

    // Pool parameters
    uint256 constant P_VALUE = 2;           // or 4
    uint256[] public alphas;
    string constant POOL_NAME = "Harmonic 50/50 Pool";
    string constant POOL_SYMBOL = "HARM-50";
    string constant VERSION = "v0.1.0-test";

    address public constant FAKE_VAULT = address(0xBA5E);

	function setUp() public {
    	tokenA = new MockERC20("Token A", "TKNA");
    	tokenB = new MockERC20("Token B", "TKNB");
	
    	tokens = new IERC20[](2);
    	tokens[0] = IERC20(address(tokenA));
    	tokens[1] = IERC20(address(tokenB));
	
    	factory = new HarmonicPoolFactory(IVault(address(this)), 90 days);
	
    	uint256[] memory _alphas = new uint256[](2);
    	_alphas[0] = 5e17;
    	_alphas[1] = 5e17;
    		
    	address poolAddr = factory.create(
        	"Harmonic 50/50",
        	"HARM-50",
        	tokens,
        	2,                      // p=2
        	_alphas,       // will set below
        	"test-v1"
    	);
    	pool = HarmonicPool(poolAddr);
	
    	// Note: factory.create should accept alphas as calldata parameter
    	// If your factory signature is different, adjust accordingly
    	tokenA.mint(address(this), 50_000 ether);
    	tokenB.mint(address(this), 50_000 ether);
    	tokenA.approve(address(this), type(uint256).max); // if needed
    	tokenB.approve(address(this), type(uint256).max);
	}

    // ─────────────────────────────────────────────────────────────
    // Helper: Simulate first liquidity provision & thetas initialization
    // ─────────────────────────────────────────────────────────────
    function _initializePool(uint256 amountA, uint256 amountB) internal {
        uint256[] memory initialBalances = new uint256[](2);
        initialBalances[0] = amountA;
        initialBalances[1] = amountB;

        // In real Balancer v3, Vault would call setThetasOnce during first addLiquidity
        // Here we simulate that call
        vm.prank(FAKE_VAULT); // pretend to be vault
        pool.setThetasOnce(initialBalances);

        // Transfer tokens to pool (simulating liquidity provision)
        tokenA.transfer(address(pool), amountA);
        tokenB.transfer(address(pool), amountB);
    }

    // ─────────────────────────────────────────────────────────────
    // Basic Tests
    // ─────────────────────────────────────────────────────────────

    function testPoolCreationAndBasicGetters() public view {
        assertEq(pool.name(), POOL_NAME);
        assertEq(pool.symbol(), POOL_SYMBOL);
        //assertEq(pool.getP(), P_VALUE);
        assertEq(pool.getAlphas()[0], 5e17);
        assertEq(pool.getAlphas()[1], 5e17);
    }

    function testThetasInitialization() public {
        uint256 initialA = 1000 ether;
        uint256 initialB = 1000 ether;

        _initializePool(initialA, initialB);

        // Check thetas were set
        assertTrue(pool.getThetas()[0] > 0);
        assertTrue(pool.getThetas()[1] > 0);

        // For equal alphas and equal initial balances → thetas should be similar
        assertApproxEqAbs(pool.getThetas()[0], pool.getThetas()[1], 1e10, "thetas should be close");
    }

    function testComputeInvariantAfterInit() public {
        uint256 initialA = 2000 ether;
        uint256 initialB = 2000 ether;

        _initializePool(initialA, initialB);

        uint256[] memory balances = new uint256[](2);
        balances[0] = initialA;
        balances[1] = initialB;

        uint256 invariant = pool.computeInvariant(balances, Rounding.ROUND_DOWN);

        assertGt(invariant, 0);
        // For p=2 and equal weights/balances, invariant should be roughly proportional to sqrt(product)
    }

    // Very basic swap smoke test
    function testSmallSwapExactIn() public {
        // Initialize with decent liquidity
        _initializePool(5000 ether, 5000 ether);

        uint256[] memory balancesBefore = new uint256[](2);
        balancesBefore[0] = 5000 ether;
        balancesBefore[1] = 5000 ether;

        // Swap 100 TokenA in → get some TokenB out
        uint256 amountInScaled18 = 100 ether;

        // We simulate vault calling onSwap
        uint256 amountOutScaled18 = pool.onSwap(
            PoolSwapParams({
				kind: SwapKind.EXACT_IN,
        		amountGivenScaled18: amountInScaled18,
        		balancesScaled18: balancesBefore,
        		indexIn: 0,
        		indexOut: 1,
        		router: address(0),          // ← required field; use address(0) for simulation
        		userData: ""                
            })
        );

        assertGt(amountOutScaled18, 0);
        assertLt(amountOutScaled18, amountInScaled18); // should get less out (fees + curve)
    }
}
