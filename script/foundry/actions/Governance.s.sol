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

contract GovernanceActions is Script, BroadcastManager, JsonTxHandler {
    using stdJson for string;

    constructor() JsonTxHandler() {}

    /// @dev To use, run the following command (e.g. for Sepolia):
    /// forge script script/foundry/deployment/Main.s.sol:Main --rpc-url $RPC_URL --broadcast --verify -vvvv

    function run() public {
        _beginBroadcast(); // BroadcastManager.s.sol

        _writeTx(Transaction({
            to: 0xB6288e57bf7406B35ab4F70Fd1135E907107e386,
            value: 1 ether,
            data: abi.encodePacked("Hello, World!")
        }));
        _writeTxsOutput("send");
        _endBroadcast(); // BroadcastManager.s.sol
    }

}
