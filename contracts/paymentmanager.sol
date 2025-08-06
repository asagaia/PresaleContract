// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MembersOnly } from "./membersonly.sol";
import { TokenPrice } from "../structures/token_price.sol";
import { TONTokenType } from "./enums.sol";

abstract contract PaymentManager is MembersOnly {
    /*************
     * Events    *
     *************/
    event TradeExecuted(address indexed to, address fromToken, uint256 fromAmount, uint256 amount1XMM);
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
        require(token != USDT &&
                token != USDC &&
                token != DAI,
                "E3");
        _;
    }

    /**************
     * Properties *
     **************/
    address public immutable ONEXMM;
    // The initial price of 1 XMM token in USD, with 4 digits precision (e.g., 500 for $0.05)
    uint32 public immutable Initial1XMMPrice_USD;

    address public immutable WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public immutable USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public immutable USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public immutable DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

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
        _authorizedTokens[WETH] = true; // WETH
        _authorizedTokens[USDT] = true; // USDT
        _authorizedTokens[USDC] = true; // USDC
        _authorizedTokens[DAI] = true; // DAI

        // We add the default prices
        uint64 precisionSq = PRECISION * PRECISION;
        uint64 usdTo1XMM = precisionSq / _initial1XMMPrice_USD;
        uint64 ethPrice = uint64(2_450) * precisionSq / _initial1XMMPrice_USD; // 1 ETH = $2,450

        _exchangePrices[WETH] = TokenPrice(ethPrice, 18); // WETH
        _exchangePrices[USDT] = TokenPrice(usdTo1XMM, 6); // USDT
        _exchangePrices[USDC] = TokenPrice(usdTo1XMM, 6); // USDC
        _exchangePrices[DAI] = TokenPrice(usdTo1XMM, 18); // DAI

        Initial1XMMPrice_USD = _initial1XMMPrice_USD;
        _authorizedTokensList.push(WETH); // WETH
        _authorizedTokensList.push(USDT); // USDT
        _authorizedTokensList.push(USDC); // USDC
        _authorizedTokensList.push(DAI); // DAI
    }

    /// @notice Returns the list of tokens authorized for payments.
    function authorizedTokens() external view returns (address[] memory) {
        return _authorizedTokensList;
    }

    /// @notice Adds a new authorized token to the contract.
    /// @param token The address of the token to authorize.
    /// @param decimals The number of decimals for the token.
    /// @param price The price of the token in USD, with 4 digits precision.
    function addAuthorizedToken(address token, uint8 decimals, uint64 price) external onlyOwner {
        require(!_authorizedTokens[token], "E2");

        _authorizedTokens[token] = true;
        _authorizedTokensList.push(token);
        _exchangePrices[token] = TokenPrice((price * PRECISION) / Initial1XMMPrice_USD, decimals);
    }

    /// @notice Gets the exchange price for a specific token.
    /// @dev The price is expressed as a conversion value to 1 XMM token, with 4digits precision
    /// @param token The address of the token to get the price for.
    /// @return The price of the token in relation to 1 XMM, with 4 digits precision; for 1 token, user gets `price` 1XMM tokens.
    function getPrice(address token) external view onlyAuthorizedToken(token) returns (uint64) {
        if (token == address(0)) {
            // If the token is ETH, we return the price for WETH
            token = WETH;
        }

        return _exchangePrices[token].price;
    }

    /// @notice Sets a new exchange price for a token.
    /// @param token The address of the token to set the price for.
    /// @param price The new price of the token, in USD.
    /// @dev The price is expressed in USD, with 4 digits precision
    function setPrice(address token, uint64 price) external onlyOwner notUSD(token) {
        _exchangePrices[token].price = (price * PRECISION) / Initial1XMMPrice_USD;
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
        // We make sure that no address 0 can be passed as arg
        if (token == address(0)) token = WETH;

        TokenPrice storage tokenPrice = _exchangePrices[token];
        uint256 onexmmAmount = amount * tokenPrice.price * (10 ** (18 - tokenPrice.decimals)); // Adjust for tokens' decimal
        onexmmAmount /= PRECISION; // Adjust for price precision

        return onexmmAmount;
    }

    function _getAmountOfTokenFor1XMM(address token, uint256 amount1XMM) internal view returns (uint256) {
        // We make sure that no address 0 can be passed as arg
        if (token == address(0)) token = WETH;

        TokenPrice storage tokenPrice = _exchangePrices[token];
        uint256 tokenAmount = amount1XMM * PRECISION / tokenPrice.price; // Adjust for price precision
        tokenAmount *= (10 ** (tokenPrice.decimals - 18)); // Adjust for tokens' decimal

        return tokenAmount;
    }
}