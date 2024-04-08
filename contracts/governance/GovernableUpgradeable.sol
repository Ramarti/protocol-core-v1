// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// solhint-disable-next-line max-line-length
import { AccessManagedUpgradeable } from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import { Errors } from "../lib/Errors.sol";
import { IGovernance } from "../interfaces/governance/IGovernance.sol";
import { GovernanceLib } from "../lib/GovernanceLib.sol";

/// @title Governable
/// @dev All contracts managed by governance should inherit from this contract.
abstract contract GovernableUpgradeable is Initializable, AccessManagedUpgradeable {
    modifier whenNotPaused() {
        if (IGovernance(authority()).getState() == GovernanceLib.ProtocolState.Paused) {
            revert Errors.Governance__ProtocolPaused();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice initializer for this implementation contract
    /// @param governance The address of the governance.
    function __GovernableUpgradeable_init(address governance) internal onlyInitializing {
        __AccessManaged_init(governance);
    }

    /// @notice Sets a new governance address.
    /// @dev only callable by the current governance.
    /// @param newAuthority The address of the new governance.
    function setAuthority(address newAuthority) public virtual override {
        if (!ERC165Checker.supportsInterface(newAuthority, type(IGovernance).interfaceId))
            revert Errors.Governance__UnsupportedInterface("IGovernance");
        if (IGovernance(newAuthority).getState() != IGovernance(newAuthority).getState())
            revert Errors.Governance__InconsistentState();
        super.setAuthority(newAuthority);
    }
}
