// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";

import { UniversalAerodromeAdapter } from
    "../../../src/swap/adapter/UniversalAerodromeAdapter.sol";
import { IAccessControl } from
    "@openzeppelin/contracts/access/IAccessControl.sol";
import { DeployHelper } from "../DeployHelper.s.sol";
import { DeployUniversalAerodromeAdapterGuardianPayload } from
    "./DeployUniversalAerodromeAdapterGuardianPayload.sol";

contract DeployUniversalAerodromeAdapter is Script, DeployHelper {
    int24 TICK_SPACING_WETH_USDC = 100;
    int24 TICK_SPACING_WETH_WSTETH = 1;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        UniversalAerodromeAdapter adapter =
            _deployUniversalAerodromeAdapter(deployerAddress);

        adapter.grantRole(adapter.MANAGER_ROLE(), deployerAddress);
        _grantRoles(adapter, adapter.MANAGER_ROLE());
        _grantRoles(adapter, adapter.DEFAULT_ADMIN_ROLE());

        _constructAndSetPaths(
            adapter,
            BASE_MAINNET_USDC,
            BASE_MAINNET_WETH,
            TICK_SPACING_WETH_USDC
        );
        _constructAndSetPaths(
            adapter,
            BASE_MAINNET_SEAMLESS_WRAPPED_WETH,
            BASE_MAINNET_SEAMLESS_WRAPPED_WSTETH,
            TICK_SPACING_WETH_WSTETH
        );

        adapter.renounceRole(adapter.MANAGER_ROLE(), deployerAddress);
        adapter.renounceRole(adapter.DEFAULT_ADMIN_ROLE(), deployerAddress);

        address payload =
            address(new DeployUniversalAerodromeAdapterGuardianPayload());

        _logAddress(
            "DeployUniversalAerodromeAdapterGuardianPayload: ", address(payload)
        );

        vm.stopBroadcast();
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

    function _grantRoles(IAccessControl accessContract, bytes32 role)
        internal
    {
        accessContract.grantRole(role, SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS);
        accessContract.grantRole(role, SEAMLESS_COMMUNITY_MULTISIG);
    }
}
