// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {FeeRouter} from "src/FeeRouter.sol";
import {NFTTreasury} from "src/NFTTreasury.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {MockNFTMarket} from "src/mocks/MockNFTMarket.sol";
import {NFTStrategyHook} from "src/NFTStrategyHook.sol";
import {IStrategyVault} from "src/interfaces/IStrategyVault.sol";

contract DeployStrategyStackScript is Script {
    uint256 internal constant TOKEN_MINT = 1_000_000e18;
    uint256 internal constant NFT_BASE_PRICE = 1e16;
    uint256 internal constant NFT_PRICE_STEP = 1e15;
    uint256 internal constant NFT_MAX_SUPPLY = 1000;

    struct DeployResult {
        MockERC20 token0;
        MockERC20 token1;
        FeeRouter feeRouter;
        NFTTreasury nftTreasury;
        MockNFTMarket mockMarket;
        StrategyVault strategyVault;
        NFTStrategyHook hook;
    }

    function run() external {
        address poolManagerAddress = vm.envOr("POOL_MANAGER_ADDRESS", vm.envOr("POOL_MANAGER", address(0)));
        require(poolManagerAddress != address(0), "DeployStrategyStack: missing pool manager");

        address owner = vm.envOr("OWNER_ADDRESS", vm.envOr("OWNER", msg.sender));

        vm.startBroadcast();
        DeployResult memory deployed = _deploy(owner, IPoolManager(poolManagerAddress));
        deployed.token0.mint(owner, TOKEN_MINT);
        deployed.token1.mint(owner, TOKEN_MINT);
        vm.stopBroadcast();

        _envLog("DEMO_TOKEN0_ADDRESS", address(deployed.token0));
        _envLog("DEMO_TOKEN1_ADDRESS", address(deployed.token1));
        _envLog("ASSET_TOKEN", address(deployed.token1));
        _envLog("REVENUE_TOKEN_ADDRESS", address(deployed.token1));
        _envLog("REVENUE_TOKEN", address(deployed.token1));
        _envLog("FEE_ROUTER_ADDRESS", address(deployed.feeRouter));
        _envLog("FEE_ROUTER", address(deployed.feeRouter));
        _envLog("NFT_TREASURY_ADDRESS", address(deployed.nftTreasury));
        _envLog("MOCK_NFT_MARKET_ADDRESS", address(deployed.mockMarket));
        _envLog("STRATEGY_VAULT_ADDRESS", address(deployed.strategyVault));
        _envLog("NFT_STRATEGY_HOOK_ADDRESS", address(deployed.hook));
        _envLog("NFT_STRATEGY_HOOK", address(deployed.hook));
        _envLog("STRATEGY_SHARE_TOKEN_ADDRESS", address(deployed.strategyVault.shareToken()));
        _envLog("TREASURY_RECIPIENT", owner);

        console2.log("deploy: strategy stack deployed");
        console2.log("deploy: hook", address(deployed.hook));
        console2.log("deploy: strategyVault", address(deployed.strategyVault));
    }

    function _deploy(address owner, IPoolManager poolManager) internal returns (DeployResult memory deployed) {
        MockERC20 tokenA = new MockERC20("Demo Token A", "DTA", 18);
        MockERC20 tokenB = new MockERC20("Demo Token B", "DTB", 18);

        (deployed.token0, deployed.token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        deployed.feeRouter = new FeeRouter(owner);
        deployed.nftTreasury = new NFTTreasury(owner);
        deployed.mockMarket = new MockNFTMarket(
            IERC20(address(deployed.token1)), NFT_BASE_PRICE, NFT_PRICE_STEP, NFT_MAX_SUPPLY, owner
        );
        deployed.strategyVault = new StrategyVault(
            IERC20(address(deployed.token1)),
            deployed.feeRouter,
            deployed.nftTreasury,
            deployed.mockMarket,
            owner
        );

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, deployed.strategyVault, owner);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(NFTStrategyHook).creationCode, constructorArgs);

        deployed.hook =
            new NFTStrategyHook{salt: salt}(poolManager, IStrategyVault(address(deployed.strategyVault)), owner);
        require(address(deployed.hook) == hookAddress, "DeployStrategyStack: Hook Address Mismatch");

        deployed.strategyVault.setHook(address(deployed.hook));
        deployed.nftTreasury.setVault(address(deployed.strategyVault));
    }

    function _envLog(string memory key, address value) internal view {
        console2.log(string.concat("ENV:", key, "=", vm.toString(value)));
    }
}
