/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import { ProtocolAdmin } from "contracts/lib/ProtocolAdmin.sol";

import { AccessController } from "contracts/access/AccessController.sol";
import { IPAccountImpl } from "contracts/IPAccountImpl.sol";
import { IPAssetRegistry } from "contracts/registries/IPAssetRegistry.sol";
import { ModuleRegistry } from "contracts/registries/ModuleRegistry.sol";
import { LicenseRegistry } from "contracts/registries/LicenseRegistry.sol";
import { LicensingModule } from "contracts/modules/licensing/LicensingModule.sol";
import { RoyaltyModule } from "contracts/modules/royalty/RoyaltyModule.sol";
import { RoyaltyPolicyLAP } from "contracts/modules/royalty/policies/RoyaltyPolicyLAP.sol";
import { DisputeModule } from "contracts/modules/dispute/DisputeModule.sol";
import { ArbitrationPolicySP } from "contracts/modules/dispute/policies/ArbitrationPolicySP.sol";
import { TokenWithdrawalModule } from "contracts/modules/external/TokenWithdrawalModule.sol";
import { MODULE_TYPE_HOOK } from "contracts/lib/modules/Module.sol";
import { IModule } from "contracts/interfaces/modules/base/IModule.sol";
import { IHookModule } from "contracts/interfaces/modules/base/IHookModule.sol";
import { IpRoyaltyVault } from "contracts/modules/royalty/policies/IpRoyaltyVault.sol";
import { CoreMetadataModule } from "contracts/modules/metadata/CoreMetadataModule.sol";
import { PILicenseTemplate, PILTerms } from "contracts/modules/licensing/PILicenseTemplate.sol";
import { LicenseToken } from "contracts/LicenseToken.sol";

// script
import { BroadcastManager } from "../../utils/BroadcastManager.s.sol";
import { StorageLayoutChecker } from "../../utils/upgrades/StorageLayoutCheck.s.sol";
import { JsonDeploymentHandler } from "../../utils/JsonDeploymentHandler.s.sol";
import { StringUtil } from "../../utils/StringUtil.sol";
import { ICreate3Deployer } from "@create3-deployer/contracts/ICreate3Deployer.sol";
import { UpgradedImplHelper } from "../../utils/upgrades/UpgradedImplHelper.sol";

