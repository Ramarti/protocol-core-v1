// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;


import { Governable } from "../../../../contracts/governance/Governable.sol";

contract MockGovernable is Governable {

    bool public methodCalled;
    bool public methodCalledOtherRole;

    constructor(address governance) Governable(governance) {}

    /// @dev keep restricted to protocol admin role
    function restrictedMethod() external restricted {
        methodCalled = true;
    }

    /// @dev set a different role for this method
    function restrictedMethodOtherRole() external restricted {
        methodCalledOtherRole = true;
    }

}
