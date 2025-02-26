// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GreetingService {
    string public lastGreeting;
    event Greeted(address indexed caller, string name);
    
    /// @notice Stores the greeting and emits an event.
    /// @param name The greeting message (typically the caller’s name).
    function greet(string calldata name) external {
        lastGreeting = name;
        emit Greeted(msg.sender, name);
    }
}


