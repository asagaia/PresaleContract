// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IErrors } from "./errors.sol";
import { PaymentManager } from "./paymentmanager.sol";
import { TONTokenType } from "./enums.sol";

contract PresaleContract is PaymentManager {
    /**********
     * Events *
     **********/
    event ETHWithdrawal(uint256 balanceBefore, uint256 balanceAfter);
    event TokenWithdrawal(address indexed token, uint256 balanceBefore, uint256 balanceAfter);

    /*************
     * Modifiers *
     *************/
    modifier presaleActive() {
        require(block.timestamp > presaleStartTime && block.timestamp < actualEndTime, "E100");
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
    uint256 public presaleStartTime;
    uint256 public actualEndTime;
    uint256 public immutable presaleEndTime;

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
        actualEndTime = _presaleEndTime;
    }

    /// @notice Returns the amount of 1XMM tokens available for sale.
    function availableForSale() public view returns (uint256) {
        return _availableForSale() - _totalLockedAmount;
    }

    /// @notice Gets whether the presale is active.
    /// @return True if the presale is active, false otherwise.
    function isActive() external view returns (bool) {
        return block.timestamp >= presaleStartTime && block.timestamp < actualEndTime;
    }

    /// @notice Returns the amount of 1XMM tokens that can be purchased for a given amount of a specific token.
    /// @param token The address of the token to pay with. If address(0) is provided, it means ETH.
    /// @param amount The amount of the token to pay with.
    function getExpectedAmountOf1XMM(address token, uint256 amount) external view onlyAuthorizedToken(token) returns (uint256) {
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
        
        uint256 amount1XMM = _getAmountOf1XMMForToken(WETH, amount);
        bool isInExcess = false;

        if (available1XMM < amount1XMM) {
            amount = _getAmountOfTokenFor1XMM(WETH, available1XMM);
            amount1XMM = available1XMM;
            isInExcess = true;
        }

        // If transfer fails, we refund the Ether
        if (_transfer(msg.sender, amount1XMM)) {
            if (availableForSale() == 0) _endPresale();
            emit TradeExecuted(msg.sender, address(0), amount, amount1XMM);

            if (isInExcess) {
                (bool success, ) = payable(msg.sender).call{value: msg.value - amount}("");
                require(success, "Transfer failed");
            }
        } else {
            // We trigger an error
            revert IErrors.TransferFailed(msg.sender, address(0), amount, amount1XMM);
        }
    }

    /// @notice Enables the owner to transfer a specified amount of Ether to the owner's address.
    function transferETHToReceivingAccount(uint256 value) external onlyReceivingAccountOrOwner payable {
        uint256 balance = address(this).balance;
        if (balance == 0 || value == 0 || value > balance) revert IErrors.ETHBalanceError(balance, value);

        payable(receivingAccount).transfer(value);
        emit ETHWithdrawal(balance, address(this).balance);
    }

    /// @notice Allows users to pay with a specific token to receive 1XMM tokens.
    /// @param token The address of the token to pay with.
    /// @param amount The amount of the token to pay with.
    function exchangeToken(address token, uint256 amount) external presaleActive onlyAuthorizedToken(token) onlyAuthorizedUser {
        uint256 available1XMM = availableForSale();
        require(amount > 0 && available1XMM > 0, "No quantity");

        IERC20 tokenContract = IERC20(token);
        uint allowance = tokenContract.allowance(msg.sender, address(this));
        // We check the 1XMM allowance for presale contract, in case transaction must be reverted
        require(allowance >= amount, "Insufficient allowance");
        
        uint256 amount1XMM = _getAmountOf1XMMForToken(token, amount);

        if (available1XMM < amount1XMM) {
            amount = _getAmountOfTokenFor1XMM(token, available1XMM);
            amount1XMM = available1XMM;
        }
        
        // First, we transfer the tokens to the smart contract
        // If the transfer fails, we revert the transaction to refund the tokens
        // If it is successful, we proceed to transfer token to the receiving account
        bool success = SafeERC20.trySafeTransferFrom(tokenContract, msg.sender, address(this), amount);

        if (success && _transfer(msg.sender, amount1XMM)) {
            SafeERC20.safeTransfer(tokenContract, receivingAccount, amount);

            if (availableForSale() == 0) _endPresale();
            emit TradeExecuted(msg.sender, token, amount, amount1XMM);
        } else {
            revert IErrors.TransferFailed(msg.sender, token, amount, amount1XMM);
        }
    }

    /// @notice If there is a remaining balance of token, transfers it back to the receiving account
    /// @dev This function should be called 
    function transferAuthorizedTokensToReceivingAccount(address token) external onlyAuthorizedToken(token) onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        SafeERC20.safeTransfer(tokenContract, receivingAccount, balance);

        emit TokenWithdrawal(token, balance, 0);
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
    /// @dev This function is called when a user does a TON payment
    /// @param to The address of the beneficiary
    /// @param tokenType The type of the token which were provided by `to` on the TON blockchain.
    /// @param amount The amount of `tokenType` tokens which were provided.
    /// @param amount1XMM The amount of 1XMM tokens to transfer to `to`.
    function transfer(address to, uint8 tokenType, uint256 amount, uint256 amount1XMM) external onlyOwner presaleActive returns(bool) {
        require(_lockedAmounts[to] >= amount1XMM, "E102");
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

    /// @notice Transfers the remaining amount of 1XMM tokens to the 1XMM smart contract
    /// @dev This automatically ends the pre-sale
    function transferRemainingTokens() public onlyOwner {
        _onexmmToken.transfer(ONEXMM, availableForSale());
        _endPresale();
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
        actualEndTime = block.timestamp;
    }

    /// @notice Used to send ETH to the contract
    /// @dev This method can be used by the owner to make sure there is
    /// enough ETH on the contract to execute operations
    receive() external payable {}

    function _endPresale() private {
        actualEndTime = block.timestamp;
    }
}