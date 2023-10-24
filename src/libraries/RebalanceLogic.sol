// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { LoanLogic } from "./LoanLogic.sol";
import { USDWadMath } from "./math/USDWadMath.sol";
import { IPriceOracleGetter } from "@aave/contracts/interfaces/IPriceOracleGetter.sol";
import { ISwapper } from "../interfaces/ISwapper.sol";
<<<<<<< HEAD
import { StrategyAssets, LoanState } from "../types/DataTypes.sol";
import { IPriceOracleGetter } from "../interfaces/IPriceOracleGetter.sol";
=======
import { LendingPool, LoanState, StrategyAssets } from "../types/DataTypes.sol";
>>>>>>> 0e0c886 (build: remove unrequired mocks, replace previous namings | WIP)

/// @title RebalanceLogic
/// @notice Contains all logic required for rebalancing
library RebalanceLogic {
    using USDWadMath for uint256;

    /// @dev ONE in USD scale and in TOKEN scale
    uint256 internal constant ONE_USD = 1e8;
    uint256 internal constant ONE_TOKEN = USDWadMath.WAD;

    /// @notice performs all operations necessary to rebalance the loan state of the strategy upwards
    /// @dev note that the current collateral/debt values are expected to be given in underlying value (USD)
    /// @param pool lending pool data
    /// @param assets addresses of collateral and borrow assets
    /// @param loanState the strategy loan state information (collateralized asset, borrowed asset, current collateral, current debt)
    /// @param targetCR target value of collateral ratio to reach
    /// @param oracle aave oracle
    /// @param swapper address of Swapper contract
    /// @return ratio value of collateral ratio after rebalance
    function rebalanceUp(
        LendingPool memory pool,
        StrategyAssets memory assets,
        LoanState memory loanState,
        uint256 targetRatio,
        IPriceOracleGetter oracle,
        ISwapper swapper
    ) external returns (uint256 ratio) {
        // current collateral ratio
        ratio = _collateralRatioUSD(loanState.collateralUSD, loanState.debtUSD);

        uint256 debtPriceInUSD = oracle.getAssetPrice(address(assets.debt));

        // get offset caused by DEX fees + slippage
        uint256 offsetFactor = swapper.offsetFactor(address(assets.debt), address(assets.collateral));

        do {
            // debt needed to reach max LTV
            uint256 debtAmount = loanState.maxBorrowAmount;

            // check if borrowing up to max LTV leads to smaller than  target collateral ratio, and adjust debtAmount if so
            if (
                _collateralRatioUSD(
                    loanState.collateralUSD + _offsetUSDAmountDown(debtAmount, offsetFactor),
                    loanState.debtUSD + debtAmount
                ) < targetCR
            ) {
                // calculate amount of debt needed to reach target collateral
                // offSetFactor < targetCR by default/design
                debtAmount = (loanState.collateralUSD - targetCR.usdMul(loanState.debtUSD)).usdDiv(
                    targetCR - (ONE_USD - offsetFactor)
                );
            }

            // convert debtAmount from USD to a borrowAsset amount
            uint256 debtAmountAsset = _convertUSDToAsset(debtAmount, debtPriceInUSD);

            // borrow assets from AaveV3 pool
            LoanLogic.borrow(pool, assets.debt, debtAmountAsset);

            // approve swapper contract to swap asset
            assets.debt.approve(address(swapper), debtAmountAsset);

            // exchange debtAmountAsset of debt tokens for collateral tokens
            uint256 collateralAmountAsset = swapper.swap(
                address(assets.debt),
                address(assets.collateral),
                debtAmountAsset,
                payable(address(this))
            );

            // collateralize assets in AaveV3 pool
            loanState = LoanLogic.supply(pool, assets.collateral, collateralAmountAsset);

            // update collateral ratio value
            ratio = _collateralRatioUSD(loanState.collateralUSD, loanState.debtUSD);
        } while (ratio > targetCR);
    }

    /// @notice performs all operations necessary to rebalance the loan state of the strategy downwards
    /// @dev note that the current collateral/debt values are expected to be given in underlying value (USD)
    /// @param pool lending pool data
    /// @param assets addresses of collateral and borrow assets
    /// @param loanState the strategy loan state information (collateralized asset, borrowed asset, current collateral, current debt)
    /// @param targetCR target value of collateral ratio to reach
    /// @param oracle aave oracle
    /// @param swapper address of Swapper contract
    /// @return ratio value of collateral ratio after rebalance
    function rebalanceDown(
        LendingPool memory pool,
        StrategyAssets memory assets,
        LoanState memory loanState,
        uint256 targetCR,
        IPriceOracleGetter oracle,
        ISwapper swapper
    ) external returns (uint256 ratio) {
        // current collateral ratio
        ratio = _collateralRatioUSD(loanState.collateralUSD, loanState.debtUSD);

        uint256 collateralUSDPrice = oracle.getAssetPrice(address(assets.collateral));

        // get offset caused by DEX fees + slippage
        uint256 offsetFactor = swapper.offsetFactor(address(assets.collateral), address(assets.debt));

        do {
            // maximum amount of collateral to not jeopardize loan health
            uint256 collateralAmount = loanState.maxWithdrawAmount;

            // handle cases where debt is less than maxWithdrawAmount possible
            if(loanState.debtUSD < loanState.maxWithdrawAmount) {
                collateralAmount = loanState.debtUSD;
            }

            // check if repaying max collateral will lead to the collateralRatio being more than target, and adjust
            // collateralAmount if so
            if (
                _collateralRatioUSD(
                    loanState.collateralUSD - collateralAmount,
                    loanState.debtUSD - _offsetUSDAmountDown(collateralAmount, offsetFactor)
                ) > targetCR
            ) {
                collateralAmount = (targetCR.usdMul(loanState.debtUSD) - loanState.collateralUSD).usdDiv(
                    targetCR.usdMul(ONE_USD - offsetFactor) - ONE_USD
                );
            }

            uint256 collateralAmountAsset = _convertUSDToAsset(collateralAmount, collateralUSDPrice);

            // withdraw collateral tokens from Aave pool
            LoanLogic.withdraw(pool, assets.collateral, collateralAmountAsset);

            // approve swapper contract to swap asset
            assets.collateral.approve(address(swapper), collateralAmountAsset);

            // exchange collateralAmount of collateral tokens for debt tokens
            uint256 debtAmount = swapper.swap(
                address(assets.collateral),
                address(assets.debt),
                collateralAmountAsset,
                payable(address(this))
            );

            // repay debt to AaveV3 pool
            loanState = LoanLogic.repay(pool, assets.debt, debtAmount);

            // update collateral ratio value
            ratio = _collateralRatioUSD(loanState.collateralUSD, loanState.debtUSD);
        } while (ratio < targetCR);
    }

    /// @notice helper function to offset amounts by a USD percentage downwards
    /// @param a amount to offset
    /// @param usdOffset offset as a number between 0 -  ONE_USD
    function _offsetUSDAmountDown(uint256 a, uint256 usdOffset) internal pure returns (uint256 amount) {
        amount = (a * (ONE_USD - usdOffset)) / ONE_USD;
    }

    /// @notice helper function to calculate collateral ratio
    /// @param collateralUSD collateral value in USD
    /// @param debtUSD debt valut in USD
    /// @return ratio collateral ratio value
    function _collateralRatioUSD(uint256 collateralUSD, uint256 debtUSD) internal pure returns (uint256 ratio) {
        ratio = debtUSD != 0 ? collateralUSD.usdDiv(debtUSD) : 0;
    }

    /// @notice converts a asset amount to its usd value
    /// @param assetAmount amount of asset
    /// @param priceInUSD price of asset in USD
    /// @return usdAmount amount of USD after conversion
    function _convertAssetToUSD(uint256 assetAmount, uint256 priceInUSD) internal pure returns (uint256 usdAmount) {
        usdAmount = USDWadMath.wadToUSD(((USDWadMath.usdToWad(priceInUSD)).wadMul(assetAmount)));
    }

    /// @notice converts a USD amount to its token value
    /// @param usdAmount amount of USD
    /// @param priceInUSD price of asset in USD
    /// @return assetAmount amount of asset after conversion
    function _convertUSDToAsset(uint256 usdAmount, uint256 priceInUSD) internal pure returns (uint256 assetAmount) {
        assetAmount = (usdAmount / priceInUSD);
    }
}
