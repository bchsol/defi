// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFT is ERC721{
    uint public id;

    constructor() ERC721("NFT","N") {}

    function mint() public {
        id++;
        _mint(msg.sender,id);
    }
}