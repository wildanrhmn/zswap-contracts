// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

contract MockUSD is MockToken {
    constructor(address initialOwner)
        MockToken("Mock USD", "mUSD", initialOwner)
    {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
} 