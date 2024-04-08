// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

import { Errors } from "../lib/Errors.sol";
import { IGovernance } from "../interfaces/governance/IGovernance.sol";
import { GovernanceLib } from "../lib/GovernanceLib.sol";

/// @title Governable
/// @dev All contracts managed by governance should inherit from this contract.
abstract contract Governable is AccessManaged {
    modifier whenNotPaused() {
        if (IGovernance(authority()).getState() == GovernanceLib.ProtocolState.Paused) {
            revert Errors.Governance__ProtocolPaused();
        }
        _;
    }

    /// @notice Constructs a new Governable contract.
    /// @param governance The address of the governance.
    constructor(address governance) AccessManaged(governance) {
        if (!ERC165Checker.supportsInterface(governance, type(IGovernance).interfaceId))
            revert Errors.Governance__UnsupportedInterface("IGovernance");
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
