// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

import { IAccessControl } from
    "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { BaseForkTest } from "../BaseForkTest.t.sol";
import { ISwapAdapter } from "../../src/interfaces/ISwapAdapter.sol";
import { AerodromeAdapter } from "../../src/swap/adapter/AerodromeAdapter.sol";
import { IRouter } from "../../src/vendor/aerodrome/IRouter.sol";

import "forge-std/console.sol";

/// @title AerodromeAdapterTEst
/// @notice Unit tests for the AerodromeAdapter contract
contract AerodromeAdapterTest is BaseForkTest {
    ///////////////////////////////////
    //////// REPLICATED EVENTS ////////
    ///////////////////////////////////

    /// @notice emitted when a value whether a pool is stable or not is set
    /// @param from first token of the pool
    /// @param to second token of the pool
    /// @param status boolean value indicating pool stability
    event IsPoolStableSet(IERC20 from, IERC20 to, bool status);

    /// @notice emitted when the poolFactory address is set
    /// @param factory address of poolFactory
    event PoolFactorySet(address factory);

    /// @notice emitted when the router address is set
    /// @param router address of router
    event RouterSet(address router);

    /// @notice emitted when set routes for a given swap are removed
    /// @param from address to swap from
    /// @param to addrses to swap to
    event RoutesRemoved(IERC20 from, IERC20 to);

    /// @notice emitted when the swap routes for a token pair are set
    /// @param from first token of the pool
    /// @param to second token of the pool
    /// @param routes array of routes for swap
    event RoutesSet(IERC20 from, IERC20 to, IRouter.Route[] routes);

    IERC20 public WETH = IERC20(BASE_MAINNET_WETH);
    IERC20 public CbETH = IERC20(BASE_MAINNET_CbETH);

    uint256 swapAmount = 1 ether;
    address alice = makeAddr("alice");
    address public MANAGER = makeAddr("MANAGER");
    address public NON_MANAGER = makeAddr("NON_MANAGER");

    AerodromeAdapter adapter;

    function setUp() public {
        adapter = new AerodromeAdapter(
            MANAGER, AERODROME_ROUTER, AERODROME_FACTORY, alice
        );

        vm.startPrank(MANAGER);
        adapter.grantRole(adapter.MANAGER_ROLE(), MANAGER);
        vm.stopPrank();

        deal(address(WETH), address(alice), 100 ether);
    }

    /// @dev ensure a swap is executed successully
    /// note: no token calculations done; this test only ensures
    /// the tokens are swapped
    function test_executeSwap() public {
        uint256 oldCbETHBalance = CbETH.balanceOf(alice);
        uint256 oldWETHBalance = WETH.balanceOf(alice);

        IRouter.Route[] memory routes = new IRouter.Route[](1);

        routes[0] = IRouter.Route({
            from: address(WETH),
            to: address(CbETH),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(MANAGER);
        adapter.setRoutes(WETH, CbETH, routes);

        vm.prank(alice);
        WETH.approve(address(adapter), swapAmount);

        vm.prank(alice);
        uint256 receivedCbETH =
            adapter.executeSwap(WETH, CbETH, swapAmount, payable(alice));

        uint256 newCbETHBalance = CbETH.balanceOf(alice);
        uint256 newWETHBalance = WETH.balanceOf(alice);

        assertEq(newCbETHBalance - oldCbETHBalance, receivedCbETH);
        assertEq(oldWETHBalance - newWETHBalance, swapAmount);
    }

    /// @dev ensures that swapping reverts when the caller is not the whitelisted swapper
    function test_executeSwap_revertsWhen_callerIsNotSwapper() public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);

        routes[0] = IRouter.Route({
            from: address(WETH),
            to: address(CbETH),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.startPrank(MANAGER);
        adapter.setRoutes(WETH, CbETH, routes);
        adapter.grantRole(adapter.SWAPPER_ROLE(), MANAGER);
        adapter.revokeRole(adapter.SWAPPER_ROLE(), alice);
        assertEq(adapter.hasRole(adapter.SWAPPER_ROLE(), alice), false);
        vm.stopPrank();

        vm.startPrank(alice);
        WETH.approve(address(adapter), swapAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                adapter.SWAPPER_ROLE()
            )
        );

        adapter.executeSwap(WETH, CbETH, swapAmount, payable(alice));
        vm.stopPrank();
    }

    /// @dev ensures setRoutes sets the new route and emits the appropriate event
    function test_setRoutes_setsRoutesForASwap_and_emitsRoutesSetEvent()
        public
    {
        assertEq(adapter.getSwapRoutes(WETH, CbETH).length, 0);

        IRouter.Route[] memory routes = new IRouter.Route[](1);

        routes[0] = IRouter.Route({
            from: address(WETH),
            to: address(CbETH),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(MANAGER);

        vm.expectEmit();
        emit RoutesSet(WETH, CbETH, routes);

        adapter.setRoutes(WETH, CbETH, routes);
    }

    /// @dev ensures setRoutes deletes the previously set routes if one
    /// was set, and sets the new routes
    function test_setRoutes_deletsPreviousRoute_and_setsRoutesForASwap()
        public
    {
        assertEq(adapter.getSwapRoutes(WETH, CbETH).length, 0);

        IRouter.Route[] memory routes = new IRouter.Route[](1);

        routes[0] = IRouter.Route({
            from: address(WETH),
            to: address(CbETH),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(MANAGER);
        adapter.setRoutes(WETH, CbETH, routes);

        vm.prank(MANAGER);

        vm.expectEmit();
        emit RoutesRemoved(WETH, CbETH);

        adapter.setRoutes(WETH, CbETH, routes);
    }

    /// @dev ensures setRoutes reverts when caller does not have manager role
    function test_setRoutes_revertsWhen_callerIsNotManager() public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);

        routes[0] = IRouter.Route({
            from: address(WETH),
            to: address(CbETH),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.startPrank(NON_MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_MANAGER,
                adapter.MANAGER_ROLE()
            )
        );
        adapter.setRoutes(WETH, CbETH, routes);
        vm.stopPrank();
    }

    /// @dev ensures removeRoutes deletes previously set routes and emits the appropriate event
    function test_removeRoutes_removesPreviouslySetRoutes_and_emitsRoutesRemovesEvent(
    ) public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);

        routes[0] = IRouter.Route({
            from: address(WETH),
            to: address(CbETH),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(MANAGER);
        adapter.setRoutes(WETH, CbETH, routes);

        assertEq(adapter.getSwapRoutes(WETH, CbETH).length, 1);

        vm.prank(MANAGER);

        vm.expectEmit();
        emit RoutesRemoved(WETH, CbETH);

        adapter.removeRoutes(WETH, CbETH);

        assertEq(adapter.getSwapRoutes(WETH, CbETH).length, 0);
    }

    /// @dev ensures removeRoutes reverts when caller does not have manager role
    function test_removeRoutes_revertsWhen_callerIsNotManager() public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);

        routes[0] = IRouter.Route({
            from: address(WETH),
            to: address(CbETH),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.startPrank(NON_MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_MANAGER,
                adapter.MANAGER_ROLE()
            )
        );

        adapter.setRoutes(WETH, CbETH, routes);
        vm.stopPrank();
    }

    /// @dev ensures setIsPoolStable sets the value for the stability of a pool
    /// and emits the appropirate event
    function test_setIsPoolStable_setsValueForIsPoolStableForGivenTokens_andEmitsIsPoolStableSetEvent(
    ) public {
        assertEq(adapter.isPoolStable(WETH, CbETH), false);

        vm.prank(MANAGER);

        vm.expectEmit();
        emit IsPoolStableSet(WETH, CbETH, true);

        adapter.setIsPoolStable(WETH, CbETH, true);

        assertEq(adapter.isPoolStable(WETH, CbETH), true);
    }

    /// @dev ensures setIsPoolStable reverts caller does not have manager role
    function test_setIsPoolStable_revertsWhen_callerIsNotManager() public {
        vm.startPrank(NON_MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_MANAGER,
                adapter.MANAGER_ROLE()
            )
        );

        adapter.setIsPoolStable(WETH, CbETH, true);
        vm.stopPrank();
    }

    /// @dev ensures setPoolFactory sets the new address for the Aerodrome router
    /// and emits the appropirate event
    function test_setRouter_setAddressForRouter_and_EmitsRouterSetEvent()
        public
    {
        assertEq(adapter.router(), AERODROME_ROUTER);

        vm.prank(MANAGER);

        vm.expectEmit();
        emit RouterSet(MANAGER);

        adapter.setRouter(MANAGER);
    }

    /// @dev ensures setRouter reverts when caller does not have manager role
    function test_setRouter_revertsWhen_callerIsNotManager() public {
        vm.startPrank(NON_MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_MANAGER,
                adapter.MANAGER_ROLE()
            )
        );

        adapter.setRouter(MANAGER);

        vm.stopPrank();
    }

    /// @dev ensures setPoolFactory sets the new address for the Aerodrome pool factory
    /// and emits the appropirate event
    function test_setPoolFactory_setAddressForPoolFactory_andEmitsPoolFactorySetEvent(
    ) public {
        assertEq(adapter.poolFactory(), AERODROME_FACTORY);

        vm.prank(MANAGER);

        vm.expectEmit();
        emit PoolFactorySet(MANAGER);

        adapter.setPoolFactory(MANAGER);
    }

    /// @dev ensures setPoolFactory reverts when caller does not have manager role
    function test_setPoolFactory_revertsWhen_callerIsNotManager() public {
        vm.startPrank(NON_MANAGER);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_MANAGER,
                adapter.MANAGER_ROLE()
            )
        );

        adapter.setPoolFactory(MANAGER);
        vm.stopPrank();
    }
}
