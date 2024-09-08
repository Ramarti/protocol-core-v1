/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import { ProtocolAdmin } from "contracts/lib/ProtocolAdmin.sol";
import { GroupNFT } from "contracts/GroupNFT.sol";
import { GroupingModule } from "contracts/modules/grouping/GroupingModule.sol";
import { IPAssetRegistry } from "contracts/registries/IPAssetRegistry.sol";
import { AccessController } from "contracts/access/AccessController.sol";
import { LicenseRegistry } from "contracts/registries/LicenseRegistry.sol";
import { LicenseToken } from "contracts/LicenseToken.sol";
import { IPGraphACL } from "contracts/access/IPGraphACL.sol";
import { RoyaltyPolicyLAP } from "contracts/modules/royalty/policies/LAP/RoyaltyPolicyLAP.sol";

// script
import { UpgradedImplHelper } from "../../utils/upgrades/UpgradedImplHelper.sol";
import { TestProxyHelper } from "test/foundry/utils/TestProxyHelper.sol";
import { BroadcastManager } from "../../utils/BroadcastManager.s.sol";
import { JsonDeploymentHandler } from "../../utils/JsonDeploymentHandler.s.sol";
import { StringUtil } from "../../utils/StringUtil.sol";
import { ICreate3Deployer } from "@create3-deployer/contracts/ICreate3Deployer.sol";

contract DeployerV1_2 is JsonDeploymentHandler, BroadcastManager, UpgradedImplHelper {
  
    address internal ERC6551_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    address internal CREATE3_DEPLOYER = 0x384a891dFDE8180b054f04D66379f16B7a678Ad6;
    uint256 internal CREATE3_DEFAULT_SEED = 0;
    // PROXY 1967 IMPLEMENTATION STORAGE SLOTS
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ICreate3Deployer internal immutable create3Deployer;

    string constant PREV_VERSION = "v1.1.1";
    string constant PROPOSAL_VERSION = "v1.2";

    AccessManager internal protocolAccessManager;
    AccessController internal accessController;
    IPAssetRegistry internal ipAssetRegistry;
    LicenseRegistry internal licenseRegistry;
    LicenseToken internal licenseToken;
    IPGraphACL internal ipGraphACL;
    RoyaltyPolicyLAP internal royaltyPolicyLAP;
    address licensingModule;
    address disputeModule;
    address royaltyModule;
    address ipAccountImpl;

    // Grouping
    GroupNFT internal groupNft;
    GroupingModule internal groupingModule;

    constructor() JsonDeploymentHandler("main") {
        create3Deployer = ICreate3Deployer(CREATE3_DEPLOYER);
    }

    function run() public virtual {
        _readDeployment(PREV_VERSION); // JsonDeploymentHandler.s.sol
        // Load existing contracts
        protocolAccessManager = AccessManager(_readAddress("ProtocolAccessManager"));
        licenseToken = LicenseToken(_readAddress("LicenseToken"));
        licensingModule = _readAddress("LicensingModule");
        licenseRegistry = LicenseRegistry(_readAddress("LicenseRegistry"));
        ipAssetRegistry = IPAssetRegistry(_readAddress("IPAssetRegistry"));
        accessController = AccessController(_readAddress("AccessController"));
        royaltyPolicyLAP = RoyaltyPolicyLAP(_readAddress("RoyaltyPolicyLAP"));
        disputeModule = _readAddress("DisputeModule");
        royaltyModule = _readAddress("RoyaltyModule");
        ipAccountImpl = _readAddress("IPAccountImpl");

        _beginBroadcast(); // BroadcastManager.s.sol
        
        UpgradeProposal[] memory proposals = deploy();
        _writeUpgradeProposals(PREV_VERSION, PROPOSAL_VERSION, proposals); // JsonDeploymentHandler.s.sol

        _endBroadcast(); // BroadcastManager.s.sol
    }

    function deploy() public returns (UpgradeProposal[] memory) {
        string memory contractKey;
        address impl;

        // Deploy new contracts

        contractKey = "GroupNFT";
        _predeploy(contractKey);
        impl = address(new GroupNFT( _getDeployedAddress(type(GroupingModule).name)));
        groupNft = GroupNFT(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(GroupNFT).name), // This salt adds PROPOSAL_VERSION to the salt
                impl,
                abi.encodeCall(
                    GroupNFT.initialize,
                    (
                        address(protocolAccessManager),
                        "https://github.com/storyprotocol/protocol-core/blob/main/assets/license-image.gif"
                    )
                )
            )
        );
        require(_getDeployedAddress(type(GroupNFT).name) == address(groupNft), "Deploy: GroupNFT Address Mismatch");
        require(_loadProxyImpl(address(groupNft)) == impl, "GroupNFT Proxy Implementation Mismatch");
        impl = address(0); // Make sure we don't deploy wrong impl
        _postdeploy(contractKey, address(groupNft));

        contractKey = "GroupingModule";
        _predeploy(contractKey);
        impl = address(
            new GroupingModule(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                _getDeployedAddress(type(LicenseToken).name),
                address(groupNft)
            )
        );
        groupingModule = GroupingModule(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(GroupingModule).name), // This salt adds PROPOSAL_VERSION to the salt
                impl,
                abi.encodeCall(GroupingModule.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(GroupingModule).name) == address(groupingModule),
            "Deploy: Grouping Module Address Mismatch"
        );
        require(_loadProxyImpl(address(groupingModule)) == impl, "Grouping Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy(contractKey, address(groupingModule));

        _predeploy("IPGraphACL");
        ipGraphACL = IPGraphACL(
            create3Deployer.deploy(
                _getSalt(type(IPGraphACL).name), // This salt adds PROPOSAL_VERSION to the salt
                abi.encodePacked(
                    type(IPGraphACL).creationCode,
                    abi.encode(address(protocolAccessManager))
                )
            )
        );
        _postdeploy("IPGraphACL", address(ipGraphACL));
        impl = address(0);


        // Deploy new implementations
        contractKey = "LicenseToken";
        _predeploy(contractKey);
        impl = address(new LicenseToken(licensingModule, disputeModule));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(licenseToken), newImpl: impl }));
       
        contractKey = "RoyaltyPolicyLAP";
        _predeploy(contractKey);
        impl = address(new RoyaltyPolicyLAP(royaltyModule, disputeModule, address(ipGraphACL)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyPolicyLAP), newImpl: impl }));

        contractKey = "IPAssetRegistry";
        _predeploy(contractKey);
        impl = address(
            new IPAssetRegistry(
                ERC6551_REGISTRY,
                ipAccountImpl,
                address(groupingModule)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(ipAssetRegistry), newImpl: impl }));
        //LicenseRegistry
        contractKey = "LicenseRegistry";
        _predeploy(contractKey);
        impl = address(
            new LicenseRegistry(
                licensingModule,
                disputeModule,
                address(ipGraphACL)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(licenseRegistry), newImpl: impl }));    

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

    function _getSalt(string memory name) private view returns (bytes32 salt) {
        salt = keccak256(abi.encode(name, PROPOSAL_VERSION));
    }
}
