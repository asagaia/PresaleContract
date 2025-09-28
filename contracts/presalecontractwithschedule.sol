// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IErrors } from "./errors.sol";
import { BasePresaleContract } from "./basepresalecontract.sol";
import { TONTokenType } from "./enums.sol";

contract PresaleContractWithSchedule is BasePresaleContract {
    /// @param _receiving_account The address of the wallet which will receive the funds from the presale.
    constructor(address _receiving_account, address _1xmmAddress, uint _start_time, uint[] memory _period_lengths, uint32[] memory _token_prices) 
    BasePresaleContract(_receiving_account, _1xmmAddress, _token_prices[0]) {
        // Sanity check
        require(_period_lengths.length == _token_prices.length, "Bad schedule");

        presaleStartTime = _start_time;
        
        uint[] memory presalePeriodEnds = new uint[](_period_lengths.length);
        uint endTime = _start_time;

        for (uint16 i = 0; i < _period_lengths.length; i++) {
            endTime += _period_lengths[i];
            presalePeriodEnds[i] = endTime;
        }

        presaleSchedule.current_period_index = 0;
        presaleSchedule.next_period_index = 1;
        presaleSchedule.period_ends = presalePeriodEnds;
        presaleSchedule.token_prices = _token_prices;

        require(presaleStartTime <= endTime, "Invalid presale times");

        presaleEndTime = endTime;
        actualEndTime = endTime;
    }
}