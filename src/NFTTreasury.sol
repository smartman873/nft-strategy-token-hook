// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title NFTTreasury
 * @notice Custodies acquired NFTs and provides inventory accounting for frontend/indexers.
 * @custom:security-contact security@nftstrategy.local
 */
contract NFTTreasury is Ownable, ERC721Holder {
    error NFTTreasury__OnlyVault();
    error NFTTreasury__ZeroVault();

    struct InventoryItem {
        address nftContract;
        uint256 tokenId;
        uint256 cost;
        uint64 acquiredAt;
    }

    address public vault;

    mapping(bytes32 poolId => InventoryItem[] items) private _inventoryByPool;
    mapping(address nftContract => uint256[] tokenIds) private _inventoryByCollection;

    event VaultSet(address indexed vault);
    event InventoryRecorded(bytes32 indexed poolId, address indexed nftContract, uint256 tokenId, uint256 cost);
    event Swept(address indexed nftContract, uint256 indexed tokenId, address indexed to);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) {
            revert NFTTreasury__ZeroVault();
        }
        vault = vault_;
        emit VaultSet(vault_);
    }

    function recordAcquisition(bytes32 poolId, address nftContract, uint256 tokenId, uint256 cost) external {
        if (msg.sender != vault) {
            revert NFTTreasury__OnlyVault();
        }

        _inventoryByPool[poolId].push(
            InventoryItem({nftContract: nftContract, tokenId: tokenId, cost: cost, acquiredAt: uint64(block.timestamp)})
        );
        _inventoryByCollection[nftContract].push(tokenId);

        emit InventoryRecorded(poolId, nftContract, tokenId, cost);
    }

    function inventoryForPool(bytes32 poolId) external view returns (InventoryItem[] memory items) {
        items = _inventoryByPool[poolId];
    }

    function inventoryCount(bytes32 poolId) external view returns (uint256 count) {
        count = _inventoryByPool[poolId].length;
    }

    function tokenIdsForCollection(address nftContract) external view returns (uint256[] memory tokenIds) {
        tokenIds = _inventoryByCollection[nftContract];
    }

    function sweep(address nftContract, uint256 tokenId, address to) external onlyOwner {
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
        emit Swept(nftContract, tokenId, to);
    }
}
