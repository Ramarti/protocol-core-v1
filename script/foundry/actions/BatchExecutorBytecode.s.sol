/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// external
import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
// script
import { BroadcastManager } from "../../../script/foundry/utils/BroadcastManager.s.sol";
import { JsonTxHandler } from "../../../script/foundry/utils/JsonTxHandler.s.sol";

import { BatchExecutor } from "../utils/BatchExecutor.sol";

contract BatchExecutorBytecode is Script, BroadcastManager, JsonTxHandler {
    using stdJson for string;

    constructor() JsonTxHandler() {}

    /// @dev To use, run the following command (e.g. for Sepolia):
    /// forge script script/foundry/deployment/Main.s.sol:Main --rpc-url $RPC_URL --broadcast --verify -vvvv

    function run() public {
        _beginBroadcast(); // BroadcastManager.s.sol

        address desiredOwner = address(0xB6288e57bf7406B35ab4F70Fd1135E907107e386);

        // Get the creation bytecode (including constructor)
        bytes memory creationBytecode = type(BatchExecutor).creationCode;

        // Encode the constructor arguments (owner address)
        bytes memory constructorArgs = abi.encode(desiredOwner);

        // Combine creation bytecode and encoded constructor arguments
        bytes memory fullBytecode = abi.encodePacked(creationBytecode, constructorArgs);

        // Print the full bytecode
        console2.logBytes(fullBytecode);

        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(fullBytecode, 0x20), mload(fullBytecode))
        }
        console2.log("Deployed at:", deployedAddress);

        // Verify the owner
        BatchExecutor deployedExecutor = BatchExecutor(deployedAddress);
        require(deployedExecutor.owner() == desiredOwner, "Owner mismatch");
        _writeTx(Transaction({
            to: address(0),
            value: 0,
            data: fullBytecode
        }));
        _writeTxsOutput("Deploy_Batch_Executor");
        _endBroadcast(); // BroadcastManager.s.sol
    }
}
