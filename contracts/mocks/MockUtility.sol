// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

contract MockUtility is MockToken {
    constructor(address initialOwner)
        MockToken("Mock Utility Token", "MUT", initialOwner)
    {}
} 