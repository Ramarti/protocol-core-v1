/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import { ProtocolAdmin } from "contracts/lib/ProtocolAdmin.sol";

import { RoyaltyModule } from "contracts/modules/royalty/RoyaltyModule.sol";

// script
import { UpgradedImplHelper } from "../../utils/upgrades/UpgradedImplHelper.sol";
import { TestProxyHelper } from "test/foundry/utils/TestProxyHelper.sol";
import { BroadcastManager } from "../../utils/BroadcastManager.s.sol";
import { JsonDeploymentHandler } from "../../utils/JsonDeploymentHandler.s.sol";
import { StringUtil } from "../../utils/StringUtil.sol";
import { ICreate3Deployer } from "@create3-deployer/contracts/ICreate3Deployer.sol";
import { StorageLayoutChecker } from "../../utils/upgrades/StorageLayoutCheck.s.sol";

contract DeployerV1_2 is JsonDeploymentHandler, BroadcastManager, UpgradedImplHelper, StorageLayoutChecker {
    address internal ERC6551_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    address internal CREATE3_DEPLOYER = 0x384a891dFDE8180b054f04D66379f16B7a678Ad6;
    uint256 internal CREATE3_DEFAULT_SEED = 0;
    // PROXY 1967 IMPLEMENTATION STORAGE SLOTS
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ICreate3Deployer internal immutable create3Deployer;
    uint256 internal create3SaltSeed = CREATE3_DEFAULT_SEED;

    string constant PREV_VERSION = "v1.2.1";
    string constant PROPOSAL_VERSION = "v1.2.2";

    address licensingModule;
    address disputeModule;
    address licenseRegistry;
    address ipAssetRegistry;
    address royaltyModule;

    constructor() JsonDeploymentHandler("main") {
        create3Deployer = ICreate3Deployer(CREATE3_DEPLOYER);
    }

    function run() public virtual override {
        // super.run();
        _readDeployment(PREV_VERSION); // JsonDeploymentHandler.s.sol
        // Load existing contracts
        licensingModule = _readAddress("LicensingModule");
        licenseRegistry = _readAddress("LicenseRegistry");
        ipAssetRegistry = _readAddress("IPAssetRegistry");
        disputeModule = _readAddress("DisputeModule");
        royaltyModule = _readAddress("RoyaltyModule");
       
        _beginBroadcast(); // BroadcastManager.s.sol

        UpgradeProposal[] memory proposals = deploy();
        _writeUpgradeProposals(PREV_VERSION, PROPOSAL_VERSION, proposals); // JsonDeploymentHandler.s.sol

        _endBroadcast(); // BroadcastManager.s.sol
    }

    function deploy() public returns (UpgradeProposal[] memory) {
        string memory contractKey;
        address impl;

        // Deploy new contracts
        contractKey = "RoyaltyModule";
        _predeploy(contractKey);
        impl = address(
            new RoyaltyModule(
                address(licensingModule),
                address(disputeModule),
                address(licenseRegistry),
                address(ipAssetRegistry)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyModule), newImpl: impl }));
        impl = address(0);

        _logUpgradeProposals();
        
        return upgradeProposals;
    }

    function _predeploy(string memory contractKey) private view {
        console2.log(string.concat("Deploying ", contractKey, "..."));
    }

    function _postdeploy(string memory contractKey, address newAddress) private {
        _writeAddress(contractKey, newAddress);
        console2.log(string.concat(contractKey, " deployed to:"), newAddress);
    }

    function _getDeployedAddress(string memory name) private view returns (address) {
        return create3Deployer.getDeployed(_getSalt(name));
    }

    /// @dev Load the implementation address from the proxy contract
    function _loadProxyImpl(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    /// @dev get the salt for the contract deployment with CREATE3
    function _getSalt(string memory name) private view returns (bytes32 salt) {
        salt = keccak256(abi.encode(name, PROPOSAL_VERSION));
    }
}