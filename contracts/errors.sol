// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { TONTokenType } from "./enums.sol";

interface IErrors {
    /// @notice Error thrown when a transfer fails on Ethereum chain.
    /// @param to The address of the receiver.
    /// @param token The token which was offered in the transfer.
    /// @param amount The token amount
    /// @param onexmmAmount The amount of 1XMM tokens that were supposed to be transferred.
    error TransferFailed(address to, address token, uint256 amount, uint256 onexmmAmount);

    /// @notice Error thrown when a transfer fails for TON chain vcpayment.
    /// @param to The address of the receiver.
    /// @param token The token which was offered in the transfer.
    /// @param amount The token amount
    /// @param onexmmAmount The amount of 1XMM tokens that were supposed to be transferred.
    error TransferForTONFailed(address to, TONTokenType token, uint256 amount, uint256 onexmmAmount);

    /// @notice Error thrown when a transfer fails on Ethereum chain but does not revert.
    /// @param to The address of the receiver.
    /// @param token The token which was offered in the transfer.
    /// @param amount The token amount
    /// @param onexmmAmount The amount of 1XMM tokens that were supposed to be transferred.
    error TransferFailedAndNotRevert(address to, address token, uint256 amount, uint256 onexmmAmount);

    /// @notice Error thrown when the ETH balance of the contract is not enough to cover the value.
    /// @param balance The current ETH balance of the contract.
    /// @param value The value that was attempted to be transferred.
    error ETHBalanceError(uint256 balance, uint256 value);
}