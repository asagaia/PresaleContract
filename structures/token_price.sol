// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

struct TokenPrice {
    uint64 price;         // The amount of 1XMM tokens per 1 unit of this token
    uint8 decimals;      // The number of decimals the token uses
}