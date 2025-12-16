// SPDX-License-Identifier: BUSL-1.1
// pkg/pool-harmonic/test/foundry/HarmonicPool.t.sol
pragma solidity ^0.8.24;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {Test} from "forge-std/Test.sol";
import {HarmonicPoolFactory} from "../../contracts/HarmonicPoolFactory.sol";
import {HarmonicPool} from "../../contracts/HarmonicPool.sol";

contract HarmonicPoolTest is Test {
    HarmonicPoolFactory factory;
    HarmonicPool pool;
    IERC20[] tokens;

    function setUp() public {
        // Mock Vault + standard pause window duration (same as WeightedPoolFactory uses)
	    factory = new HarmonicPoolFactory(IVault(address(0xdead)), 90 days); // short, valid, no issues
        // TODO: add real tokens and create pool with p = 4 for first test
    }

    function testSwap() public {
        // TODO
    }
}
