// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.21;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IPool } from "@aave/contracts/interfaces/IPool.sol";
import { IRewardsController } from
    "@aave-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import { ILoopStrategy } from "../../../src/interfaces/ILoopStrategy.sol";
import { StrategyAssets } from "../../../src/types/DataTypes.sol";
import { DataTypes } from
    "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import { Test } from "forge-std/Test.sol";
import { TestConstants } from "../../config/TestConstants.sol";

contract RewardsHandler is Test, TestConstants {
    uint256 public constant MIN_REDEEM_AMOUNT = 1e7;

    ILoopStrategy public immutable strategy;
    IPool public immutable pool;
    IRewardsController public immutable rewardsController;
    IERC20 public immutable rewardToken;
    IERC20 public immutable supplyToken;
    IERC20 public immutable strategyUnderlying;

    address public sSupplyTokenAddress;
    address[] public actors;

    modifier useActor(uint256 actorIndexSeed) {
        address currentActor =
            actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(
        address _strategy,
        address _pool,
        address _rewardsController,
        address _rewardToken,
        address _supplyToken
    ) {
        strategy = ILoopStrategy(_strategy);
        pool = IPool(_pool);
        rewardsController = IRewardsController(_rewardsController);
        rewardToken = IERC20(_rewardToken);
        supplyToken = IERC20(_supplyToken);

        DataTypes.ReserveData memory reserveData =
            pool.getReserveData(address(supplyToken));
        sSupplyTokenAddress = reserveData.aTokenAddress;

        StrategyAssets memory strategyAssets = strategy.getAssets();
        strategyUnderlying = strategyAssets.underlying;

        actors.push(address(1));
        actors.push(address(2));
        actors.push(address(3));
    }

    function getActors() public view returns (address[] memory) {
        return actors;
    }

    function deposit(uint256 actorIndex, uint256 amount, uint8 timeToPass)
        public
        useActor(actorIndex)
    {
        amount = bound(amount, 1 ether, 3 ether);
        timeToPass = uint8(bound(uint256(timeToPass), 0, 100_000));

        (, address user,) = vm.readCallers();

        deal(address(strategyUnderlying), user, amount);

        strategyUnderlying.approve(address(strategy), amount);

        uint256 shares = strategy.deposit(amount, user);

        deal(address(supplyToken), user, shares);
        supplyToken.approve(address(pool), shares);
        pool.deposit(address(supplyToken), shares, user, 0);

        skip(timeToPass);
    }

    function withdraw(uint256 actorIndex, uint256 amount, uint8 timeToPass)
        public
        useActor(actorIndex)
    {
        timeToPass = uint8(bound(uint256(timeToPass), 0, 100_000));

        (, address user,) = vm.readCallers();

        if (strategy.balanceOf(user) <= MIN_REDEEM_AMOUNT) {
            return;
        }

        amount = bound(amount, MIN_REDEEM_AMOUNT, strategy.balanceOf(user));

        try strategy.redeem(amount, user, user) {
            pool.withdraw(address(supplyToken), amount, user);
            skip(timeToPass);
        } catch Error(string memory reason) {
            // if user redeems close to all shares from the strategy, it can revert with error '35'
            // issue itemId=70345890
            if (Strings.equal(reason, "35")) {
                assertApproxEqRel(
                    amount, strategy.totalSupply(), 0.00000001 * 1e18
                );
            } else {
                revert(reason);
            }
        }
    }

    function transfer(
        uint256 fromActorIndex,
        uint256 toActorIndex,
        uint256 amount,
        uint8 timeToPass
    ) public useActor(fromActorIndex) {
        toActorIndex = bound(toActorIndex, 0, actors.length - 1);
        timeToPass = uint8(bound(uint256(timeToPass), 0, 100_000));

        (, address fromUser,) = vm.readCallers();
        address toUser = actors[toActorIndex];

        if (strategy.balanceOf(fromUser) == 0) {
            return;
        }

        amount = bound(amount, 1, strategy.balanceOf(fromUser));

        strategy.transfer(toUser, amount);
        IERC20(sSupplyTokenAddress).transfer(toUser, amount);

        skip(timeToPass);
    }

    function claimAllRewards(
        uint256 fromActorIndex,
        uint256 toActorIndex,
        uint8 timeToPass
    ) public useActor(fromActorIndex) {
        toActorIndex = bound(toActorIndex, 0, actors.length - 1);
        timeToPass = uint8(bound(uint256(timeToPass), 0, 100_000));

        address toUser = actors[toActorIndex];

        address[] memory assets = new address[](1);
        assets[0] = address(strategy);

        (address[] memory rewardsList1, uint256[] memory claimedAmounts1) =
            REWARDS_CONTROLLER.claimAllRewards(assets, toUser);

        assets[0] = sSupplyTokenAddress;
        (address[] memory rewardsList2, uint256[] memory claimedAmounts2) =
            REWARDS_CONTROLLER.claimAllRewards(assets, toUser);

        assertEq(
            rewardsList1.length, rewardsList2.length, "Rewards length mismatch"
        );
        assertEq(
            claimedAmounts1.length,
            claimedAmounts2.length,
            "Claimed amounts length mismatch"
        );

        for (uint256 i = 0; i < rewardsList1.length; i++) {
            assertEq(rewardsList1[i], rewardsList2[i], "Rewards mismatch");
            assertEq(
                claimedAmounts1[i],
                claimedAmounts2[i],
                "Claimed amounts mismatch"
            );
        }

        skip(timeToPass);
    }
}
