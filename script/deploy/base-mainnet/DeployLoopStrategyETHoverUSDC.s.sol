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

contract LoopStrategyETHoverUSDCConfig is BaseMainnetConstants {
    // wrapped WETH
    WrappedERC20PermissionedDeposit public wrappedToken =
        WrappedERC20PermissionedDeposit(BASE_MAINNET_SEAMLESS_WRAPPED_WETH);

    uint256 public assetsCap = 50 ether; // TODO: add assets cap

    uint256 public maxSlippageOnRebalance = 1_000000; // 1%

    LoopStrategyConfig public ethOverUSDCconfig = LoopStrategyConfig({
        // WETH address
        underlyingTokenAddress: BASE_MAINNET_WETH,
        // ETH-USD oracle
        underlyingTokenOracle: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
        strategyERC20Config: ERC20Config({
            name: "Seamless ILM 1.5x Loop ETH/USDC",
            symbol: "ilm-ETH/USDC-1.5xloop"
        }),
        wrappedTokenERC20Config: ERC20Config("", ""), // empty, not used
        wrappedTokenReserveConfig: ReserveConfig(
            address(0), "", "", "", "", "", "", 0, 0, 0
        ), // empty, not used
        collateralRatioConfig: CollateralRatioConfig({
            collateralRatioTargets: CollateralRatio({
                target: USDWadRayMath.usdDiv(300, 100), // 3 (1.5x)
                minForRebalance: USDWadRayMath.usdDiv(255, 100), // 2.55 (-15%) (1.645x)
                maxForRebalance: USDWadRayMath.usdDiv(345, 100), // 3.45 (+15%) (1.408x)
                maxForDepositRebalance: USDWadRayMath.usdDiv(150, 50), // = target
                minForWithdrawRebalance: USDWadRayMath.usdDiv(150, 50) // = target
             }),
            ratioMargin: 1, // 0.000001% ratio margin
            maxIterations: 20
        }),
        swapperConfig: SwapperConfig({
            swapperOffsetFactor: 300000, // 0.3 %
            swapperOffsetDeviation: 0 // not used
         }),
        debtAsset: BASE_MAINNET_USDC
    });
}

contract DeployLoopStrategyETHoverUSDC is
    Script,
    DeployHelper,
    LoopStrategyETHoverUSDCConfig
{
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        Swapper swapper = Swapper(SWAPPER);

        LoopStrategy strategy = _deployLoopStrategy(
            wrappedToken, deployerAddress, swapper, ethOverUSDCconfig
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

        address guardianPayload = address(
            new DeployLoopStrategyETHoverUSDCGuardianPayload(
                ILoopStrategy(strategy),
                ethOverUSDCconfig.swapperConfig.swapperOffsetFactor
            )
        );

        _logAddress("GuardianPayloadContract", guardianPayload);

        vm.stopBroadcast();
    }

    function _grantRoles(IAccessControl accessContract, bytes32 role)
        internal
    {
        accessContract.grantRole(role, SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS);
        accessContract.grantRole(role, SEAMLESS_COMMUNITY_MULTISIG);
    }
}

contract DeployLoopStrategyETHoverUSDCGuardianPayload is
    BaseMainnetConstants
{
    ILoopStrategy public immutable strategy;
    uint256 public immutable swapperOffsetFactor;

    constructor(ILoopStrategy _strategy, uint256 _swapperOffsetFactor) {
        strategy = _strategy;
        swapperOffsetFactor = _swapperOffsetFactor;
    }

    function run() external {
        StrategyAssets memory strategyAssets = strategy.getAssets();

        IWrappedERC20PermissionedDeposit wrappedToken =
            IWrappedERC20PermissionedDeposit(address(strategyAssets.collateral));
        IWrappedTokenAdapter wrappedTokenAdapter =
            IWrappedTokenAdapter(WRAPPED_TOKEN_ADAPTER);

        IAccessControl(address(wrappedToken)).grantRole(
            wrappedToken.DEPOSITOR_ROLE(), address(strategy)
        );
        IAccessControl(address(wrappedToken)).grantRole(
            wrappedToken.DEPOSITOR_ROLE(), address(wrappedTokenAdapter)
        );

        wrappedTokenAdapter.setWrapper(
            wrappedToken.underlying(),
            IERC20(address(wrappedToken)),
            wrappedToken
        );

        DeployHelperLib._setAerodromeAdapterRoutes(
            IAerodromeAdapter(AERODROME_ADAPTER),
            strategyAssets.collateral,
            strategyAssets.debt,
            AERODROME_FACTORY
        );

        DeployHelperLib._setSwapperRouteBetweenWrappedAndToken(
            ISwapper(SWAPPER),
            wrappedToken,
            strategyAssets.debt,
            ISwapAdapter(address(wrappedTokenAdapter)),
            ISwapAdapter(AERODROME_ADAPTER),
            swapperOffsetFactor
        );
    }
}
