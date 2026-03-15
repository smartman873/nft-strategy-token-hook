// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MockStrategyNFT
 * @notice Internal deterministic NFT collection minted by MockNFTMarket.
 * @custom:security-contact security@nftstrategy.local
 */
contract MockStrategyNFT is ERC721 {
    error MockStrategyNFT__OnlyMarket();

    address public immutable market;

    constructor(address market_) ERC721("Strategy Treasury Collectible", "STC") {
        market = market_;
    }

    function mintForMarket(uint256 tokenId) external {
        if (msg.sender != market) {
            revert MockStrategyNFT__OnlyMarket();
        }
        _mint(market, tokenId);
    }
}
