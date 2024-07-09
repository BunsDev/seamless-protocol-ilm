// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

import { IAccessControl } from
    "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { ISwapAdapter } from "../../../src/interfaces/ISwapAdapter.sol";
import { ISwapper } from "../../../src/interfaces/ISwapper.sol";
import { IWrappedERC20PermissionedDeposit } from
    "../../../src/interfaces/IWrappedERC20PermissionedDeposit.sol";
import { UniversalAerodromeAdapter } from
    "../../../src/swap/adapter/UniversalAerodromeAdapter.sol";

import { BaseMainnetConstants } from "../config/BaseMainnetConstants.sol";
import { DeployHelperLib } from "../DeployHelperLib.sol";

/// @dev the script requires that this address has the `MANAGER_ROLE` on the `UniversalAerodromeAdapter`
/// and the `Swapper`
contract DeployUniversalAerodromeAdapterGuardianPayload is
    BaseMainnetConstants
{
    error NotAuthorized();

    int24 TICK_SPACING_WETH_USDC = 100;
    int24 TICK_SPACING_WETH_WSTETH = 1;

    function run(
        UniversalAerodromeAdapter universalAerodromeAdapter,
        address wrappedTokenAdapter
    ) external {
        if (
            msg.sender != SEAMLESS_COMMUNITY_MULTISIG
                && msg.sender != SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS
        ) {
            revert NotAuthorized();
        }

        _constructAndSetPaths(
            universalAerodromeAdapter,
            BASE_MAINNET_USDC,
            BASE_MAINNET_WETH,
            TICK_SPACING_WETH_USDC
        );
        _constructAndSetPaths(
            universalAerodromeAdapter,
            BASE_MAINNET_SEAMLESS_WRAPPED_WETH,
            BASE_MAINNET_SEAMLESS_WRAPPED_WSTETH,
            TICK_SPACING_WETH_WSTETH
        );

        DeployHelperLib._setSwapperRouteBetweenWrappedAndToken(
            ISwapper(SWAPPER),
            IWrappedERC20PermissionedDeposit(
                BASE_MAINNET_SEAMLESS_WRAPPED_WSTETH
            ),
            IERC20(BASE_MAINNET_WETH),
            ISwapAdapter(wrappedTokenAdapter),
            universalAerodromeAdapter,
            10000 // 0.01 % - value is set to 100 / 1000000 which is pool fee at time of deployment
        );

        DeployHelperLib._setSwapperRouteBetweenWrappedAndToken(
            ISwapper(SWAPPER),
            IWrappedERC20PermissionedDeposit(BASE_MAINNET_SEAMLESS_WRAPPED_WETH),
            IERC20(BASE_MAINNET_USDC),
            ISwapAdapter(wrappedTokenAdapter),
            universalAerodromeAdapter,
            40000 // 0.04 % - value is set to 400 / 1000000 which is pool fee at time of deployment
        );

        bytes32 MANAGER_ROLE = keccak256("MANAGER_ROLE");
        IAccessControl(SWAPPER).renounceRole(MANAGER_ROLE, address(this));
        universalAerodromeAdapter.renounceRole(MANAGER_ROLE, address(this));
    }

    function _constructAndSetPaths(
        UniversalAerodromeAdapter adapter,
        address tokenA,
        address tokenB,
        int24 tickSpacing
    ) internal {
        address[] memory aToB = new address[](2);
        address[] memory bToA = new address[](2);
        int24[] memory tickSpacings = new int24[](1);

        aToB[0] = tokenA;
        aToB[1] = tokenB;
        bToA[0] = tokenB;
        bToA[1] = tokenA;
        tickSpacings[0] = tickSpacing;

        adapter.setPath(aToB, tickSpacings);
        adapter.setPath(bToA, tickSpacings);
    }
}
