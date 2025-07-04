// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IErrors } from "./errors.sol";
import { PaymentManager } from "./paymentmanager.sol";
import { TONTokenType } from "./enums.sol";

contract PresaleContract is PaymentManager {
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

    /// @notice Returns the amount of 1XMM tokens that can be purchased for a given amount of a specific token.
    /// @param token The address of the token to pay with. If address(0) is provided, it means ETH.
    /// @param amount The amount of the token to pay with.
    function getExpectedAmountOf1XMM(address token, uint256 amount) external view onlyAuthorizedToken(token) returns (uint256) {
        if (token == address(0)) {
            // If the token is ETH, we use WETH address
            token = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        }
        
        uint256 available1XMM = availableForSale();
        uint256 amount1XMM = _getAmountOf1XMMForToken(token, amount);

        if (available1XMM < amount1XMM) amount1XMM = available1XMM;
        return amount1XMM;
    }

    /// @notice Allows user to pay with ETH to receive 1XMM tokens.
    function exchangeETH() external payable presaleActive onlyAuthorizedUser {
        uint256 amount = msg.value;
        uint256 available1XMM = availableForSale();
        require(amount > 0 && available1XMM > 0, "No quantity");
        
        uint256 amount1XMM = _getAmountOf1XMMForToken(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), amount);

        if (available1XMM < amount1XMM) {
            amount = _getAmountOfTokenFor1XMM(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), available1XMM);
            amount1XMM = available1XMM;

            payable(msg.sender).transfer(msg.value - amount);
        }

        // If transfer fails, we refund the Ether
        if (_transfer(msg.sender, amount1XMM)) {
            emit TradeExecuted(msg.sender, address(0), amount, amount1XMM);
        } else {
            // We keep track record of failed trades
            // and revert the transaction to refund the Ether
            emit TradeFailed(msg.sender, address(0), amount, amount1XMM);
            payable(msg.sender).transfer(amount);
            revert IErrors.TransferFailed(msg.sender, address(0), amount, amount1XMM);
        }
    }

    /// @notice Enables the owner to transfer a specified amount of Ether to the owner's address.
    function transferETHToReceivingAccount(uint256 value) external onlyReceivingAccountOrOwner payable {
        uint256 balance = address(this).balance;
        if (balance <= 0 && value > balance) revert IErrors.ETHBalanceError(balance, value);
        payable(receivingAccount).transfer(value);
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

        if (success) {
            if (_transfer(msg.sender, amount1XMM)) {
                SafeERC20.safeTransfer(tokenContract, receivingAccount, amount);
                emit TradeExecuted(msg.sender, token, amount, amount1XMM);
            }
            else {
                success = SafeERC20.trySafeTransfer(tokenContract, msg.sender, amount);

                if (success) {
                    emit TradeFailed(msg.sender, token, amount, amount1XMM);
                    revert IErrors.TransferFailed(msg.sender, token, amount, amount1XMM);
                } else {
                    emit FailedTradeNotReverted(msg.sender, token, amount, amount1XMM);
                    revert IErrors.TransferFailedAndNotRevert(msg.sender, token, amount, amount1XMM);
                }
            }
        } else {
            emit TradeFailed(msg.sender, token, amount, amount1XMM);
            revert IErrors.TransferFailed(msg.sender, token, amount, amount1XMM);
        }
    }

    /// @notice Locks a specified amount of 1XMM tokens for a beneficiary.
    /// @param beneficiary The address of the beneficiary to lock the tokens for.
    /// @param amount1XMM The amount of 1XMM tokens to lock.
    /// @dev This function can only be called by the owner of the contract - the function shall be called
    ///       before executing a transfer on the TON blockchain, to ensure that the beneficiary has enough 
    ///       locked tokens to satisfy the transfer requirements.
    function lockAmount(address beneficiary, uint256 amount1XMM) external onlyOwner presaleActive {
        require(availableForSale() >= amount1XMM, "E101");
        _lockedAmounts[beneficiary] += amount1XMM;
        _totalLockedAmount += amount1XMM;
    }


    /// @notice Transfers a specified amount of 1XMM tokens to a beneficiary
    /// @param to The address of the beneficiary
    /// @param tokenType The type of the token which were provided by `to` on the TON blockchain.
    /// @param amount The amount of `tokenType` tokens which were provided.
    /// @param amount1XMM The amount of 1XMM tokens to transfer to `to`.
    function transfer(address to, uint8 tokenType, uint256 amount, uint256 amount1XMM) external onlyOwner presaleActive returns(bool) {
        require(_lockedAmounts[to] >= amount1XMM, "E102");
        _lockedAmounts[to] -= amount1XMM;

        bool success = _transfer(to, amount1XMM);

        if (success) {
            unlockAmount(to, amount1XMM);
            emit TONTradeExecuted(to, TONTokenType(tokenType), amount, amount1XMM);
            
        } else {
            emit TONTradeFailed(to, TONTokenType(tokenType), amount, amount1XMM);
            revert IErrors.TransferForTONFailed(to, TONTokenType(tokenType), amount, amount1XMM);
        }

        return success;
    }

    /// @notice Unlocks a specified amount of 1XMM tokens for `forBeneficiary`.
    /// @dev This function can only be called by the owner of the contract - function is called
    ///       to unlock tokens that were locked for a beneficiary, in case a transfer was not executed.
    function unlockAmount(address forBeneficiary, uint256 amount1XMM) public onlyOwner presaleActive {
        require(_lockedAmounts[forBeneficiary] >= amount1XMM, "E103");
        _lockedAmounts[forBeneficiary] -= amount1XMM;
        _totalLockedAmount -= amount1XMM;
    }

    /// @notice Ends the presale by setting the end time to the current block timestamp.
    function endPresale() external onlyOwner {
        presaleEndTime = block.timestamp;
    }
}