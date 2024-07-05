// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.21;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { LoopStrategyTest } from "./LoopStrategy.t.sol";
import { IRewardsController } from
    "@aave-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import { RewardsDataTypes } from
    "@aave-periphery/contracts/rewards/libraries/RewardsDataTypes.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { MockAaveOracle } from "../mock/MockAaveOracle.sol";
import { MockTransferStrategy } from "../mock/MockTransferStrategy.sol";
import { ITransferStrategyBase } from
    "@aave-periphery/contracts/rewards/interfaces/ITransferStrategyBase.sol";
import { IEACAggregatorProxy } from
    "@aave-periphery/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import { IPoolConfigurator } from
    "@aave/contracts/interfaces/IPoolConfigurator.sol";
import { ConfiguratorInputTypes } from
    "@aave/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import { IAaveOracle } from "@aave/contracts/interfaces/IAaveOracle.sol";
import { IPool } from "@aave/contracts/interfaces/IPool.sol";
import { DataTypes } from
    "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import { RewardsHandler } from "./helpers/RewardsHandler.t.sol";
import { MockEACAggregatorProxy } from "../mock/MockEACAggregatorProxy.sol";
import { IPoolAddressesProvider } from
    "@aave/contracts/interfaces/IPoolAddressesProvider.sol";

