// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @title BatchExecutor
/// @author PIP Labs
/// @notice A contract that allows for batch delegate call execution of transactions
contract BatchExecutor is Ownable {

    constructor(address owner) Ownable(owner) {}

    /// @notice Execute a batch of transactions
    /// @param targets The addresses of the contracts to call
    /// @param data The data to send to each contract
    /// @return results The results of each call
    function batchExecute(address[] calldata targets, bytes[] calldata data) external onlyOwner returns(bytes[] memory results) {
        require(targets.length == data.length, "Mismatched array lengths");
        
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(targets[i], data[i]);
        }
    }
}