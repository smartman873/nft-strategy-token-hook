// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IStrategyVault {
    function captureRevenue(
        bytes32 poolId,
        address token,
        uint256 amount,
        uint128 acquireThreshold,
        uint8 valuationMode,
        uint64 policyNonce
    ) external;
}
