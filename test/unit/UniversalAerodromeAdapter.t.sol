// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

import { IAccessControl } from
    "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { OwnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { BaseForkTest } from "../BaseForkTest.t.sol";
import { ISwapAdapter } from "../../src/interfaces/ISwapAdapter.sol";
import { UniversalAerodromeAdapter } from
    "../../src/swap/adapter/UniversalAerodromeAdapter.sol";

contract UniversalAerodromeAdapterTest is BaseForkTest {
    event PathSet(IERC20 from, IERC20 to, bytes path);

    address public MANAGER = makeAddr("MANAGER");
    address public NON_MANAGER = makeAddr("NON_MANAGER");
    address payable BENEFICIARY = payable(makeAddr("BENEFICIARY"));

    uint256 swapAmountUSDC = 100 * 10 ** 6;
    uint256 swapAmountWETH = 1 ether;

    int24 tickSpacingWETHUSDC = 100;
    int24 tickSpacingWETHCbETH = 1;

    UniversalAerodromeAdapter adapter;
    IERC20 USDC = IERC20(BASE_MAINNET_USDC);
    IERC20 WETH = IERC20(BASE_MAINNET_WETH);
    IERC20 CbETH = IERC20(BASE_MAINNET_CbETH);
    IERC20 TEST_COIN = IERC20(makeAddr("test-coin"));

    function setUp() public {
        baseFork = vm.createSelectFork(BASE_RPC_URL, 15555784);

        deal(BASE_MAINNET_WETH, MANAGER, 1000 ether);
        deal(BASE_MAINNET_USDC, MANAGER, 1000 * 10 ** 6);

        adapter =
            new UniversalAerodromeAdapter(MANAGER, UNIVERSAL_ROUTER, MANAGER);

        address[] memory usdcWETH = new address[](2);
        address[] memory wethUSDC = new address[](2);

        int24[] memory tickSpacings = new int24[](1);

        usdcWETH[0] = address(USDC);
        usdcWETH[1] = address(WETH);
        wethUSDC[0] = address(WETH);
        wethUSDC[1] = address(USDC);
        tickSpacings[0] = tickSpacingWETHUSDC;

        vm.startPrank(MANAGER);
        adapter.grantRole(adapter.MANAGER_ROLE(), MANAGER);
        adapter.setPath(wethUSDC, tickSpacings);
        adapter.setPath(usdcWETH, tickSpacings);
        vm.stopPrank();
    }

    function test_setUp() public view {
        assertEq(adapter.hasRole(adapter.DEFAULT_ADMIN_ROLE(), MANAGER), true);
        assertEq(adapter.hasRole(adapter.MANAGER_ROLE(), MANAGER), true);
        assertEq(WETH.balanceOf(MANAGER), 1000 ether);
        assertEq(USDC.balanceOf(MANAGER), 1000 * 10 ** 6);
    }

    function testFuzz_executeSwap_swapsAllTokensSentToAdapter_andSendsReceivedTokens_toBeneficiary(
        uint256 swapAmount
    ) public {
        /// set min to 1 USD max to 3MM USD
        swapAmount = bound(swapAmount, 10 ** 8, 31000000 * 10 ** 8);
        deal(BASE_MAINNET_USDC, MANAGER, swapAmount);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        uint256 oldBeneficiaryBalanceWETH = WETH.balanceOf(BENEFICIARY);
        uint256 oldOwnerBalanceUSDC = USDC.balanceOf(MANAGER);

        vm.startPrank(MANAGER);
        USDC.approve(address(adapter), swapAmount);
        uint256 amountReceived =
            adapter.executeSwap(USDC, WETH, swapAmount, BENEFICIARY);
        vm.stopPrank();

        assertGt(amountReceived, 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(
            WETH.balanceOf(BENEFICIARY) - oldBeneficiaryBalanceWETH,
            amountReceived
        );
        assertEq(oldOwnerBalanceUSDC - USDC.balanceOf(MANAGER), swapAmount);
    }

    function test_executeSwap_transfersAllReceivedTokens_toBeneficiary()
        public
    {
        uint256 oldBalance = WETH.balanceOf(BENEFICIARY);
        uint256 oldOwnerBalanceUSDC = USDC.balanceOf(MANAGER);

        vm.startPrank(MANAGER);
        USDC.approve(address(adapter), swapAmountUSDC);
        uint256 amountReceived =
            adapter.executeSwap(USDC, WETH, swapAmountUSDC, BENEFICIARY);
        vm.stopPrank();

        assertEq(amountReceived, WETH.balanceOf(BENEFICIARY) - oldBalance);
        assertEq(oldOwnerBalanceUSDC - USDC.balanceOf(MANAGER), swapAmountUSDC);
    }

    function test_executeSwap_worksForMultiplePools() public {
        address[] memory usdcCbETH = new address[](3);
        int24[] memory tickSpacingsUSDCCbETH = new int24[](2);

        usdcCbETH[0] = address(USDC);
        usdcCbETH[1] = address(WETH);
        usdcCbETH[2] = address(CbETH);

        tickSpacingsUSDCCbETH[0] = tickSpacingWETHUSDC;
        tickSpacingsUSDCCbETH[1] = tickSpacingWETHCbETH;

        vm.startPrank(MANAGER);
        adapter.setPath(usdcCbETH, tickSpacingsUSDCCbETH);
        vm.stopPrank();

        uint256 swapAmount = 500 * 10 ** 6;

        uint256 oldBalance = CbETH.balanceOf(BENEFICIARY);
        uint256 oldOwnerBalanceUSDC = USDC.balanceOf(MANAGER);

        vm.startPrank(MANAGER);
        USDC.approve(address(adapter), swapAmount);
        uint256 amountReceived =
            adapter.executeSwap(USDC, CbETH, swapAmount, BENEFICIARY);
        vm.stopPrank();

        assertGt(amountReceived, 0);
        assertEq(CbETH.balanceOf(address(adapter)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(CbETH.balanceOf(address(adapter)), 0);
        assertEq(amountReceived, CbETH.balanceOf(BENEFICIARY) - oldBalance);
        assertEq(oldOwnerBalanceUSDC - USDC.balanceOf(MANAGER), swapAmount);
    }

    function test_executeSwap_succeeds_forVerySmallAmounts() public {
        uint256 oldBeneficiaryBalanceWETH = WETH.balanceOf(BENEFICIARY);
        uint256 oldOwnerBalanceUSDC = USDC.balanceOf(MANAGER);

        vm.startPrank(MANAGER);
        USDC.approve(address(adapter), 1);
        uint256 amountReceived = adapter.executeSwap(USDC, WETH, 1, BENEFICIARY);
        vm.stopPrank();

        assertEq(amountReceived, 0);

        assertEq(
            amountReceived,
            WETH.balanceOf(BENEFICIARY) - oldBeneficiaryBalanceWETH
        );
        assertEq(oldOwnerBalanceUSDC - USDC.balanceOf(MANAGER), 1);

        uint256 oldBeneficiaryBalanceUSDC = USDC.balanceOf(BENEFICIARY);
        uint256 oldOwnerBalanceWETH = WETH.balanceOf(MANAGER);

        vm.startPrank(MANAGER);
        WETH.approve(address(adapter), 1);
        amountReceived = adapter.executeSwap(WETH, USDC, 1, BENEFICIARY);
        vm.stopPrank();

        assertEq(amountReceived, 0);

        assertEq(
            amountReceived,
            USDC.balanceOf(BENEFICIARY) - oldBeneficiaryBalanceUSDC
        );
        assertEq(oldOwnerBalanceWETH - WETH.balanceOf(MANAGER), 1);
    }

    function test_setPath_setsNewPath_andEmits_PathSetEvent() public {
        bytes memory expectedPath = abi.encodePacked(
            address(TEST_COIN), tickSpacingWETHUSDC, address(WETH)
        );

        address[] memory tokens = new address[](2);
        int24[] memory tickSpacings = new int24[](1);

        tokens[0] = address(TEST_COIN);
        tokens[1] = address(WETH);
        tickSpacings[0] = tickSpacingWETHUSDC;

        vm.startPrank(MANAGER);
        vm.expectEmit();
        emit PathSet(TEST_COIN, WETH, expectedPath);

        adapter.setPath(tokens, tickSpacings);
        vm.stopPrank();

        assertEq(adapter.swapPaths(TEST_COIN, WETH), expectedPath);
    }

    function test_setPath_revertsIf_callerDoesNotHaveManagerRole() public {
        address[] memory tokens = new address[](2);
        int24[] memory tickSpacings = new int24[](1);

        tokens[0] = address(TEST_COIN);
        tokens[1] = address(WETH);
        tickSpacings[0] = tickSpacingWETHUSDC;

        vm.startPrank(NON_MANAGER);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_MANAGER,
                adapter.MANAGER_ROLE()
            )
        );

        adapter.setPath(tokens, tickSpacings);

        vm.stopPrank();
    }
}
