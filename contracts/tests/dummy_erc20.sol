// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyERC20 is ERC20 {
    constructor() ERC20("dummy", "DUM") {
        // Mint 1 million tokens to the deployer
        _mint(msg.sender, 10_000_000 * 10 ** decimals());
    }
}