// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token1 is ERC20{
    uint256 private constant DECIMAL_MULTIPLIER = 10**18;
    constructor() ERC20("token1","t1") {}

    function mint(uint256 amount) external {
        _mint(msg.sender, amount * DECIMAL_MULTIPLIER);
    }
}