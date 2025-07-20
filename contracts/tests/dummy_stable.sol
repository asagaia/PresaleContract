// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyStable is ERC20 {
    constructor() ERC20("dummy", "DUM") {
        // Mint 1 million tokens to the deployer
        _mint(msg.sender, 10_000_000 * 10 ** decimals());
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }
}