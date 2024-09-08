import { console2 } from "forge-std/console2.sol";
import { UpgradeExecuter } from "../../utils/upgrades/UpgradeExecuter.s.sol";

contract ExecuteV1_2 is UpgradeExecuter {
    
    constructor() UpgradeExecuter(
        "v1.1.1", // From version
        "v1.2", // To version
        UpgradeModes.EXECUTE, // Schedule or Execute upgrade
        Output.BATCH_TX_EXECUTION // Output mode
    ) {}

    function _scheduleUpgrades() internal virtual override {
        console2.log("Scheduling upgrades  -------------");

        _scheduleUpgrade("LicenseToken");
        _scheduleUpgrade("RoyaltyPolicyLAP");
        _scheduleUpgrade("IPAssetRegistry");
        _scheduleUpgrade("LicenseRegistry");
    }

    function _executeUpgrades() internal virtual override {
        console2.log("Executing upgrades  -------------");
        _executeUpgrade("LicenseToken");
        _executeUpgrade("RoyaltyPolicyLAP");
        _executeUpgrade("IPAssetRegistry");
        _executeUpgrade("LicenseRegistry");
    }
}