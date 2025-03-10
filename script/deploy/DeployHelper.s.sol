// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { BaseMainnetConstants } from "./config/BaseMainnetConstants.sol";
import {
    LoopStrategyConfig,
    ERC20Config,
    ReserveConfig,
    CollateralRatioConfig
} from "./config/LoopStrategyConfig.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC1967Proxy } from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ISwapper, Swapper } from "../../src/swap/Swapper.sol";
import { IPool } from "@aave/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider } from
    "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPriceOracleGetter } from
    "@aave/contracts/interfaces/IPriceOracleGetter.sol";
import { IPoolConfigurator } from
    "@aave/contracts/interfaces/IPoolConfigurator.sol";
import { IAaveOracle } from "@aave/contracts/interfaces/IAaveOracle.sol";
import { ConfiguratorInputTypes } from
    "@aave/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import { IRouter } from "../../src/vendor/aerodrome/IRouter.sol";
import {
    WrappedERC20PermissionedDeposit,
    IWrappedERC20PermissionedDeposit
} from "../../src/tokens/WrappedERC20PermissionedDeposit.sol";
import {
    LendingPool,
    LoanState,
    StrategyAssets,
    CollateralRatio,
    Step
} from "../../src/types/DataTypes.sol";
import { LoopStrategy, ILoopStrategy } from "../../src/LoopStrategy.sol";
import {
    WrappedTokenAdapter,
    IWrappedTokenAdapter
} from "../../src/swap/adapter/WrappedTokenAdapter.sol";
import {
    AerodromeAdapter,
    IAerodromeAdapter
} from "../../src/swap/adapter/AerodromeAdapter.sol";
import {
    UniversalAerodromeAdapter,
    IUniversalAerodromeAdapter
} from "../../src/swap/adapter/UniversalAerodromeAdapter.sol";
import { ISwapAdapter } from "../../src/interfaces/ISwapAdapter.sol";
import { DeployHelperLib } from "./DeployHelperLib.sol";
import "forge-std/console.sol";

