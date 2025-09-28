// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct Schedule {
    uint16 current_period_index;    // The index of the current period
    uint16 next_period_index;       // The index of the next period
    uint[] period_ends;             // The end timestamp, in second, of each period
    uint32[] token_prices;         // The price of the token in each period, with 4 digits precision (e.g., 500 for $0.05)
}