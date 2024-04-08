// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import { IGovernance } from "../../../../contracts/interfaces/governance/IGovernance.sol";
import { GovernanceLib } from "../../../../contracts/lib/GovernanceLib.sol";

contract MockGovernance is AccessManager, IGovernance {
    GovernanceLib.ProtocolState internal state;

    constructor(address admin) AccessManager(admin) {
    }

    function setState(GovernanceLib.ProtocolState newState) external {
        state = newState;
    }

    function getState() external view returns (GovernanceLib.ProtocolState) {
        return state;
    }

    function supportsInterface(bytes4) public pure returns (bool) {
        return true;
    }
}
