// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { IIPAccount } from "../../../contracts/interfaces/IIPAccount.sol";
import { AccessPermission } from "../../../contracts/lib/AccessPermission.sol";
import { Errors } from "../../../contracts/lib/Errors.sol";
import { GovernanceLib } from "../../../contracts/lib/GovernanceLib.sol";
import { Governance } from "../../../contracts/governance/Governance.sol";
import { Governable } from "../../../contracts/governance/Governable.sol";

import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

import { MockModule } from "../mocks/module/MockModule.sol";
import { MockGovernable } from "../mocks/governance/MockGovernable.sol";
import { BaseTest } from "../utils/BaseTest.t.sol";
import { TestProxyHelper } from "test/foundry/utils/TestProxyHelper.sol";

contract GovernanceTest is BaseTest {
    MockModule mockModule;
    MockModule moduleWithoutPermission;
    MockModule mockModule2;
    MockGovernable mockGovernable;
    IIPAccount ipAccount;

    address owner = vm.addr(1);
    uint256 tokenId = 100;

    modifier withRegisteredMockModule2() {
        mockModule2 = new MockModule(address(ipAccountRegistry), address(moduleRegistry), "MockModule2");
        vm.prank(u.admin);
        moduleRegistry.registerModule("MockModule2", address(mockModule2));
        _;
    }

    function setUp() public override {
        super.setUp();
        buildDeployAccessCondition(DeployAccessCondition({ accessController: true, governance: true }));
        buildDeployRegistryCondition(DeployRegistryCondition({ moduleRegistry: true, licenseRegistry: false }));
        deployConditionally();
        postDeploymentSetup();

        mockNFT.mintId(owner, tokenId);

        address deployedAccount = ipAccountRegistry.registerIpAccount(block.chainid, address(mockNFT), tokenId);
        ipAccount = IIPAccount(payable(deployedAccount));

        mockModule = new MockModule(address(ipAccountRegistry), address(moduleRegistry), "MockModule");
        mockGovernable = new MockGovernable(address(governance));

        vm.startPrank(u.admin);
        bytes4[] memory selectors = new bytes4[](1);
        // selectors[0] = mockGovernable.restrictedMethod.selector;
        // governance.setTargetFunctionRole(address(mockGovernable), selectors, GovernanceLib.PROTOCOL_ADMIN);

        selectors[0] = mockGovernable.restrictedMethodOtherRole.selector;
        governance.setTargetFunctionRole(address(mockGovernable), selectors, GovernanceLib.UPGRADER_ROLE);
        governance.grantRole(GovernanceLib.UPGRADER_ROLE, u.alice, 0);

        vm.stopPrank();
    }

    function test_Governance_restrictedMethodSuccess() public {
        vm.prank(u.admin);
        mockGovernable.restrictedMethod();
        assertTrue(mockGovernable.methodCalled());

        vm.prank(u.alice);
        mockGovernable.restrictedMethodOtherRole();
        assertTrue(mockGovernable.methodCalledOtherRole());
    }

    function test_Governance_revert_restrictedMethodWithNonAdmin() public {
        vm.prank(address(0x777));
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", address(0x777)));
        mockGovernable.restrictedMethod();
    }

    function test_Governance_revert_otherRoleWithNotRoleMember() public {
        vm.prank(address(0x777));
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", address(0x777)));
        mockGovernable.restrictedMethodOtherRole();
        vm.prank(u.admin);
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", u.admin));
        mockGovernable.restrictedMethodOtherRole();
    }

    function test_Governance_revert_restrictedMethodWithOldAdmin() public {
        address newAdmin = vm.addr(3);

        vm.startPrank(u.admin);
        governance.grantRole(GovernanceLib.PROTOCOL_ADMIN, newAdmin, 0);
        governance.revokeRole(GovernanceLib.PROTOCOL_ADMIN, u.admin);

        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", u.admin));
        mockGovernable.restrictedMethod();
    }

    function test_Governance_setNewGovernance() public {
        address newAdmin = vm.addr(3);
        Governance newGovernance = _deployGovernance(newAdmin);
        vm.prank(u.admin);
        IAccessManaged(address(moduleRegistry)).setAuthority(address(newGovernance));
        assertEq(Governable(address(moduleRegistry)).authority(), address(newGovernance));
    }

    function test_Governance_adminFunctionWithNewGov() public {
        address newAdmin = vm.addr(3);
        Governance newGovernance = _deployGovernance(newAdmin);

        vm.prank(u.admin);
        governance.updateAuthority(address(mockGovernable), address(newGovernance));

        vm.prank(newAdmin);
        mockGovernable.restrictedMethod();
        assertTrue(mockGovernable.methodCalled());
    }

    function test_Governance_revert_adminFunctionWithOldGov() public {
        address newAdmin = vm.addr(3);
        Governance newGovernance = _deployGovernance(newAdmin);

        vm.prank(u.admin);
        governance.updateAuthority(address(mockGovernable), address(newGovernance));

        vm.prank(u.admin);
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", u.admin));
        mockGovernable.restrictedMethod();
    }

    function test_Governance_revert_checkPermissionUnPausedThenPauseThenUnPause() public withRegisteredMockModule2 {
        vm.startPrank(u.admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                address(mockModule),
                address(mockModule2),
                bytes4(0)
            )
        );
        accessController.checkPermission(address(ipAccount), address(mockModule), address(mockModule2), bytes4(0));
        (bool inRole, uint32 executionDelay) = governance.hasRole(0, u.admin);

        governance.setState(GovernanceLib.ProtocolState.Paused);
        // vm.expectRevert(abi.encodeWithSelector(Errors.Governance__ProtocolPaused.selector));
        // accessController.checkPermission(address(ipAccount), address(mockModule), address(mockModule2), bytes4(0));

        // governance.setState(GovernanceLib.ProtocolState.Unpaused);
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         Errors.AccessController__PermissionDenied.selector,
        //         address(ipAccount),
        //         address(mockModule),
        //         address(mockModule2),
        //         bytes4(0)
        //     )
        // );
        // accessController.checkPermission(address(ipAccount), address(mockModule), address(mockModule2), bytes4(0));
    }

    function test_Governance_revert_setNewGovernanceNotContract() public {
        vm.prank(u.admin);
        vm.expectRevert();
        IAccessManaged(address(moduleRegistry)).setAuthority(address(0xbeefbeef));
    }

    function test_Governance_revert_setNewGovernanceNotSupportInterface() public {
        vm.prank(u.admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Governance__UnsupportedInterface.selector, "IGovernance"));
        IAccessManaged(address(mockGovernable)).setAuthority(address(mockModule));

        vm.prank(u.admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Governance__UnsupportedInterface.selector, "IGovernance"));
        IAccessManaged(address(mockGovernable)).setAuthority(address(0));
    }

    function test_Governance_revert_setNewGovernanceInconsistentState() public {
        address newAdmin = vm.addr(3);
        Governance newGovernance = _deployGovernance(newAdmin);
        (bool immediate, uint32 delay) = newGovernance.canCall(
            newAdmin,
            address(newGovernance),
            newGovernance.setState.selector
        );
        vm.prank(newAdmin);
        newGovernance.setState(GovernanceLib.ProtocolState.Paused);

        vm.prank(u.admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Governance__InconsistentState.selector));
        governance.updateAuthority(address(mockGovernable), address(newGovernance));
    }

    function test_Governance_revert_setPermissionWhenPaused() public withRegisteredMockModule2 {
        vm.startPrank(u.admin);
        governance.setState(GovernanceLib.ProtocolState.Paused);
        vm.expectRevert(abi.encodeWithSelector(Errors.Governance__ProtocolPaused.selector));
        accessController.setPermission(
            address(ipAccount),
            address(mockModule),
            address(mockModule2),
            bytes4(0),
            AccessPermission.ALLOW
        );
    }

    function test_Governance_revert_checkPermissionWhenPaused() public withRegisteredMockModule2 {
        vm.startPrank(u.admin);
        governance.setState(GovernanceLib.ProtocolState.Paused);
        vm.expectRevert(abi.encodeWithSelector(Errors.Governance__ProtocolPaused.selector));
        accessController.checkPermission(address(ipAccount), address(mockModule), address(mockModule2), bytes4(0));
    }

    function test_Governance_revert_setStateWithNonAdmin() public {
        vm.prank(address(0x777));
        vm.expectRevert(abi.encodeWithSelector(Errors.Governance__OnlyProtocolAdmin.selector));
        governance.setState(GovernanceLib.ProtocolState.Paused);
    }

    function test_Governance_revert_setSameState() public {
        vm.startPrank(u.admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Governance__NewStateIsTheSameWithOldState.selector));
        governance.setState(GovernanceLib.ProtocolState.Unpaused);
    }

    function _deployGovernance(address admin) internal returns (Governance) {
        address impl = address(new Governance());
        return Governance(TestProxyHelper.deployUUPSProxy(impl, abi.encodeCall(Governance.initialize, admin)));
    }
}
