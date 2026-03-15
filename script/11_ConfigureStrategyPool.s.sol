// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {NFTStrategyHook} from "src/NFTStrategyHook.sol";

contract ConfigureStrategyPoolScript is Script {
    function run() external {
        FeeRouter feeRouter = FeeRouter(vm.envAddress("FEE_ROUTER"));
        NFTStrategyHook hook = NFTStrategyHook(vm.envAddress("NFT_STRATEGY_HOOK"));

        PoolKey memory poolKey = abi.decode(vm.parseJson(vm.readFile(vm.envString("POOL_KEY_JSON"))), (PoolKey));

        uint16 treasuryBps = uint16(vm.envUint("TREASURY_BPS"));
        uint16 strategyBps = 10_000 - treasuryBps;
        address treasuryRecipient = vm.envAddress("TREASURY_RECIPIENT");

        NFTStrategyHook.PoolRevenueConfig memory config = NFTStrategyHook.PoolRevenueConfig({
            enabled: vm.envBool("REVENUE_ENABLED"),
            revenueToken: vm.envAddress("REVENUE_TOKEN"),
            revenueShareBps: uint16(vm.envUint("REVENUE_SHARE_BPS")),
            acquireThreshold: uint128(vm.envUint("ACQUIRE_THRESHOLD")),
            valuationMode: uint8(vm.envUint("VALUATION_MODE")),
            policyNonce: uint64(vm.envUint("POLICY_NONCE"))
        });

        vm.startBroadcast();
        feeRouter.setPoolSplit(keccak256(abi.encode(poolKey)), strategyBps, treasuryBps, treasuryRecipient);
        hook.setPoolRevenueConfig(poolKey, config);
        vm.stopBroadcast();
    }
}
