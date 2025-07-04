// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MembersOnly } from "./membersonly.sol";
import { TokenPrice } from "../structures/token_price.sol";
import { TONTokenType } from "./enums.sol";

import { console } from "hardhat/console.sol";

abstract contract PaymentManager is MembersOnly {
    /*************
     * Events    *
     *************/
    event TradeExecuted(address indexed to, address fromToken, uint256 fromAmount, uint256 amount1XMM);
    event TradeFailed(address indexed to, address fromToken, uint256 fromAmount, uint256 amount1XMM);
    event FailedTradeNotReverted(address indexed to, address fromToken, uint256 fromAmount, uint256 amount1XMM);
    event TONTradeExecuted(address indexed to, TONTokenType fromToken, uint256 fromAmount, uint256 amount1XMM);
    event TONTradeFailed(address indexed to, TONTokenType fromToken, uint256 fromAmount, uint256 amount1XMM);

    /*************
     * Modifiers *
     *************/
    modifier onlyAuthorizedToken(address token) {
        require(token == address(0) || _authorizedTokens[token], "E1");
        _;
    }

    modifier notUSD(address token) {
        require(token != address(0xdAC17F958D2ee523a2206206994597C13D831ec7) && // USDT
                token != address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) && // USDC
                token != address(0x6B175474E89094C44Da98b954EedeAC495271d0F), // DAI
                "E3");
        _;
    }

    /**************
     * Properties *
     **************/
    address public immutable ONEXMM;
    // The initial price of 1 XMM token in USD, with 4 digits precision (e.g., 500 for $0.05)
    uint32 public immutable Initial1XMMPrice_USD;

    /******************
     * Private Fields *
     ******************/
    IERC20 internal immutable _onexmmToken;
    uint32 constant private PRECISION = 10_000; // 4 digits precision (0.0001)
    address[] private _authorizedTokensList; // List of authorized tokens for easier iteration

    mapping(address token => bool isAuthorized) private _authorizedTokens;
    // Prices are expressed with 4 digits precision (0.0001)
    // The price is expressed as a conversion value to 1XMM token
    mapping(address token => TokenPrice) private _exchangePrices;

    /// @dev The contract constructor
    /// @param _initial1XMMPrice_USD The initial price of 1 XMM token in USD, with 4 digits precision (e.g., 500 for $0.05, or 5 US cents))
    constructor(address _1xmmAddress, uint32 _initial1XMMPrice_USD) MembersOnly() {
        ONEXMM = _1xmmAddress;
        _onexmmToken = IERC20(_1xmmAddress);

        // We add the default authorized tokens
        _authorizedTokens[address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)] = true; // WETH
        _authorizedTokens[address(0xdAC17F958D2ee523a2206206994597C13D831ec7)] = true; // USDT
        _authorizedTokens[address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)] = true; // USDC
        _authorizedTokens[address(0x6B175474E89094C44Da98b954EedeAC495271d0F)] = true; // DAI

        // We add the default prices
        uint32 precisionSq = PRECISION * PRECISION;
        uint32 usdTo1XMM = precisionSq / _initial1XMMPrice_USD;
        uint32 ethPrice = uint32(uint64(2_450) * precisionSq / _initial1XMMPrice_USD); // 1 ETH = $2,450

        _exchangePrices[address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)] = TokenPrice(ethPrice, 18); // WETH
        _exchangePrices[address(0xdAC17F958D2ee523a2206206994597C13D831ec7)] = TokenPrice(usdTo1XMM, 6); // USDT
        _exchangePrices[address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)] = TokenPrice(usdTo1XMM, 6); // USDC
        _exchangePrices[address(0x6B175474E89094C44Da98b954EedeAC495271d0F)] = TokenPrice(usdTo1XMM, 18); // DAI

        Initial1XMMPrice_USD = _initial1XMMPrice_USD;
        _authorizedTokensList.push(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)); // WETH
        _authorizedTokensList.push(address(0xdAC17F958D2ee523a2206206994597C13D831ec7)); // USDT
        _authorizedTokensList.push(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)); // USDC
        _authorizedTokensList.push(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)); // DAI
    }

    /// @notice Returns the list of tokens authorized for payments.
    function authorizedTokens() external view returns (address[] memory) {
        return _authorizedTokensList;
    }

    /// @notice Adds a new authorized token to the contract.
    /// @param token The address of the token to authorize.
    /// @param decimals The number of decimals for the token.
    /// @param price The price of the token in USD, with 4 digits precision.
    function addAuthorizedToken(address token, uint8 decimals, uint32 price) external onlyOwner {
        require(!_authorizedTokens[token], "E2");

        _authorizedTokens[token] = true;
        _authorizedTokensList.push(token);
        _exchangePrices[token] = TokenPrice((uint64(price) * PRECISION) / Initial1XMMPrice_USD, decimals);
    }

    /// @notice Gets the exchange price for a specific token.
    /// @dev The price is expressed as a conversion value to 1 XMM token, with 4digits precision
    /// @param token The address of the token to get the price for.
    /// @return The price of the token in relation to 1 XMM, with 4 digits precision; for 1 token, user gets `price` 1XMM tokens.
    function getPrice(address token) external view onlyAuthorizedToken(token) returns (uint64) {
        if (token == address(0)) {
            // If the token is ETH, we return the price for WETH
            token = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        }

        return _exchangePrices[token].price;
    }

    /// @notice Sets a new exchange price for a token.
    /// @param token The address of the token to set the price for.
    /// @param price The new price of the token, in USD.
    /// @dev The price is expressed in USD, with 4 digits precision
    function setPrice(address token, uint32 price) external onlyOwner notUSD(token) {
        _exchangePrices[token].price = (uint64(price) * PRECISION) / Initial1XMMPrice_USD;
    }

    /********************************
     * Internal and Private Methods *
     ********************************/
    function _availableForSale() internal view returns (uint256) {
        return _onexmmToken.balanceOf(address(this));
    }

    function _transfer(address to, uint256 amount1XMM) internal returns(bool) {
        return _onexmmToken.transfer(to, amount1XMM);
    }

    function _getAmountOf1XMMForToken(address token, uint256 amount) internal view returns (uint256) {
        TokenPrice storage tokenPrice = _exchangePrices[token];
        uint256 onexmmAmount = amount * tokenPrice.price * (10 ** (18 - tokenPrice.decimals)); // Adjust for tokens' decimal
        onexmmAmount /= PRECISION; // Adjust for price precision

        return onexmmAmount;
    }

    function _getAmountOfTokenFor1XMM(address token, uint256 amount1XMM) internal view returns (uint256) {
        TokenPrice storage tokenPrice = _exchangePrices[token];
        uint256 tokenAmount = amount1XMM * PRECISION / tokenPrice.price; // Adjust for price precision
        tokenAmount *= (10 ** (tokenPrice.decimals - 18)); // Adjust for tokens' decimal

        return tokenAmount;
    }
}