contract ImplDeployerV1_1_0 is StorageLayoutChecker, UpgradedImplHelper {
    struct ProxiesToUpgrade {
        address licenseToken;
        address licensingModule;
        address licenseRegistry;
        address piLicenseTemplate;
        address accessController;
        address royaltyModule;
        address royaltyPolicyLAP;
        address ipAssetRegistry;
    }

    struct Dependencies {
        address disputeModule;
        address moduleRegistry;
    }

    ProxiesToUpgrade internal proxies;
    Dependencies internal dependencies;
    uint256 internal create3SaltSeed;
    address erc6551Registry;

    function deploy(
        ICreate3Deployer create3Deployer,
        uint256 _create3SaltSeed,
        address _erc6551Registry,
        ProxiesToUpgrade memory _proxies,
        Dependencies memory _dependencies
    ) public returns (UpgradeProposal[] memory) {
        create3SaltSeed = _create3SaltSeed;
        proxies = _proxies;
        dependencies = _dependencies;
        erc6551Registry = _erc6551Registry;
        //_validate(); // StorageLayoutChecker.s.sol
        string memory contractKey;
        address impl;

        // - LicenseToken
        contractKey = "LicenseToken";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(LicenseToken).name, "implementation")),
            abi.encodePacked(
                type(LicenseToken).creationCode,
                abi.encode(proxies.licensingModule, dependencies.disputeModule)
            )
        );
        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.licenseToken,
                newImpl: impl
            })
        );

        // - LicensingModule
        contractKey = "LicensingModule";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(LicensingModule).name, "implementation")),
            abi.encodePacked(
                type(LicensingModule).creationCode,
                abi.encode(
                    proxies.accessController,
                    proxies.ipAssetRegistry,
                    dependencies.moduleRegistry,
                    proxies.royaltyModule,
                    proxies.licenseRegistry,
                    dependencies.disputeModule,
                    proxies.licenseToken
                )
            )
        );

        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.licensingModule,
                newImpl: impl
            })
        );

        // - LicenseRegistry
        contractKey = "LicenseRegistry";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(LicenseRegistry).name, "implementation")),
            abi.encodePacked(
                type(LicenseRegistry).creationCode,
                abi.encode(proxies.licensingModule, dependencies.disputeModule)
            )
        );
        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.licenseRegistry,
                newImpl: impl
            })
        );

        // - PILicenseTemplate
        contractKey = "PILicenseTemplate";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(PILicenseTemplate).name, "implementation")),
            abi.encodePacked(
                type(PILicenseTemplate).creationCode,
                abi.encode(
                    proxies.accessController,
                    proxies.ipAssetRegistry,
                    proxies.licenseRegistry,
                    proxies.royaltyModule
                )
            )
        );
        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.piLicenseTemplate,
                newImpl: impl
            })
        );

        // - AccessController
        contractKey = "AccessController";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(AccessController).name, "implementation")),
            abi.encodePacked(
                type(AccessController).creationCode,
                abi.encode(proxies.ipAssetRegistry, dependencies.moduleRegistry)
            )
        );
        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.accessController,
                newImpl: impl
            })
        );

        // - IPAccountImpl
        bytes memory ipAccountImplCode = abi.encodePacked(
            type(IPAccountImpl).creationCode,
            abi.encode(
                proxies.accessController,
                proxies.ipAssetRegistry,
                proxies.licenseRegistry,
                dependencies.moduleRegistry
            )
        );
        address ipAccountImpl = create3Deployer.deploy(
            _getSalt(string.concat(type(IPAccountImpl).name, "implementation")),
            ipAccountImplCode
        );

        // - IPAssetRegistry
        console2.log("Deploying IPAssetRegistry");
        contractKey = "IPAssetRegistry";

        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(IPAssetRegistry).name, "implementation")),
            abi.encodePacked(type(IPAssetRegistry).creationCode, abi.encode(erc6551Registry, ipAccountImpl))
        );

        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.ipAssetRegistry,
                newImpl: impl
            })
        );

        // - RoyaltyModule
        contractKey = "RoyaltyModule";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(RoyaltyModule).name, "implementation")),
            abi.encodePacked(
                type(RoyaltyModule).creationCode,
                abi.encode(proxies.licensingModule, dependencies.disputeModule, proxies.licenseRegistry)
            )
        );
        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.royaltyModule,
                newImpl: impl
            })
        );

        // - RoyaltyPolicyLAP.sol
        contractKey = "RoyaltyPolicyLAP";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(RoyaltyPolicyLAP).name, "implementation")),
            abi.encodePacked(
                type(RoyaltyPolicyLAP).creationCode,
                abi.encode(proxies.royaltyModule, proxies.licensingModule)
            )
        );
        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.royaltyPolicyLAP,
                newImpl: impl
            })
        );

        // - IPRoyaltyVaults
        contractKey = "IpRoyaltyVault";
        impl = create3Deployer.deploy(
            _getSalt(string.concat(type(IpRoyaltyVault).name, "implementation")),
            abi.encodePacked(
                type(IpRoyaltyVault).creationCode,
                abi.encode(proxies.royaltyPolicyLAP, dependencies.disputeModule)
            )
        );
        // In this case, RoyaltyPolicyLAP has the role to update the vaults in the Beacon
        upgradeProposals.push(
            UpgradeProposal({
                key: contractKey,
                proxy: proxies.royaltyPolicyLAP,
                newImpl: impl
            })
        );
        _logUpgradeProposals();
        return upgradeProposals;
    }

    function _getSalt(string memory name) private view returns (bytes32 salt) {
        salt = keccak256(abi.encode(name, create3SaltSeed));
    }
}
