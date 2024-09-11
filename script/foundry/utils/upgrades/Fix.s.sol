/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { AccessController } from "contracts/access/AccessController.sol";
import { ProtocolAdmin } from "contracts/lib/ProtocolAdmin.sol";
import { ProtocolPauseAdmin } from "contracts/pause/ProtocolPauseAdmin.sol";
import { ProtocolPausableUpgradeable } from "contracts/pause/ProtocolPausableUpgradeable.sol";

import { IVaultController } from "contracts/interfaces/modules/royalty/policies/IVaultController.sol";

// script
import { BroadcastManager } from "../BroadcastManager.s.sol";
import { JsonDeploymentHandler } from "../JsonDeploymentHandler.s.sol";
import { JsonBatchTxHelper } from "../JsonBatchTxHelper.s.sol";
import { StringUtil } from "../StringUtil.sol";
import { ICreate3Deployer } from "@create3-deployer/contracts/ICreate3Deployer.sol";
import { UpgradedImplHelper } from "./UpgradedImplHelper.sol";
import { StorageLayoutChecker } from "./StorageLayoutCheck.s.sol";

contract Fix is Script, BroadcastManager, JsonDeploymentHandler, JsonBatchTxHelper {

    address internal ERC6551_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    address internal CREATE3_DEPLOYER = 0x384a891dFDE8180b054f04D66379f16B7a678Ad6;
    uint256 internal CREATE3_DEFAULT_SEED = 0;
    // PROXY 1967 IMPLEMENTATION STORAGE SLOTS
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    enum UpgradeModes { SCHEDULE, EXECUTE }
    enum Output {
        TX_EXECUTION, // One Tx per schedule/execute
        BATCH_TX_EXECUTION, // Use AccessManager to batch txs (multicall)
        BATCH_TX_JSON // Prepare raw bytes for multisig. Multisig may batch txs (e.g. Gnosis Safe JSON input in tx builder)
    }

    ///////// USER INPUT /////////
    UpgradeModes mode;
    Output outputType;

    /////////////////////////////
    ICreate3Deployer internal immutable create3Deployer;
    AccessManager internal protocolAccessManager;
    ProtocolPauseAdmin internal protocolPauser;

    string fromVersion;
    string toVersion;

    bytes[] multicallData;

    constructor() JsonDeploymentHandler("main") JsonBatchTxHelper() {
        create3Deployer = ICreate3Deployer(CREATE3_DEPLOYER);
        fromVersion = "v1.1.1";
    }

    /// @dev To use, run the following command (e.g. for Sepolia):
    /// forge script script/foundry/deployment/Main.s.sol:Main --rpc-url $RPC_URL --broadcast --verify -vvvv

    function run() public virtual {
        _readDeployment(fromVersion); // JsonDeploymentHandler.s.sol
        protocolAccessManager = AccessManager(_readAddress("ProtocolAccessManager"));
        address royaltyPolicyLRP = 0x49852f326F81a867157b0D2379A85A62Cd4c6Ee0;
        address groupingModule = 0xeD1eF5749468B1805952757F53aB4C9037cD3ed6;
        protocolPauser = ProtocolPauseAdmin(_readAddress("ProtocolPauseAdmin"));
        console2.log("accessManager", address(protocolAccessManager));
        _beginBroadcast(); // BroadcastManager.s.sol

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;
        console2.logBytes4(selectors[0]);

        protocolPauser.addPausable(address(royaltyPolicyLRP));
        protocolPauser.addPausable(address(groupingModule));

        protocolAccessManager.setTargetFunctionRole(
            address(groupingModule),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );
        address groupNft = 0x38B4596C3866469d9979899b0E9dfB18573eD524;
        protocolAccessManager.setTargetFunctionRole(
            address(groupNft),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );

        selectors = new bytes4[](2);
        selectors[0] = ProtocolPausableUpgradeable.pause.selector;
        selectors[1] = ProtocolPausableUpgradeable.unpause.selector;
        protocolAccessManager.setTargetFunctionRole(
            address(royaltyPolicyLRP),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(groupingModule),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );

        _endBroadcast(); // BroadcastManager.s.sol
    }

}
