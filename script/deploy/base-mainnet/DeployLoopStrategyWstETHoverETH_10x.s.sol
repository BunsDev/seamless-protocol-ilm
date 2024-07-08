// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IAccessControl } from
    "@openzeppelin/contracts/access/IAccessControl.sol";
import { ISwapper, Swapper } from "../../../src/swap/Swapper.sol";
import { LoopStrategy, ILoopStrategy } from "../../../src/LoopStrategy.sol";
import { WrappedTokenAdapter } from
    "../../../src/swap/adapter/WrappedTokenAdapter.sol";
import { AerodromeAdapter } from
    "../../../src/swap/adapter/AerodromeAdapter.sol";
import { DeployHelper } from "../DeployHelper.s.sol";
import { WrappedERC20PermissionedDeposit } from
    "../../../src/tokens/WrappedERC20PermissionedDeposit.sol";
import {
    LoopStrategyConfig,
    ERC20Config,
    ReserveConfig,
    CollateralRatioConfig,
    SwapperConfig
} from "../config/LoopStrategyConfig.sol";
import { CollateralRatio } from "../../../src/types/DataTypes.sol";
import { USDWadRayMath } from "../../../src/libraries/math/USDWadRayMath.sol";
import { BaseMainnetConstants } from "../config/BaseMainnetConstants.sol";

contract LoopStrategyWstETHoverETHConfig_10x is BaseMainnetConstants {
    WrappedERC20PermissionedDeposit public wrappedToken =
        WrappedERC20PermissionedDeposit(BASE_MAINNET_SEAMLESS_WRAPPED_WSTETH);

    // TODO: set asset cap
    uint256 public assetsCap = 0 ether;

    uint256 public maxSlippageOnRebalance = 1_000000; // 1%

    LoopStrategyConfig public wstETHoverETHconfig_10x = LoopStrategyConfig({
        // wstETH address
        underlyingTokenAddress: BASE_MAINNET_wstETH,
        // wstETH-USD Adapter oracle (used in the Seamless pool)
        underlyingTokenOracle: WSTETH_ETH_ORACLE,
        strategyERC20Config: ERC20Config({
            name: "Seamless ILM 10x Loop wstETH/ETH",
            symbol: "ilm-wstETH/ETH-10xloop"
        }),
        wrappedTokenERC20Config: ERC20Config("", ""), // empty, not used
        wrappedTokenReserveConfig: ReserveConfig(
            address(0), "", "", "", "", "", "", 0, 0, 0
        ), // empty, not used
        collateralRatioConfig: CollateralRatioConfig({
            collateralRatioTargets: CollateralRatio({
                target: USDWadRayMath.usdDiv(110, 100), // 1.1
                minForRebalance: USDWadRayMath.usdDiv(109, 100), // 1.09
                maxForRebalance: USDWadRayMath.usdDiv(1100015, 1000000), // 1.100015
                maxForDepositRebalance: USDWadRayMath.usdDiv(110, 100), // 1.1
                minForWithdrawRebalance: USDWadRayMath.usdDiv(110, 100) // 1.1
             }),
            ratioMargin: 1, // 0.000001% ratio margin
            maxIterations: 20
        }),
        swapperConfig: SwapperConfig({
            swapperOffsetFactor: 0, // not used
            swapperOffsetDeviation: 0 // not used
         }),
        debtAsset: BASE_MAINNET_WETH
    });
}

contract DeployLoopStrategyWstETHoverETH_10x is
    Script,
    DeployHelper,
    LoopStrategyWstETHoverETHConfig_10x
{
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        LoopStrategy strategy = _deployLoopStrategy(
            wrappedToken,
            deployerAddress,
            ISwapper(SWAPPER),
            wstETHoverETHconfig_10x
        );

        strategy.setAssetsCap(assetsCap);

        strategy.setMaxSlippageOnRebalance(maxSlippageOnRebalance);

        // set roles on strategy
        _grantRoles(strategy, strategy.DEFAULT_ADMIN_ROLE());
        _grantRoles(strategy, strategy.MANAGER_ROLE());
        _grantRoles(strategy, strategy.UPGRADER_ROLE());
        _grantRoles(strategy, strategy.PAUSER_ROLE());

        // renounce deployer roles on strategy
        strategy.renounceRole(strategy.MANAGER_ROLE(), deployerAddress);
        strategy.renounceRole(strategy.DEFAULT_ADMIN_ROLE(), deployerAddress);

        vm.stopBroadcast();
    }

    function _grantRoles(IAccessControl accessContract, bytes32 role)
        internal
    {
        accessContract.grantRole(role, SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS);
        accessContract.grantRole(role, SEAMLESS_COMMUNITY_MULTISIG);
    }
}
