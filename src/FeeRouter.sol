// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeRouter
 * @notice Per-pool deterministic split policy for captured hook revenue.
 * @custom:security-contact security@nftstrategy.local
 */
contract FeeRouter is Ownable {
    error FeeRouter__InvalidSplit();
    error FeeRouter__TreasuryRequired();

    uint16 public constant MAX_BPS = 10_000;

    struct PoolSplit {
        uint16 strategyBps;
        uint16 treasuryBps;
        address treasuryRecipient;
    }

    mapping(bytes32 poolId => PoolSplit split) public poolSplits;

    event PoolSplitSet(bytes32 indexed poolId, uint16 strategyBps, uint16 treasuryBps, address treasuryRecipient);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setPoolSplit(bytes32 poolId, uint16 strategyBps, uint16 treasuryBps, address treasuryRecipient)
        external
        onlyOwner
    {
        if (uint256(strategyBps) + uint256(treasuryBps) != MAX_BPS) {
            revert FeeRouter__InvalidSplit();
        }
        if (treasuryBps > 0 && treasuryRecipient == address(0)) {
            revert FeeRouter__TreasuryRequired();
        }

        poolSplits[poolId] =
            PoolSplit({strategyBps: strategyBps, treasuryBps: treasuryBps, treasuryRecipient: treasuryRecipient});

        emit PoolSplitSet(poolId, strategyBps, treasuryBps, treasuryRecipient);
    }

    function quoteRoute(bytes32 poolId, uint256 amount)
        external
        view
        returns (uint256 strategyAmount, uint256 treasuryAmount, address treasuryRecipient)
    {
        (strategyAmount, treasuryAmount, treasuryRecipient) = _route(poolId, amount);
    }

    function route(bytes32 poolId, uint256 amount)
        external
        view
        returns (uint256 strategyAmount, uint256 treasuryAmount, address treasuryRecipient)
    {
        (strategyAmount, treasuryAmount, treasuryRecipient) = _route(poolId, amount);
    }

    function _route(bytes32 poolId, uint256 amount)
        internal
        view
        returns (uint256 strategyAmount, uint256 treasuryAmount, address treasuryRecipient)
    {
        PoolSplit memory split = poolSplits[poolId];

        if (split.strategyBps == 0 && split.treasuryBps == 0) {
            return (amount, 0, address(0));
        }

        treasuryAmount = (amount * split.treasuryBps) / MAX_BPS;
        strategyAmount = amount - treasuryAmount;
        treasuryRecipient = split.treasuryRecipient;
    }
}
