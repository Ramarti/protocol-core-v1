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

import { IVaultController } from "contracts/interfaces/modules/royalty/policies/IVaultController.sol";

// script
import { BroadcastManager } from "../BroadcastManager.s.sol";
import { JsonDeploymentHandler } from "../JsonDeploymentHandler.s.sol";
import { JsonBatchTxHelper } from "../JsonBatchTxHelper.s.sol";
import { StringUtil } from "../StringUtil.sol";
import { ICreate3Deployer } from "@create3-deployer/contracts/ICreate3Deployer.sol";
import { UpgradedImplHelper } from "./UpgradedImplHelper.sol";
import { StorageLayoutChecker } from "./StorageLayoutCheck.s.sol";

abstract contract UpgradeExecuter is Script, BroadcastManager, JsonDeploymentHandler, JsonBatchTxHelper {

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
    AccessManager internal accessManager;

    string fromVersion;
    string toVersion;

    bytes[] multicallData;

    constructor(string memory _fromVersion, string memory _toVersion, UpgradeModes _mode, Output _outputType) JsonDeploymentHandler("main") JsonBatchTxHelper() {
        create3Deployer = ICreate3Deployer(CREATE3_DEPLOYER);
        fromVersion = _fromVersion;
        toVersion = _toVersion;
        mode = _mode;
        outputType = _outputType;
    }

    /// @dev To use, run the following command (e.g. for Sepolia):
    /// forge script script/foundry/deployment/Main.s.sol:Main --rpc-url $RPC_URL --broadcast --verify -vvvv

    function run() public virtual {
        _readDeployment(fromVersion); // JsonDeploymentHandler.s.sol
        accessManager = AccessManager(_readAddress("ProtocolAccessManager"));
        console2.log("accessManager", address(accessManager));
        _readProposalFile(fromVersion, toVersion); // JsonDeploymentHandler.s.sol
        _beginBroadcast(); // BroadcastManager.s.sol
        if (outputType == Output.BATCH_TX_JSON) {
            console2.log(multisig);
            deployer = multisig;
            console2.log("Generating tx json...");
        }
        if (mode == UpgradeModes.SCHEDULE) {
            _scheduleUpgrades();
        } else {
            _executeUpgrades();
        }
        if (outputType == Output.BATCH_TX_JSON) {
            string memory action;
            if (mode == UpgradeModes.SCHEDULE) {
                action = "schedule";
            } else if (mode == UpgradeModes.EXECUTE) {
                action = "execute";
            } else {
                revert("Invalid mode");
            }
            _writeBatchTxsOutput(
                string.concat(
                    action, "-", fromVersion, "-to-", toVersion
                )
            ); // JsonBatchTxHelper.s.sol
        }
        if (outputType == Output.BATCH_TX_EXECUTION) {
            _executeBatchTxs();
        }
        _endBroadcast(); // BroadcastManager.s.sol
    }

    function _scheduleUpgrades() internal virtual;


    function _scheduleUpgrade(string memory key) internal {
        console2.log("--------------------");
        UpgradedImplHelper.UpgradeProposal memory p = _readUpgradeProposal(key);
        console2.log("Scheduling", key);
        console2.log("Proxy", p.proxy);
        console2.log("New Impl", p.newImpl);
        bytes memory data;
        // IF the key is IpRoyaltyVault, we need to schedule upgradeVaults
        if (keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked("IpRoyaltyVault"))) {
            console2.log("Schedule upgradeVaults");
            data = abi.encodeCall(
                IVaultController.upgradeVaults, (p.newImpl)
            );
        } else {
            // IF the key is something else, we need to schedule upgradeToAndCall
            console2.log("Deployer", deployer);
            (bool isMember, ) = accessManager.hasRole(ProtocolAdmin.UPGRADER_ROLE, deployer);
            console2.log("Has Role Upgrader", isMember);

            console2.log(
                "Authority equals accessManager?",
                AccessManaged(p.proxy).authority(),
                address(accessManager),
                AccessManaged(p.proxy).authority() == address(accessManager)
            );


            (bool immediate, uint32 delay) = accessManager.canCall(
                deployer,
                p.proxy,
                UUPSUpgradeable.upgradeToAndCall.selector
            );
            console2.log("Can call upgradeToAndCall");
            console2.log("Immediate", immediate);
            console2.log("Delay", delay);

            if (delay == 0) {
                revert("Cannot schedule upgradeToAndCall");
            }
            console2.log("Schedule upgradeUUPS");
            data = abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (p.newImpl, "")
            );

        }
        if (data.length == 0) {
            revert("No data to schedule");
        }
        if (outputType == Output.TX_EXECUTION) {
            console2.log("Schedule tx execution");
            console2.logBytes(data);

            (bytes32 operationId, uint32 nonce) = accessManager.schedule(
                p.proxy, // target
                data,
                0// when
            );
            console2.log("Scheduled", nonce);
            console2.log("OperationId");
            console2.logBytes32(operationId);
        } else if (outputType == Output.BATCH_TX_EXECUTION) {
            console2.log("Adding tx to batch");
            multicallData.push(abi.encodeCall(AccessManager.schedule, (p.proxy, data, 0)));
            console2.logBytes(multicallData[multicallData.length - 1]);
        } else if (outputType == Output.BATCH_TX_JSON) {
            console2.log("------------ WARNING: NOT TESTED ------------");
            _writeTx(
                address(accessManager),
                0,
                abi.encodeCall(AccessManager.execute, (p.proxy, data))
            );
        } else {
            _writeTx(address(accessManager), 0, abi.encodeCall(AccessManager.schedule, (p.proxy, data, 0)));
        }
        console2.log("--------------------");
    }

    function _executeUpgrades() internal virtual;

    function _executeUpgrade(string memory key) internal {
        UpgradedImplHelper.UpgradeProposal memory p = _readUpgradeProposal(key);

        console2.log("Upgrading", key);
        console2.log("Proxy", p.proxy);
        console2.log("New Impl", p.newImpl);

        bytes memory data;
        if (keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked("IpRoyaltyVault"))) {
            console2.log("Execute upgradeVaults");
            data = abi.encodeCall(
                IVaultController.upgradeVaults, (p.newImpl)
            );
        } else {
            console2.log("Execute upgradeToAndCall");
            data = abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (p.newImpl, "")
            );
        }
        (uint48 schedule) = accessManager.getSchedule(accessManager.hashOperation(deployer, p.proxy, data));
        console2.log("schedule", schedule);
        console2.log("Execute scheduled tx");
        console2.logBytes(data);
    
        if (outputType == Output.TX_EXECUTION) {
            console2.log("Executed tx");
            // In this version, we don't have initializer calls. In other versions, we might need to store the bytes in JsonDeploymentHandler
            accessManager.execute(
                p.proxy,
                data
            );
        } else if (outputType == Output.BATCH_TX_EXECUTION) {
            console2.log("Adding tx to batch");
            multicallData.push(abi.encodeCall(AccessManager.execute, (p.proxy, data)));
            console2.logBytes(multicallData[multicallData.length - 1]);
        } else if (outputType == Output.BATCH_TX_JSON) {
            _writeTx(
                address(accessManager),
                0,
                abi.encodeCall(AccessManager.execute, (p.proxy, data))
            );
        } else {
            revert("Invalid output type");
        }
    }

    function _executeBatchTxs() internal {
        console2.log("Executing batch txs...");
        console2.log("Access Manager", address(accessManager));
        bytes[] memory results = accessManager.multicall(multicallData);
        console2.log("Results");
        for (uint256 i = 0; i < results.length; i++) {
            console2.log(i, ": ");
            console2.logBytes(results[i]);
        }
    }


    /// @dev get the salt for the contract deployment with CREATE3
    function _getSalt(string memory name) private view returns (bytes32 salt) {
        salt = keccak256(abi.encode(name, CREATE3_DEFAULT_SEED));
    }

    /// @dev Get the deterministic deployed address of a contract with CREATE3
    function _getDeployedAddress(string memory name) private view returns (address) {
        return create3Deployer.getDeployed(_getSalt(name));
    }

    /// @dev Load the implementation address from the proxy contract
    function _loadProxyImpl(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}