/// @title DeployHelper
/// @notice This contract contains functions to deploy and setup ILM LoopStrategy contracts
contract DeployHelper is BaseMainnetConstants {
    IERC20 public constant WETH = IERC20(BASE_MAINNET_WETH);
    IPoolAddressesProvider public constant poolAddressesProvider =
        IPoolAddressesProvider(SEAMLESS_ADDRESS_PROVIDER_BASE_MAINNET);

    /// @dev logs the contract address on the console output
    function _logAddress(string memory _name, address _address) internal view {
        console.log("%s: %s", _name, _address);
    }

    /// @dev deploys the WrappedToken contract
    /// @param initialAdmin initial DEFAULT_ADMIN role on the contract
    /// @param wrappedTokenERC20Config ERC20 configuration of the wrapped token
    /// @param underlyingToken address of the underlying token which is wrapped
    /// @return wrappedToken address of the deployed WrappedToken contract
    function _deployWrappedToken(
        address initialAdmin,
        ERC20Config memory wrappedTokenERC20Config,
        IERC20 underlyingToken
    ) internal returns (WrappedERC20PermissionedDeposit wrappedToken) {
        wrappedToken = new WrappedERC20PermissionedDeposit(
            wrappedTokenERC20Config.name,
            wrappedTokenERC20Config.symbol,
            underlyingToken,
            initialAdmin
        );

        _logAddress("WrappedToken", address(wrappedToken));
    }

    /// @dev set up the wrapped token on the lending pool
    /// @dev requires from the caller to have ACL_ADMIN or POOL_ADMIN role on the lending pool
    /// @param wrappedToken address of the WrappedToken contract
    /// @param wrappedTokenReserveConfig all configuration parameters for setting up the token as reserve on the lending pool
    /// @param underlyingTokenOracle address of the price oracle for the wrapped token (it's underlying token)
    function _setupWrappedToken(
        WrappedERC20PermissionedDeposit wrappedToken,
        ReserveConfig memory wrappedTokenReserveConfig,
        address underlyingTokenOracle
    ) internal {
        ConfiguratorInputTypes.InitReserveInput[] memory initReserveInputs =
            new ConfiguratorInputTypes.InitReserveInput[](1);

        initReserveInputs[0] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl: SEAMLESS_ATOKEN_IMPL,
            stableDebtTokenImpl: SEAMLESS_STABLE_DEBT_TOKEN_IMPL,
            variableDebtTokenImpl: SEAMLESS_VARIABLE_DEBT_TOKEN_IMPL,
            underlyingAssetDecimals: wrappedToken.decimals(),
            interestRateStrategyAddress: wrappedTokenReserveConfig
                .interestRateStrategyAddress,
            underlyingAsset: address(wrappedToken),
            treasury: SEAMLESS_TREASURY,
            incentivesController: SEAMLESS_INCENTIVES_CONTROLLER,
            aTokenName: wrappedTokenReserveConfig.aTokenName,
            aTokenSymbol: wrappedTokenReserveConfig.aTokenSymbol,
            variableDebtTokenName: wrappedTokenReserveConfig.variableDebtTokenName,
            variableDebtTokenSymbol: wrappedTokenReserveConfig
                .variableDebtTokenSymbol,
            stableDebtTokenName: wrappedTokenReserveConfig.stableDebtTokenName,
            stableDebtTokenSymbol: wrappedTokenReserveConfig.stableDebtTokenSymbol,
            params: bytes("")
        });

        IPoolConfigurator poolConfigurator =
            IPoolConfigurator(poolAddressesProvider.getPoolConfigurator());

        poolConfigurator.initReserves(initReserveInputs);

        poolConfigurator.configureReserveAsCollateral(
            address(wrappedToken),
            wrappedTokenReserveConfig.ltv,
            wrappedTokenReserveConfig.liquidationTrashold,
            wrappedTokenReserveConfig.liquidationBonus
        );

        address[] memory assets = new address[](1);
        address[] memory sources = new address[](1);
        assets[0] = address(wrappedToken);
        sources[0] = underlyingTokenOracle;

        IAaveOracle(poolAddressesProvider.getPriceOracle()).setAssetSources(
            assets, sources
        );
    }

    /// @dev deploys the Swapper contract
    /// @dev requires for the caller to be the same address as `initialAdmin`
    /// @param initialAdmin initial DEFAULT_ADMIN, MANAGER_ROLE and UPGRADER_ROLE roles on the contract
    /// @param swapperOffsetDeviation maximal offset deviation of the price from the offsetFactor (in percent)
    /// @return swapper address of the deployed Swapper contract
    function _deploySwapper(
        address initialAdmin,
        uint256 swapperOffsetDeviation
    ) internal returns (Swapper swapper) {
        Swapper swapperImplementation = new Swapper();
        ERC1967Proxy swapperProxy = new ERC1967Proxy(
            address(swapperImplementation),
            abi.encodeWithSelector(
                Swapper.Swapper_init.selector,
                initialAdmin,
                IPriceOracleGetter(poolAddressesProvider.getPriceOracle()),
                swapperOffsetDeviation
            )
        );

        swapper = Swapper(address(swapperProxy));

        swapper.grantRole(swapper.MANAGER_ROLE(), initialAdmin);
        swapper.grantRole(swapper.UPGRADER_ROLE(), initialAdmin);

        _logAddress("Swapper", address(swapper));
    }

    /// @dev deploys SwapAdapters (WrappedTokenAdapter and AerodromeAdapter) and set up those contracts
    /// @dev requires for the caller to be the same address as `initialAdmin`
    /// @param swapper address of the Swapper contract
    /// @param wrappedToken address of the WrappedToken contract
    /// @param initialAdmin initial Owner role on the contracts
    /// @return wrappedTokenAdapter address of the deployed WrappedTokenAdapter contract
    /// @return aerodromeAdapter address of the deployed AerodromeAdapter contract
    function _deploySwapAdapters(
        Swapper swapper,
        WrappedERC20PermissionedDeposit wrappedToken,
        address initialAdmin
    )
        internal
        returns (
            WrappedTokenAdapter wrappedTokenAdapter,
            AerodromeAdapter aerodromeAdapter
        )
    {
        IERC20 underlyingToken = wrappedToken.underlying();

        // WrappedToken Adapter
        wrappedTokenAdapter =
            new WrappedTokenAdapter(initialAdmin, address(swapper));
        wrappedTokenAdapter.setWrapper(
            underlyingToken,
            IERC20(address(wrappedToken)),
            IWrappedERC20PermissionedDeposit(wrappedToken)
        );

        // UnderlyingToken <-> WETH Aerodrome Adapter
        aerodromeAdapter = new AerodromeAdapter(
            initialAdmin, AERODROME_ROUTER, AERODROME_FACTORY, address(swapper)
        );

        DeployHelperLib._setAerodromeAdapterRoutes(
            aerodromeAdapter, underlyingToken, WETH, AERODROME_FACTORY
        );

        _logAddress("WrappedTokenAdapter", address(wrappedTokenAdapter));
        _logAddress("AerodromeAdapter", address(aerodromeAdapter));
    }

    /// @notice deploys a wrapped token adapter and an aerodrome adapter
    /// @param swapper Swapper contract
    /// @param initialAdmin address of initial admin
    /// @return wrappedTokenAdapter newly deployed wrapped token adapter
    /// @return aerodromeAdapter newly deploy aerodrome adapter
    function _deploySwapAdapters(Swapper swapper, address initialAdmin)
        internal
        returns (
            WrappedTokenAdapter wrappedTokenAdapter,
            AerodromeAdapter aerodromeAdapter
        )
    {
        // WrappedToken Adapter
        wrappedTokenAdapter =
            new WrappedTokenAdapter(initialAdmin, address(swapper));
        // UnderlyingToken <-> WETH Aerodrome Adapter
        aerodromeAdapter = new AerodromeAdapter(
            initialAdmin, AERODROME_ROUTER, AERODROME_FACTORY, address(swapper)
        );

        _logAddress("WrappedTokenAdapter", address(wrappedTokenAdapter));
        _logAddress("AerodromeAdapter", address(aerodromeAdapter));
    }

    /// @notice deploys a wrapped token adapter
    /// @param swapper Swapper contract
    /// @param initialAdmin address of initial admin
    /// @return wrappedTokenAdapter newly deployed wrapped token adapter
    function _deployWrappedTokenAdapter(Swapper swapper, address initialAdmin)
        internal
        returns (WrappedTokenAdapter wrappedTokenAdapter)
    {
        // WrappedToken Adapter
        wrappedTokenAdapter =
            new WrappedTokenAdapter(initialAdmin, address(swapper));

        _logAddress("WrappedTokenAdapter", address(wrappedTokenAdapter));
    }

    /// @notice deploys a UniversalAerodromeAdapter instance
    /// @param initialAdmin address to be first default admin
    /// @return adapter deployed UniversalAerodromeAdapter
    function _deployUniversalAerodromeAdapter(address initialAdmin)
        internal
        returns (UniversalAerodromeAdapter adapter)
    {
        adapter = new UniversalAerodromeAdapter(
            initialAdmin, UNIVERSAL_ROUTER, SWAPPER
        );

        _logAddress("UniversalAerodromeAdapter: ", address(adapter));
    }

    /// @dev set up the routes for swapping (wrappedToken <-> WETH)
    /// @dev requires for the caller to have MANAGER_ROLE on the Swapper contract
    /// @param swapper address of the Swapper contract
    /// @param wrappedToken address of the WrappedToken contract
    /// @param wrappedTokenAdapter address of the WrappedTokenAdapter contract
    /// @param aerodromeAdapter address of the AerodromeAdapter contract
    /// @param swapperOffsetFactor offsetFactor for this swapping routes
    function _setupSwapperRoutes(
        Swapper swapper,
        WrappedERC20PermissionedDeposit wrappedToken,
        WrappedTokenAdapter wrappedTokenAdapter,
        AerodromeAdapter aerodromeAdapter,
        uint256 swapperOffsetFactor
    ) internal {
        DeployHelperLib._setSwapperRouteBetweenWrappedAndToken(
            swapper,
            wrappedToken,
            WETH,
            ISwapAdapter(address(wrappedTokenAdapter)),
            ISwapAdapter(address(aerodromeAdapter)),
            swapperOffsetFactor
        );
    }

    /// @dev deploys LoopStrategy contract
    /// @dev requires for the caller to be the same address as `initialAdmin`
    /// @param wrappedToken address of the WrappedToken contract
    /// @param initialAdmin initial DEFAULT_ADMIN, MANAGER_ROLE, UPGRADER_ROLE and PAUSER_ROLE roles on the contract
    /// @param swapper address of the Swapper contract
    /// @param config configuration paramteres for the LoopStrategy contract
    /// @return strategy address of the deployed LoopStrategy contract
    function _deployLoopStrategy(
        WrappedERC20PermissionedDeposit wrappedToken,
        address initialAdmin,
        ISwapper swapper,
        LoopStrategyConfig memory config
    ) internal returns (LoopStrategy strategy) {
        StrategyAssets memory strategyAssets = StrategyAssets({
            underlying: IERC20(config.underlyingTokenAddress),
            collateral: IERC20(address(wrappedToken)),
            debt: IERC20(config.debtAsset)
        });

        LoopStrategy strategyImplementation = new LoopStrategy();

        ERC1967Proxy strategyProxy = new ERC1967Proxy(
            address(strategyImplementation),
            abi.encodeWithSelector(
                LoopStrategy.LoopStrategy_init.selector,
                config.strategyERC20Config.name,
                config.strategyERC20Config.symbol,
                initialAdmin,
                strategyAssets,
                config.collateralRatioConfig.collateralRatioTargets,
                poolAddressesProvider,
                IPriceOracleGetter(poolAddressesProvider.getPriceOracle()),
                swapper,
                config.collateralRatioConfig.ratioMargin,
                config.collateralRatioConfig.maxIterations
            )
        );
        strategy = LoopStrategy(address(strategyProxy));

        strategy.grantRole(strategy.MANAGER_ROLE(), initialAdmin);

        _logAddress("Strategy", address(strategy));
    }

    /// @dev deploys a new LoopStrategy contract implementation
    function _deployLoopStrategyImplementation() internal {
        LoopStrategy strategyImplementation = new LoopStrategy();

        _logAddress("Strategy Implementation", address(strategyImplementation));
    }

    /// @dev deploys a new Swapper contract implementation
    function _deploySwapperImplementation() internal {
        Swapper swapperImplementation = new Swapper();

        _logAddress("Swapper Implementation", address(swapperImplementation));
    }

    /// @dev set deposit permissions to the LoopStrategy and WrappedTokenAdapter contracts
    /// @dev requires caller to have MANAGER_ROLE on the WrappedToken contract
    /// @param wrappedToken address of the WrappedTokenContract
    /// @param wrappedTokenAdapter address of the WrappedTokenAdapter contract
    /// @param strategy address of the LoopStrategy contract
    function _setupWrappedTokenRoles(
        WrappedERC20PermissionedDeposit wrappedToken,
        address wrappedTokenAdapter,
        address strategy
    ) internal {
        wrappedToken.grantRole(wrappedToken.DEPOSITOR_ROLE(), strategy);
        wrappedToken.grantRole(
            wrappedToken.DEPOSITOR_ROLE(), wrappedTokenAdapter
        );
    }

    /// @dev set STRATEGY_ROLE to the LoopStrategy contract
    /// @dev requires caller to have MANAGER_ROLE on the Swapper contract
    /// @param swapper address of the Swapper contract
    /// @param strategy address of the LoopStrategy contract
    function _setupSwapperRoles(Swapper swapper, LoopStrategy strategy)
        internal
    {
        swapper.grantRole(swapper.STRATEGY_ROLE(), address(strategy));
    }
}
