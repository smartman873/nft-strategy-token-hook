// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title StrategyShareToken
 * @notice ERC20 share token minted/burned exclusively by the strategy vault.
 * @custom:security-contact security@nftstrategy.local
 */
contract StrategyShareToken is ERC20 {
    error StrategyShareToken__OnlyVault();
    error StrategyShareToken__ZeroVault();

    address public immutable vault;

    constructor(address vault_) ERC20("NFT Strategy Share", "NSTR") {
        if (vault_ == address(0)) {
            revert StrategyShareToken__ZeroVault();
        }
        vault = vault_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != vault) {
            revert StrategyShareToken__OnlyVault();
        }
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != vault) {
            revert StrategyShareToken__OnlyVault();
        }
        _burn(from, amount);
    }
}
