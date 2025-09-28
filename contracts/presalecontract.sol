// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IErrors } from "./errors.sol";
import { BasePresaleContract } from "./basepresalecontract.sol";
import { TONTokenType } from "./enums.sol";

contract PresaleContract is BasePresaleContract {
    /// @param _receiving_account The address of the wallet which will receive the funds from the presale.
    constructor(address _receiving_account, address _1xmmAddress, uint256 _presaleStartTime, uint256 _presaleEndTime, uint32 _initial1XMMPrice_USD) 
    BasePresaleContract(_receiving_account, _1xmmAddress, _initial1XMMPrice_USD) {
        require(_presaleStartTime < _presaleEndTime, "Invalid presale times");
        presaleStartTime = _presaleStartTime;

        presaleSchedule.current_period_index = 0;
        presaleSchedule.next_period_index = 1;
        presaleSchedule.period_ends = [_presaleEndTime];
        presaleSchedule.token_prices = [_initial1XMMPrice_USD];

        presaleEndTime = _presaleEndTime;
        actualEndTime = _presaleEndTime;
    }
}