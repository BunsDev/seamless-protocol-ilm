// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IAccessControl } from
    "@openzeppelin/contracts/access/IAccessControl.sol";
import { ISwapper, Swapper } from "../../../src/swap/Swapper.sol";
import { IRouter } from "../../../src/vendor/aerodrome/IRouter.sol";
import { LoopStrategy, ILoopStrategy } from "../../../src/LoopStrategy.sol";
import { IWrappedTokenAdapter } from
    "../../../src/interfaces/IWrappedTokenAdapter.sol";
import { IAerodromeAdapter } from
    "../../../src/interfaces/IAerodromeAdapter.sol";
import { DeployHelper } from "../DeployHelper.s.sol";
import {
    WrappedERC20PermissionedDeposit,
    IWrappedERC20PermissionedDeposit
} from "../../../src/tokens/WrappedERC20PermissionedDeposit.sol";
import {
    LoopStrategyConfig,
    ERC20Config,
    ReserveConfig,
    CollateralRatioConfig,
    SwapperConfig
} from "../config/LoopStrategyConfig.sol";
import {
    CollateralRatio, StrategyAssets
} from "../../../src/types/DataTypes.sol";
import { USDWadRayMath } from "../../../src/libraries/math/USDWadRayMath.sol";
import { BaseMainnetConstants } from "../config/BaseMainnetConstants.sol";
import { ISwapAdapter } from "../../../src/interfaces/ISwapAdapter.sol";
import { DeployHelperLib } from "../DeployHelperLib.sol";
import { DeployLoopStrategyETHoverUSDCGuardianPayload } from
    "./DeployLoopStrategyETHoverUSDCGuardianPayload.sol";

contract LoopStrategyETHoverUSDCConfig_4p5x is BaseMainnetConstants {
    // wrapped WETH
    WrappedERC20PermissionedDeposit public wrappedToken =
        WrappedERC20PermissionedDeposit(BASE_MAINNET_SEAMLESS_WRAPPED_WETH);

    uint256 public assetsCap = 35 ether;

    uint256 public maxSlippageOnRebalance = 1_000000; // 1%

    LoopStrategyConfig public ethOverUSDCconfig_4p5x = LoopStrategyConfig({
        // WETH address
        underlyingTokenAddress: BASE_MAINNET_WETH,
        // ETH-USD oracle
        underlyingTokenOracle: WETH_USD_ORACLE,
        strategyERC20Config: ERC20Config({
            name: "Seamless ILM 4p5x Loop ETH/USDC",
            symbol: "ilm-ETH/USDC-4p5xloop"
        }),
        wrappedTokenERC20Config: ERC20Config("", ""), // empty, not used
        wrappedTokenReserveConfig: ReserveConfig(
            address(0), "", "", "", "", "", "", 0, 0, 0
        ), // empty, not used
        collateralRatioConfig: CollateralRatioConfig({
            collateralRatioTargets: CollateralRatio({
                target: USDWadRayMath.usdDiv(1285, 1000), // 1.285 (4.5x)
                minForRebalance: USDWadRayMath.usdDiv(12593, 10000), // 1.2593 (-2%) (4.85x)
                maxForRebalance: USDWadRayMath.usdDiv(13107, 10000), // 1.3107 (+2%) (4.21x)
                maxForDepositRebalance: USDWadRayMath.usdDiv(1285, 1000), // = target
                minForWithdrawRebalance: USDWadRayMath.usdDiv(1285, 1000) // = target
             }),
            ratioMargin: 1, // 0.000001% ratio margin
            maxIterations: 20
        }),
        swapperConfig: SwapperConfig({
            swapperOffsetFactor: 0, // not used
            swapperOffsetDeviation: 0 // not used
         }),
        debtAsset: BASE_MAINNET_USDC
    });
}

contract DeployLoopStrategyETHoverUSDC_4p5x is
    Script,
    DeployHelper,
    LoopStrategyETHoverUSDCConfig_4p5x
{
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        Swapper swapper = Swapper(SWAPPER);

        LoopStrategy strategy = _deployLoopStrategy(
            wrappedToken, deployerAddress, swapper, ethOverUSDCconfig_4p5x
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
