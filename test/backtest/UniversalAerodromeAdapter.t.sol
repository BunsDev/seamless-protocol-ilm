// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { DeployHelperLib } from "../../script/deploy/DeployHelperLib.sol";
import { Swapper } from "../../src/swap/Swapper.sol";
import { IUniversalRouter } from
    "../../src/vendor/aerodrome/IUniversalRouter.sol";
import { LoopStrategy, ILoopStrategy } from "../../src/LoopStrategy.sol";
import { IPriceOracleGetter } from "../../src/interfaces/IPriceOracleGetter.sol";
import { CollateralRatio } from "../../src/types/DataTypes.sol";
import { UniversalAerodromeAdapter } from
    "../../src/swap/adapter/UniversalAerodromeAdapter.sol";
import { IWrappedERC20PermissionedDeposit } from
    "../../src/interfaces/IWrappedERC20PermissionedDeposit.sol";
import { WrappedTokenAdapter } from
    "../../src/swap/adapter/WrappedTokenAdapter.sol";
import { TestConstants } from "../config/TestConstants.sol";

contract UniversalAerodromeAdapterBackTest is Test, TestConstants {
    string internal BASE_RPC_URL = vm.envString("BASE_MAINNET_RPC_URL");

    LoopStrategy WSTETH_WETH = LoopStrategy(WSTETH_WETH_3x_LOOP_STRATEGY);
    LoopStrategy WETH_USDC_LONG =
        LoopStrategy(WETH_USDC_LONG_1p5x_LOOP_STRATEGY);
    Swapper swapper = Swapper(0xE314ae9D279919a00d4773cCe37946A98fADDaBc);

    IWrappedERC20PermissionedDeposit wrappedTokenWSTETH =
    IWrappedERC20PermissionedDeposit(0xc9ae3B5673341859D3aC55941D27C8Be4698C9e4);
    IWrappedERC20PermissionedDeposit wrappedTokenWETH =
    IWrappedERC20PermissionedDeposit(0x3e8707557D4aD25d6042f590bCF8A06071Da2c5F);

    WrappedTokenAdapter wrappedTokenAdapter =
        WrappedTokenAdapter(0xc3e17CDac7C6ED317f0D9845d47df1a281B5f79E);

    IERC20 USDC = IERC20(BASE_MAINNET_USDC);
    IERC20 WETH = IERC20(BASE_MAINNET_WETH);
    IERC20 WSTETH = IERC20(BASE_MAINNET_WSTETH);

    int24 tickSpacingWETHUSDC = 100;
    int24 tickSpacingWETHWSTETH = 1;

    uint256 swapperOffsetFactor = 350000;

    uint256 WETH_USDC_LONG_REBALANCE_BLOCK = 14728506;
    uint256 WSTETH_WETH_REBALANCE_BLOCK = 15798959;

    function _deployAndSetupUniversalAerodromeAdapter() internal {
        UniversalAerodromeAdapter universalAerodromeAdapter = new UniversalAerodromeAdapter(
            SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS,
            UNIVERSAL_ROUTER,
            address(swapper)
        );

        address[] memory usdcWETH = new address[](2);
        address[] memory wethUSDC = new address[](2);
        int24[] memory tickSpacingsWETHUSDC = new int24[](1);

        usdcWETH[0] = address(USDC);
        usdcWETH[1] = address(WETH);
        wethUSDC[0] = address(WETH);
        wethUSDC[1] = address(USDC);
        tickSpacingsWETHUSDC[0] = tickSpacingWETHUSDC;

        address[] memory wethWSTETH = new address[](2);
        address[] memory wstethWETH = new address[](2);
        int24[] memory tickSpacingsWETHWSTETH = new int24[](1);

        wethWSTETH[0] = address(WETH);
        wethWSTETH[1] = address(WSTETH);
        wstethWETH[0] = address(WSTETH);
        wstethWETH[1] = address(WETH);
        tickSpacingsWETHWSTETH[0] = tickSpacingWETHWSTETH;

        vm.startPrank(SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS);
        universalAerodromeAdapter.grantRole(
            universalAerodromeAdapter.MANAGER_ROLE(),
            SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS
        );
        universalAerodromeAdapter.setPath(usdcWETH, tickSpacingsWETHUSDC);
        universalAerodromeAdapter.setPath(wethUSDC, tickSpacingsWETHUSDC);
        universalAerodromeAdapter.setPath(wethWSTETH, tickSpacingsWETHWSTETH);
        universalAerodromeAdapter.setPath(wstethWETH, tickSpacingsWETHWSTETH);

        DeployHelperLib._setSwapperRouteBetweenWrappedAndToken(
            swapper,
            wrappedTokenWSTETH,
            WETH,
            wrappedTokenAdapter,
            universalAerodromeAdapter,
            swapperOffsetFactor
        );

        DeployHelperLib._setSwapperRouteBetweenWrappedAndToken(
            swapper,
            wrappedTokenWETH,
            USDC,
            wrappedTokenAdapter,
            universalAerodromeAdapter,
            swapperOffsetFactor
        );

        vm.stopPrank();
    }

    function test_rebalanceSucceedsTo_rebalanceUp_whenUsing_universalAerodromeAdapter_for_WSTETH_WETH_strategy(
    ) public {
        vm.createSelectFork(BASE_RPC_URL, WSTETH_WETH_REBALANCE_BLOCK);
        CollateralRatio memory targets = WSTETH_WETH.getCollateralRatioTargets();

        uint256 currentCR = WSTETH_WETH.currentCollateralRatio();

        assertGt(currentCR, targets.target);
        assertEq(
            WSTETH_WETH.rebalanceNeeded(),
            true,
            "Initial: rebalance not needed."
        );

        _deployAndSetupUniversalAerodromeAdapter();

        vm.expectCall(
            UNIVERSAL_ROUTER,
            abi.encodeWithSelector(IUniversalRouter.execute.selector)
        );
        WSTETH_WETH.rebalance();

        assertEq(
            WSTETH_WETH.rebalanceNeeded(), false, "Final: rebalance needed."
        );
    }

    function test_rebalanceSucceedsTo_rebalanceDown_whenUsing_universalAerodromeAdapter_for_WSTETH_WETH_strategy(
    ) public {
        vm.createSelectFork(BASE_RPC_URL, WSTETH_WETH_REBALANCE_BLOCK);

        CollateralRatio memory targets = WSTETH_WETH.getCollateralRatioTargets();

        /// @dev magic values chosen to ensure rebalance downwards is needed
        vm.mockCall(
            address(WSTETH_WETH.getOracle()),
            abi.encodeWithSelector(
                IPriceOracleGetter.getAssetPrice.selector, address(WETH)
            ),
            abi.encode(4450 * 10 ** 8)
        );
        vm.mockCall(
            address(WSTETH_WETH.getOracle()),
            abi.encodeWithSelector(
                IPriceOracleGetter.getAssetPrice.selector,
                address(wrappedTokenWSTETH)
            ),
            abi.encode(456293 * 10 ** 6)
        );

        uint256 currentCR = WSTETH_WETH.currentCollateralRatio();

        assertLt(currentCR, targets.target);
        assertEq(
            WSTETH_WETH.rebalanceNeeded(),
            true,
            "Initial: rebalance not needed."
        );

        _deployAndSetupUniversalAerodromeAdapter();

        vm.expectCall(
            UNIVERSAL_ROUTER,
            abi.encodeWithSelector(IUniversalRouter.execute.selector)
        );
        WSTETH_WETH.rebalance();

        assertEq(
            WSTETH_WETH.rebalanceNeeded(),
            false,
            "Final: rebalance still needed"
        );
    }

    function test_rebalanceSucceedsTo_rebalanceUp_whenUsing_universalAerodromeAdapter_for_WETH_USDC_LONG_strategy(
    ) public {
        vm.createSelectFork(BASE_RPC_URL, WETH_USDC_LONG_REBALANCE_BLOCK);

        CollateralRatio memory targets =
            WETH_USDC_LONG.getCollateralRatioTargets();
        uint256 currentCR = WETH_USDC_LONG.currentCollateralRatio();

        assertGt(currentCR, targets.target);
        assertEq(
            WETH_USDC_LONG.rebalanceNeeded(),
            true,
            "Initial: rebalance not needed."
        );

        _deployAndSetupUniversalAerodromeAdapter();

        vm.expectCall(
            UNIVERSAL_ROUTER,
            abi.encodeWithSelector(IUniversalRouter.execute.selector)
        );
        WETH_USDC_LONG.rebalance();

        assertEq(
            WETH_USDC_LONG.rebalanceNeeded(), false, "Final: rebalance needed."
        );
    }

    function test_rebalanceSucceedsTo_rebalanceDown_whenUsing_universalAerodromeAdapter_for_WETH_USDC_LONG_strategy(
    ) public {
        vm.createSelectFork(BASE_RPC_URL, WETH_USDC_LONG_REBALANCE_BLOCK);

        CollateralRatio memory targets =
            WETH_USDC_LONG.getCollateralRatioTargets();

        /// @dev magic value chosen to ensure rebalance downwards is needed
        vm.mockCall(
            address(WETH_USDC_LONG.getOracle()),
            abi.encodeWithSelector(
                IPriceOracleGetter.getAssetPrice.selector,
                address(wrappedTokenWETH)
            ),
            abi.encode(2600 * 10 ** 8)
        );

        uint256 currentCR = WETH_USDC_LONG.currentCollateralRatio();

        assertLt(currentCR, targets.target);
        assertEq(
            WETH_USDC_LONG.rebalanceNeeded(),
            true,
            "Initial: rebalance not needed."
        );

        _deployAndSetupUniversalAerodromeAdapter();

        vm.expectCall(
            UNIVERSAL_ROUTER,
            abi.encodeWithSelector(IUniversalRouter.execute.selector)
        );
        WETH_USDC_LONG.rebalance();

        assertEq(
            WETH_USDC_LONG.rebalanceNeeded(), false, "Final: rebalance needed."
        );
    }
}
