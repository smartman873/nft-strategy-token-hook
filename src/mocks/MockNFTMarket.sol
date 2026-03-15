// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MockStrategyNFT} from "src/mocks/MockStrategyNFT.sol";

/**
 * @title MockNFTMarket
 * @notice Deterministic demo market with predictable linear pricing.
 * @custom:security-contact security@nftstrategy.local
 */
contract MockNFTMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error MockNFTMarket__OutOfInventory();
    error MockNFTMarket__PriceExceedsLimit();
    error MockNFTMarket__ZeroAsset();
    error MockNFTMarket__ZeroMaxSupply();

    IERC20 public immutable asset;
    MockStrategyNFT public immutable nft;

    uint256 public immutable basePrice;
    uint256 public immutable priceStep;
    uint256 public immutable maxSupply;

    uint256 public nextTokenId;

    event NFTPurchased(address indexed buyer, address indexed recipient, uint256 indexed tokenId, uint256 price);

    constructor(IERC20 asset_, uint256 basePrice_, uint256 priceStep_, uint256 maxSupply_, address initialOwner)
        Ownable(initialOwner)
    {
        if (address(asset_) == address(0)) {
            revert MockNFTMarket__ZeroAsset();
        }
        if (maxSupply_ == 0) {
            revert MockNFTMarket__ZeroMaxSupply();
        }

        asset = asset_;
        basePrice = basePrice_;
        priceStep = priceStep_;
        maxSupply = maxSupply_;
        nft = new MockStrategyNFT(address(this));
    }

    function quoteNextPrice() public view returns (uint256 price) {
        price = basePrice + (priceStep * nextTokenId);
    }

    function floorPrice() external view returns (uint256 price) {
        price = quoteNextPrice();
    }

    function buyNext(address recipient, uint256 maxPrice)
        external
        nonReentrant
        returns (uint256 tokenId, uint256 price)
    {
        if (nextTokenId >= maxSupply) {
            revert MockNFTMarket__OutOfInventory();
        }

        price = quoteNextPrice();
        if (price > maxPrice) {
            revert MockNFTMarket__PriceExceedsLimit();
        }

        asset.safeTransferFrom(msg.sender, address(this), price);

        tokenId = nextTokenId + 1;
        nextTokenId = tokenId;

        nft.mintForMarket(tokenId);
        nft.safeTransferFrom(address(this), recipient, tokenId);

        emit NFTPurchased(msg.sender, recipient, tokenId, price);
    }
}
