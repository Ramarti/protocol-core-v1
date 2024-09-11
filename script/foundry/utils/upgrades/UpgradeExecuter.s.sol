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
    enum UpgradeModes { SCHEDULE, EXECUTE, CANCEL }
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

    modifier onlyMatchingAccessManager(address proxy) {
        require(
            AccessManaged(proxy).authority() == address(accessManager),
            "Proxy's Authority must equal accessManager"
        );
        _;
    }

    modifier onlyUpgraderRole() {
        (bool isMember, ) = accessManager.hasRole(ProtocolAdmin.UPGRADER_ROLE, deployer);
        require(isMember, "Caller must have Upgrader role");
        _;
    }

    modifier onlyScheduled(UpgradedImplHelper.UpgradeProposal memory p) {
        (bool immediate, uint32 delay) = accessManager.canCall(
            deployer,
            p.proxy,
            UUPSUpgradeable.upgradeToAndCall.selector
        );
        console2.log("Can call upgradeToAndCall");
        console2.log("Immediate", immediate);
        console2.log("Delay", delay);

        require(delay > 0, "Cannot schedule upgradeToAndCall");
        _;
    }

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
        } else if (mode == UpgradeModes.EXECUTE) {
            _executeUpgrades();
        } else if (mode == UpgradeModes.CANCEL) {
            _cancelScheduledUpgrades();
        }
        if (outputType == Output.BATCH_TX_JSON) {
            string memory action;
            if (mode == UpgradeModes.SCHEDULE) {
                action = "schedule";
            } else if (mode == UpgradeModes.EXECUTE) {
                action = "execute";
            } else if (mode  == UpgradeModes.CANCEL) {
                action = "cancel";
            } else {
                revert("Invalid mode");
            }
            _writeBatchTxsOutput(
                string.concat(
                    action, "-", fromVersion, "-to-", toVersion
                )
            ); // JsonBatchTxHelper.s.sol
        } else if (outputType == Output.BATCH_TX_EXECUTION) {
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
        _scheduleUpgrade(key, p);
        console2.log("--------------------");
    }

    function _scheduleUpgrade(string memory key, UpgradedImplHelper.UpgradeProposal memory p) private onlyMatchingAccessManager(p.proxy) onlyUpgraderRole() {
        bytes memory data = _getExecutionData(key, p);
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
            revert("Unsupported mode");
        }
    }

    function _executeUpgrades() internal virtual;

    function _executeUpgrade(string memory key) internal {
        UpgradedImplHelper.UpgradeProposal memory p = _readUpgradeProposal(key);

        console2.log("Upgrading", key);
        console2.log("Proxy", p.proxy);
        console2.log("New Impl", p.newImpl);
        _executeUpgrade(key, p);
    }

    function _executeUpgrade(string memory key, UpgradedImplHelper.UpgradeProposal memory p) private onlyMatchingAccessManager(p.proxy) {
        bytes memory data = _getExecutionData(key, p);
        (uint48 schedule) = accessManager.getSchedule(accessManager.hashOperation(deployer, p.proxy, data));
        console2.log("schedule", schedule);
        console2.log("Execute scheduled tx");
        console2.logBytes(data);
    
        if (outputType == Output.TX_EXECUTION) {
            console2.log("Execute upgrade tx");
            // We don't currently support reinitializer calls
            accessManager.execute(
                p.proxy,
                data
            );
        } else if (outputType == Output.BATCH_TX_EXECUTION) {
            console2.log("Adding execution tx to batch");
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

    function _cancelScheduledUpgrades() internal virtual;

    function _cancelScheduledUpgrade(string memory key) internal {
        console2.log("--------------------");
        UpgradedImplHelper.UpgradeProposal memory p = _readUpgradeProposal(key);
        console2.log("Scheduling", key);
        console2.log("Proxy", p.proxy);
        console2.log("New Impl", p.newImpl);
        _cancelScheduledUpgrade(key, p);
        console2.log("--------------------");
    }

    function _cancelScheduledUpgrade(string memory key, UpgradedImplHelper.UpgradeProposal memory p) private onlyMatchingAccessManager(p.proxy) {
        bytes memory data = _getExecutionData(key, p);
        if (data.length == 0) {
            revert("No data to schedule");
        }
        if (outputType == Output.TX_EXECUTION) {
            console2.log("Execute cancelation");
            console2.logBytes(data);
            (uint32 nonce) = accessManager.cancel(deployer, p.proxy, data);
            console2.log("Cancelled", nonce);
        } else if (outputType == Output.BATCH_TX_EXECUTION) {
            console2.log("Adding cancel tx to batch");
            multicallData.push(abi.encodeCall(AccessManager.cancel, (deployer, p.proxy, data)));
            console2.logBytes(multicallData[multicallData.length - 1]);
        } else if (outputType == Output.BATCH_TX_JSON) {
            console2.log("------------ WARNING: NOT TESTED ------------");
            _writeTx(
                address(accessManager),
                0,
                abi.encodeCall(AccessManager.cancel, (deployer, p.proxy, data))
            );
        } else {
            revert("Unsupported mode");
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

    function _getExecutionData(string memory key, UpgradedImplHelper.UpgradeProposal memory p) internal returns(bytes memory data) {
        if (keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked("IpRoyaltyVault"))) {
            console2.log("Schedule upgradeVaults");
            data = abi.encodeCall(
                IVaultController.upgradeVaults, (p.newImpl)
            );
        } else {            
            console2.log("Schedule upgradeUUPS");
            data = abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (p.newImpl, "")
            );
        }
        return data;
    }
}