contract LoopStrategyDepositTest is LoopStrategyTest {
    ERC20Mock public supplyToken = new ERC20Mock();
    ERC20Mock public rewardToken = new ERC20Mock();
    MockEACAggregatorProxy public aggregatorProxy;
    MockTransferStrategy public transferStrategy;

    address public sSupplyTokenAddress;
    RewardsHandler public rewardsHandler;

    uint88 public constant EMISSION_PER_SECOND = 1_000_000;

    function setUp() public override {
        super.setUp();

        _openLendingPoolMarket();

        aggregatorProxy = new MockEACAggregatorProxy();
        transferStrategy = new MockTransferStrategy();

        address emissionManager = REWARDS_CONTROLLER.getEmissionManager();

        vm.startPrank(emissionManager);

        RewardsDataTypes.RewardsConfigInput[] memory config =
            new RewardsDataTypes.RewardsConfigInput[](2);

        config[0] = _makeRewardsConfigInput(address(strategy));
        config[1] = _makeRewardsConfigInput(sSupplyTokenAddress);

        REWARDS_CONTROLLER.configureAssets(config);

        rewardsHandler = new RewardsHandler(
            address(strategy),
            address(POOL),
            address(REWARDS_CONTROLLER),
            address(rewardToken),
            address(supplyToken)
        );

        vm.stopPrank();

        vm.allowCheatcodes(address(rewardsHandler));

        // This is necessary so all deployed contracts in setUp are removed from the target contracts list
        targetContract(address(rewardsHandler));
    }

    function test_Deposit_OneUser() public {
        uint256 depositAmount = 3 ether;
        _depositFor(alice, depositAmount);

        uint256 timeToPass = 1 days;
        uint256 totalDistributedRewards = timeToPass * EMISSION_PER_SECOND;
        vm.warp(block.timestamp + timeToPass);

        address[] memory assets = new address[](1);
        assets[0] = address(strategy);
        uint256 userRewards = REWARDS_CONTROLLER.getUserRewards(
            assets, alice, address(rewardToken)
        );

        assertEq(userRewards, totalDistributedRewards - 1);
    }

    function test_HandleAction_notRevertingIfRewardsControllerNotSet() public {
        bytes32 INCENTIVES_CONTROLLER = keccak256("INCENTIVES_CONTROLLER");

        IPoolAddressesProvider addressesProvider =
            IPoolAddressesProvider(SEAMLESS_ADDRESS_PROVIDER_BASE_MAINNET);
        vm.prank(SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS);
        addressesProvider.setAddress(INCENTIVES_CONTROLLER, address(0));

        // this will call _handeAction which must not revert
        _depositFor(alice, 5 ether);
    }

    function invariant_LoopStrategyRewards_equalToPoolRewards() public {
        address[] memory actors = rewardsHandler.getActors();

        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];

            assertEq(
                _getUserRewards(address(strategy), actor),
                _getUserRewards(sSupplyTokenAddress, actor),
                "Rewards mismatch"
            );
        }
    }

    function _depositFor(address user, uint256 amount)
        internal
        override
        returns (uint256)
    {
        uint256 shares = super._depositFor(user, amount);

        deal(address(supplyToken), user, amount);

        vm.startPrank(user);
        supplyToken.approve(address(POOL), shares);
        POOL.supply(address(supplyToken), shares, user, 0);
        vm.stopPrank();

        return shares;
    }

    function _redeemFrom(address user, uint256 amount) internal {
        vm.startPrank(user);

        strategy.redeem(amount, user, user);
        POOL.withdraw(address(supplyToken), amount, user);

        vm.stopPrank();
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.startPrank(from);
        IERC20(sSupplyTokenAddress).transfer(to, amount);
        strategy.transfer(to, amount);
        vm.stopPrank();
    }

    function _openLendingPoolMarket() internal {
        vm.startPrank(SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS);

        address[] memory assets = new address[](1);
        assets[0] = address(supplyToken);

        address[] memory sources = new address[](1);
        sources[0] = address(aggregatorProxy);

        ConfiguratorInputTypes.InitReserveInput[] memory reserveConfig =
            new ConfiguratorInputTypes.InitReserveInput[](1);
        reserveConfig[0] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl: SEAMLESS_ATOKEN_IMPL,
            stableDebtTokenImpl: SEAMLESS_STABLE_DEBT_TOKEN_IMPL,
            variableDebtTokenImpl: SEAMLESS_VARIABLE_DEBT_TOKEN_IMPL,
            underlyingAssetDecimals: 18,
            interestRateStrategyAddress: SEAMLESS_CBETH_INTEREST_RATE_STRATEGY_ADDRESS,
            underlyingAsset: address(supplyToken),
            treasury: SEAMLESS_TREASURY,
            incentivesController: SEAMLESS_INCENTIVES_CONTROLLER,
            aTokenName: "A Token Name",
            aTokenSymbol: "A Token Symbol",
            variableDebtTokenName: "VD Token Name",
            variableDebtTokenSymbol: "VD Token Symbol",
            stableDebtTokenName: "SD Token Nname",
            stableDebtTokenSymbol: "SD Token Symbol",
            params: new bytes(0x1)
        });

        POOL_CONFIGURATOR.initReserves(reserveConfig);
        POOL_CONFIGURATOR.setSupplyCap(address(supplyToken), MAX_SUPPLY_CAP);
        AAVE_ORACLE.setAssetSources(assets, sources);

        DataTypes.ReserveData memory reserveData =
            POOL.getReserveData(address(supplyToken));
        sSupplyTokenAddress = reserveData.aTokenAddress;

        vm.stopPrank();
    }

    function _makeRewardsConfigInput(address asset)
        internal
        view
        returns (RewardsDataTypes.RewardsConfigInput memory)
    {
        return RewardsDataTypes.RewardsConfigInput({
            emissionPerSecond: EMISSION_PER_SECOND,
            totalSupply: 0,
            distributionEnd: type(uint32).max,
            asset: asset,
            reward: address(rewardToken),
            transferStrategy: ITransferStrategyBase(address(transferStrategy)),
            rewardOracle: IEACAggregatorProxy(address(aggregatorProxy))
        });
    }

    function _getUserRewards(address asset, address user)
        internal
        view
        returns (uint256)
    {
        address[] memory assets = new address[](1);
        assets[0] = asset;

        return REWARDS_CONTROLLER.getUserRewards(
            assets, user, address(rewardToken)
        );
    }
}
