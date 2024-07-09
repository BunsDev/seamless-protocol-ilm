// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";

import { IAccessControl } from
    "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { IWrappedERC20PermissionedDeposit } from
    "../../../src/interfaces/IWrappedERC20PermissionedDeposit.sol";
import { WrappedTokenAdapter } from
    "../../../src/swap/adapter/WrappedTokenAdapter.sol";
import { Swapper } from "../../../src/swap/Swapper.sol";

import { BaseMainnetConstants } from "../config/BaseMainnetConstants.sol";
import { DeployHelper } from "../DeployHelper.s.sol";

contract DeployWrappedTokenAdapter is Script, DeployHelper {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        WrappedTokenAdapter adapter =
            _deployWrappedTokenAdapter(Swapper(SWAPPER), deployerAddress);

        adapter.grantRole(adapter.MANAGER_ROLE(), deployerAddress);
        _grantRoles(adapter, adapter.MANAGER_ROLE());
        _grantRoles(adapter, adapter.DEFAULT_ADMIN_ROLE());

        IWrappedERC20PermissionedDeposit wrappedWSTETH =
        IWrappedERC20PermissionedDeposit(BASE_MAINNET_SEAMLESS_WRAPPED_WSTETH);
        IWrappedERC20PermissionedDeposit wrappedWETH =
            IWrappedERC20PermissionedDeposit(BASE_MAINNET_SEAMLESS_WRAPPED_WETH);

        adapter.setWrapper(
            wrappedWSTETH.underlying(),
            IERC20(address(wrappedWSTETH)),
            wrappedWSTETH
        );
        adapter.setWrapper(
            wrappedWETH.underlying(), IERC20(address(wrappedWETH)), wrappedWETH
        );

        adapter.renounceRole(adapter.MANAGER_ROLE(), deployerAddress);
        adapter.renounceRole(adapter.DEFAULT_ADMIN_ROLE(), deployerAddress);

        vm.stopBroadcast();
    }

    function _grantRoles(IAccessControl accessContract, bytes32 role)
        internal
    {
        accessContract.grantRole(role, SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS);
        accessContract.grantRole(role, SEAMLESS_COMMUNITY_MULTISIG);
    }
}
