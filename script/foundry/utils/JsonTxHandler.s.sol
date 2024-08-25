// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";

import { StringUtil } from "../../../script/foundry/utils/StringUtil.sol";

contract JsonTxHandler is Script {
    using StringUtil for uint256;
    using stdJson for string;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
    }

    Transaction[] private transactions;
    string private chainId;

    constructor() {
        chainId = (block.chainid).toString();
    }

    function _writeTx(Transaction memory _tx) internal {
        transactions.push(_tx);
        console2.log("Added tx to ", _tx.to);
        console2.log("Value: ", _tx.value);
        console2.log("Data: ");
        console2.logBytes(_tx.data);
    }

    function _writeTx(address _to, uint256 _value, bytes memory _data) internal {
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data
        }));
        console2.log("Added tx to ", _to);
        console2.log("Value: ", _value);
        console2.log("Data: ");
        console2.logBytes(_data);
    }

    function _writeTxsOutput(string memory _action) internal {
        string memory json = "[";
        for (uint i = 0; i < transactions.length; i++) {
            if (i > 0 && i < transactions.length-1) {
                json = string(abi.encodePacked(json, ","));
            }
            json = string(abi.encodePacked(json, "{"));
            json = string(abi.encodePacked(json, '"to":"', vm.toString(transactions[i].to), '",'));
            json = string(abi.encodePacked(json, '"value":', vm.toString(transactions[i].value), ','));
            json = string(abi.encodePacked(json, '"data":"', vm.toString(transactions[i].data), '"'));
            json = string(abi.encodePacked(json, "}"));
        }
        json = string(abi.encodePacked(json, "]"));

        string memory filename = string(abi.encodePacked("./deploy-out/", _action, "-", chainId, ".json"));
        vm.writeFile(filename, json);
        console2.log("Wrote batch txs to ", filename);
    }
}