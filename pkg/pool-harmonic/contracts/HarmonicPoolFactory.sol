// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { HarmonicPool } from "./HarmonicPool.sol";

contract HarmonicPoolFactory is BasePoolFactory {
    constructor(
        IVault vault,
        uint32 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(HarmonicPool).creationCode) {}

    function create(
        string memory name,
        string memory symbol,
        IERC20[] calldata tokens,
        uint256 p,
        uint256[] calldata alphas,
        string memory version
    ) external returns (address pool) {
        HarmonicPool.NewPoolParams memory params = HarmonicPool.NewPoolParams({
            name: name,
            symbol: symbol,
            tokens: tokens,
            p: p,
            alphas: alphas,
            version: version
        });

        // This is the exact pattern used by WeightedPoolFactory, StablePoolFactory, etc.
        pool = _create(abi.encode(params, getVault()), bytes32(0));

        TokenConfig[] memory tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
        	tokenConfig[i] = TokenConfig({
    			token: tokens[i],
    			tokenType: TokenType(0),  // ← explicit enum cast
    			rateProvider: IRateProvider(address(0)),  // ← explicit interface cast
    			paysYieldFees: false
			});
        }

        LiquidityManagement memory lm;

		_registerPoolWithVault(
    		pool,
    		tokenConfig,
    		0,           // swapFeePercentage
    		false,       // not exempt
    		PoolRoleAccounts(address(0), address(0), address(0)),  // pauseManager, swapFeeManager, poolCreator all address(0)
    		address(0),  // poolHooksContract
    		lm
		);

        return pool;
    }
}
