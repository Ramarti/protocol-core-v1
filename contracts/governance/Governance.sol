// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessManagerUpgradeable } from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagerUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { Errors } from "../lib/Errors.sol";
import { IGovernance } from "../interfaces/governance/IGovernance.sol";
import { GovernanceLib } from "../lib/GovernanceLib.sol";

/// @title Governance
/// @dev This contract is used for governance of the protocol.
contract Governance is IGovernance, AccessManagerUpgradeable, ERC165Upgradeable, UUPSUpgradeable {
    /// @dev The current governance state.
    GovernanceLib.ProtocolState internal state;

    /// @notice Method to check for admin roles in this contract
    /// @dev onlyAuthorized works only for AccessManager contract...
    modifier govRestricted() {
        bytes4 selector = bytes4(msg.data[0:4]);
        (bool allowed, uint32 delay) = canCall(msg.sender, address(this), selector);
        if (!allowed) {
            revert AccessManagerUnauthorizedAccount(msg.sender, getTargetFunctionRole(address(this), selector));
        }
        _;
    }

    /// Constructor
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice initializer for Governance contract
    /// @param initialAdmin The address of the initial admin account
    function initialize(address initialAdmin) public initializer {
        __AccessManager_init(initialAdmin);
        __ERC165_init();
        __UUPSUpgradeable_init();
        state = GovernanceLib.ProtocolState.Unpaused;
    }

    /// @notice Sets the state of the protocol
    /// @dev This function can only be called by an account with the appropriate role
    /// @param newState The new state to set for the protocol
    function setState(GovernanceLib.ProtocolState newState) external override govRestricted {
        if (newState == state) revert Errors.Governance__NewStateIsTheSameWithOldState();
        emit StateSet(msg.sender, state, newState, block.timestamp);
        state = newState;
    }

    /// @notice Returns the current state of the protocol
    /// @return state The current state of the protocol
    function getState() external view override returns (GovernanceLib.ProtocolState) {
        return state;
    }

    function canCall(
        address caller,
        address target,
        bytes4 selector
    ) public virtual override(IAccessManager, AccessManagerUpgradeable) view returns (bool allowed, uint32 delay) {
        return super.canCall(caller, target, selector);
    }

    /// @notice IERC165 interface support.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return (interfaceId == type(IGovernance).interfaceId || super.supportsInterface(interfaceId));
    }

    function _authorizeUpgrade(address newImplementation) internal override govRestricted {}
}
