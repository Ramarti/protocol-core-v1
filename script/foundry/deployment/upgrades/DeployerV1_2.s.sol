/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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
import { PILicenseTemplate } from "contracts/modules/licensing/PILicenseTemplate.sol";
import { RoyaltyPolicyLAP } from "contracts/modules/royalty/policies/LAP/RoyaltyPolicyLAP.sol";
import { RoyaltyPolicyLRP } from "contracts/modules/royalty/policies/LRP/RoyaltyPolicyLRP.sol";
import { IpRoyaltyVault } from "contracts/modules/royalty/policies/IpRoyaltyVault.sol";
import { RoyaltyModule } from "contracts/modules/royalty/RoyaltyModule.sol";

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
    uint256 internal create3SaltSeed = CREATE3_DEFAULT_SEED;

    string constant PREV_VERSION = "v1.1.1";
    string constant PROPOSAL_VERSION = "v1.2.0";

    AccessManager internal protocolAccessManager;
    AccessController internal accessController;
    IPAssetRegistry internal ipAssetRegistry;
    LicenseRegistry internal licenseRegistry;
    LicenseToken internal licenseToken;
    RoyaltyPolicyLAP internal royaltyPolicyLAP;
    RoyaltyPolicyLRP internal royaltyPolicyLRP;
    // Grouping
    GroupNFT internal groupNft;
    GroupingModule internal groupingModule;
    address licensingModule;
    address disputeModule;
    address royaltyModule;
    address ipAccountImpl;
    address ipGraphACL;
    address piLicenseTemplate;

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
        piLicenseTemplate = _readAddress("PILicenseTemplate");
        ipGraphACL = _readAddress("IPGraphACL");
        groupingModule = GroupingModule(_readAddress("GroupingModule"));
        groupNft = GroupNFT(_readAddress("GroupNFT"));
        royaltyPolicyLRP = RoyaltyPolicyLRP(_readAddress("RoyaltyPolicyLRP"));

        _beginBroadcast(); // BroadcastManager.s.sol

        UpgradeProposal[] memory proposals = deploy();
        _writeUpgradeProposals(PREV_VERSION, PROPOSAL_VERSION, proposals); // JsonDeploymentHandler.s.sol

        _endBroadcast(); // BroadcastManager.s.sol
    }

    function deploy() public returns (UpgradeProposal[] memory) {
        string memory contractKey;
        address impl;

        // Deploy new contracts
        /* Deployed before rebase
        _predeploy("RoyaltyPolicyLRP");
        impl = address(new RoyaltyPolicyLRP(address(royaltyModule)));
        royaltyPolicyLRP = RoyaltyPolicyLRP(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(RoyaltyPolicyLRP).name),
                impl,
                abi.encodeCall(RoyaltyPolicyLRP.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(RoyaltyPolicyLRP).name) == address(royaltyPolicyLRP),
            "Deploy: Royalty Policy Address Mismatch"
        );
        require(_loadProxyImpl(address(royaltyPolicyLRP)) == impl, "RoyaltyPolicyLRP Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy("RoyaltyPolicyLRP", address(royaltyPolicyLRP));
        */

        /* Deployed before rebase
        contractKey = "GroupingModule";
        _predeploy(contractKey);
        impl = address(
            new GroupingModule(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                address(licenseToken),
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
        */

        /* Deployed manually
        contractKey = "GroupNFT";
        _predeploy(contractKey);
        impl = address(new GroupNFT(address(groupingModule)));
        console2.log("GroupNFT impl:", impl);
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
        */
        /*
        // Deploy new implementations
        contractKey = "GroupingModule";
        _predeploy(contractKey);
        impl = address(
            new GroupingModule(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                address(licenseToken),
                address(groupNft)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(groupingModule), newImpl: impl }));
        impl = address(0);

        contractKey = "LicenseToken";
        _predeploy(contractKey);
        impl = address(new LicenseToken(licensingModule, disputeModule));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(licenseToken), newImpl: impl }));
        impl = address(0);

        contractKey = "IPAssetRegistry";
        _predeploy(contractKey);
        impl = address(new IPAssetRegistry(ERC6551_REGISTRY, ipAccountImpl, address(groupingModule)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(ipAssetRegistry), newImpl: impl }));
        impl = address(0);

        contractKey = "LicenseRegistry";
        _predeploy(contractKey);
        impl = address(new LicenseRegistry(licensingModule, disputeModule, address(ipGraphACL)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(licenseRegistry), newImpl: impl }));
        impl = address(0);

        contractKey = "PILicenseTemplate";
        _predeploy(contractKey);
        impl = address(
            new PILicenseTemplate(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                address(royaltyModule)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(piLicenseTemplate), newImpl: impl }));
        impl = address(0);
        */
        contractKey = "RoyaltyPolicyLAP";
        _predeploy(contractKey);
        impl = address(new RoyaltyPolicyLAP(royaltyModule, disputeModule, address(ipGraphACL)));
        console2.log("RoyaltyPolicyLAP impl:", impl);
        //upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyPolicyLAP), newImpl: impl }));
        impl = address(0);
        /*
        contractKey = "RoyaltyPolicyLRP";
        _predeploy(contractKey);
        impl = address(new RoyaltyPolicyLRP(address(royaltyModule)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyPolicyLRP), newImpl: impl }));
        impl = address(0);

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

        contractKey = "IpRoyaltyVault";
        _predeploy(contractKey);
        impl = address(new IpRoyaltyVault(disputeModule, royaltyModule));
        // In this case, "proxy" is the royaltyModule, since it can upgrade the vaults
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyModule), newImpl: impl }));
        impl = address(0);
        */
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
