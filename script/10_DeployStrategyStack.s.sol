// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {NFTTreasury} from "src/NFTTreasury.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {MockNFTMarket} from "src/mocks/MockNFTMarket.sol";
import {NFTStrategyHook} from "src/NFTStrategyHook.sol";
import {IStrategyVault} from "src/interfaces/IStrategyVault.sol";

contract DeployStrategyStackScript is Script {
    function run() external {
        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        IERC20 asset = IERC20(vm.envAddress("ASSET_TOKEN"));
        address owner = vm.envAddress("OWNER");

        vm.startBroadcast();

        FeeRouter feeRouter = new FeeRouter(owner);
        NFTTreasury nftTreasury = new NFTTreasury(owner);
        MockNFTMarket mockMarket = new MockNFTMarket(asset, 1e16, 1e15, 1000, owner);
        StrategyVault strategyVault = new StrategyVault(asset, feeRouter, nftTreasury, mockMarket, owner);

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);

        bytes memory constructorArgs = abi.encode(poolManager, strategyVault, owner);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(NFTStrategyHook).creationCode, constructorArgs);

        NFTStrategyHook hook =
            new NFTStrategyHook{salt: salt}(poolManager, IStrategyVault(address(strategyVault)), owner);
        require(address(hook) == hookAddress, "DeployStrategyStack: Hook Address Mismatch");

        strategyVault.setHook(address(hook));
        nftTreasury.setVault(address(strategyVault));

        vm.stopBroadcast();

        console2.log("feeRouter:", address(feeRouter));
        console2.log("nftTreasury:", address(nftTreasury));
        console2.log("mockMarket:", address(mockMarket));
        console2.log("strategyVault:", address(strategyVault));
        console2.log("hook:", address(hook));
        console2.log("shareToken:", address(strategyVault.shareToken()));
    }
}
