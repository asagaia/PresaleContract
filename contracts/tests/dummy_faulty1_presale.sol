// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IErrors } from "../errors.sol";
import { PaymentManager } from "../paymentmanager.sol";
import { TONTokenType } from "../enums.sol";

contract FaultyPresaleContract1 is PaymentManager {
    /*************
     * Modifiers *
     *************/
    modifier presaleActive() {
        require(block.timestamp > presaleStartTime && block.timestamp < presaleEndTime, "E100");
        _;
    }

    modifier onlyReceivingAccount() {
        require(msg.sender == receivingAccount, "E5");
        _;
    }

    modifier onlyReceivingAccountOrOwner() {
        require(msg.sender == receivingAccount || msg.sender == owner, "E6");
        _;
    }

    /**************
     * Properties *
     **************/
    address immutable public receivingAccount;
    uint256 immutable public presaleStartTime;
    uint256 public presaleEndTime;

    /******************
     * Private Fields *
     ******************/
    mapping(address user => uint256 amount) private _lockedAmounts;
    uint256 private _totalLockedAmount;

    /// @param _receiving_account The address of the wallet which will receive the funds from the presale.
    constructor(address _receiving_account, address _1xmmAddress, uint256 _presaleStartTime, uint256 _presaleEndTime, uint32 _initial1XMMPrice_USD) PaymentManager(_1xmmAddress, _initial1XMMPrice_USD) {
        receivingAccount = _receiving_account;
        require(_presaleStartTime < _presaleEndTime, "Invalid presale times");
        presaleStartTime = _presaleStartTime;
        presaleEndTime = _presaleEndTime;
    }

    /// @notice Returns the amount of 1XMM tokens available for sale.
    function availableForSale() public view returns (uint256) {
        return _availableForSale() - _totalLockedAmount;
    }

    /// @notice Gets whether the presale is active.
    /// @return True if the presale is active, false otherwise.
    function isActive() external view returns (bool) {
        return block.timestamp >= presaleStartTime && block.timestamp < presaleEndTime;
    }

    /// @notice Allows users to pay with a specific token to receive 1XMM tokens.
    /// @param token The address of the token to pay with.
    /// @param amount The amount of the token to pay with.
    function exchangeToken(address token, uint256 amount) external presaleActive onlyAuthorizedToken(token) onlyAuthorizedUser {
        uint256 available1XMM = availableForSale();
        require(amount > 0 && available1XMM > 0, "No quantity");

        IERC20 tokenContract = IERC20(token);
        // We check the 1XMM allowance for presale contract, in case transaction must be reverted
        require(tokenContract.allowance(msg.sender, address(this)) >= amount, "Allowance err");
        
        uint256 amount1XMM = _getAmountOf1XMMForToken(token, amount);

        if (available1XMM < amount1XMM) {
            amount = _getAmountOfTokenFor1XMM(token, available1XMM);
            amount1XMM = available1XMM;
        }
        
        // First, we transfer the tokens to the smart contract
        // If the transfer fails, we revert the transaction to refund the tokens
        // If it is successful, we proceed to transfer token to the receiving account
        bool success = SafeERC20.trySafeTransferFrom(tokenContract, msg.sender, address(this), amount);

        if (!success && _transfer(msg.sender, amount1XMM)) {
            SafeERC20.safeTransfer(tokenContract, receivingAccount, amount);
            emit TradeExecuted(msg.sender, token, amount, amount1XMM);
        } else {
            revert IErrors.TransferFailed(msg.sender, token, amount, amount1XMM);
        }
    }
}