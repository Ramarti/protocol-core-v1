/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { console2 } from "forge-std/console2.sol";
import { UpgradeExecutor } from "../../utils/upgrades/UpgradeExecutor.s.sol";

contract Execute_V1_2_2 is UpgradeExecutor {
    
    constructor() UpgradeExecutor(
        "v1.2.1", // From version
        "v1.2.2", // To version
        UpgradeModes.SCHEDULE, // Schedule, Cancel or Execute upgrade
        Output.BATCH_TX_EXECUTION // Output mode
    ) {}

    function _scheduleUpgrades() internal virtual override {
        console2.log("Scheduling upgrades  -------------");
        _scheduleUpgrade("GroupingModule");
        _scheduleUpgrade("IPAssetRegistry");
        _scheduleUpgrade("LicenseRegistry");
        _scheduleUpgrade("LicenseToken");
        _scheduleUpgrade("PILicenseTemplate");
        _scheduleUpgrade("RoyaltyModule");
        _scheduleUpgrade("RoyaltyPolicyLAP");
        _scheduleUpgrade("RoyaltyPolicyLRP");
        _scheduleUpgrade("IpRoyaltyVault");
    }

    function _executeUpgrades() internal virtual override {
        console2.log("Executing upgrades  -------------");
        _executeUpgrade("IpRoyaltyVault");
        _executeUpgrade("GroupingModule");
        _executeUpgrade("IPAssetRegistry");
        _executeUpgrade("LicenseRegistry");
        _executeUpgrade("LicenseToken");
        _executeUpgrade("PILicenseTemplate");
        _executeUpgrade("RoyaltyModule");
        _executeUpgrade("RoyaltyPolicyLAP");
        _executeUpgrade("RoyaltyPolicyLRP");
        
    }

    function _cancelScheduledUpgrades() internal virtual override {
        console2.log("Cancelling upgrades  -------------");
        _cancelScheduledUpgrade("GroupingModule");
        _cancelScheduledUpgrade("IPAssetRegistry");
        _cancelScheduledUpgrade("LicenseRegistry");
        _cancelScheduledUpgrade("LicenseToken");
        _cancelScheduledUpgrade("PILicenseTemplate");
        _cancelScheduledUpgrade("RoyaltyModule");
        _cancelScheduledUpgrade("RoyaltyPolicyLAP");
        _cancelScheduledUpgrade("RoyaltyPolicyLRP");
        _cancelScheduledUpgrade("IpRoyaltyVault");
    }
}