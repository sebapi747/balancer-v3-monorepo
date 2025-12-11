// pkg/pool-harmonic/test/foundry/utils/HarmonicPoolDeployer.sol
pragma solidity ^0.8.24;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {HarmonicPoolFactory} from "../../../contracts/HarmonicPoolFactory.sol";
import {HarmonicPool} from "../../../contracts/HarmonicPool.sol";

contract HarmonicPoolDeployer {
    function deployPool(
        HarmonicPoolFactory factory,
        IERC20[] memory tokens,
        uint256 p
    ) external returns (HarmonicPool) {
		return HarmonicPool(
    		factory.create("Harmonic Pool", "HARM", tokens, p, "1.0.0")
		);
    }
}
