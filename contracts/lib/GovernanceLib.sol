// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/// @title Governance
/// @dev This library provides types for Story Protocol Governance.
library GovernanceLib {
    uint64 public constant PROTOCOL_ADMIN = type(uint64).min; // 0
    uint64 public constant PUBLIC_ROLE = type(uint64).max; // 2**64-1
    uint64 public constant UPGRADER_ROLE = 1;
    uint64 public constant PAUSER_ROLE = 2;


    /// @notice An enum containing the different states the protocol can be in.
    /// @param Unpaused The unpaused state.
    /// @param Paused The paused state.
    enum ProtocolState {
        Unpaused,
        Paused
    }


}
