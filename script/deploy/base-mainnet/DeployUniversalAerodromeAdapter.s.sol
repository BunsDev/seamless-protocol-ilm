// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";

import { UniversalAerodromeAdapter } from
    "../../../src/swap/adapter/UniversalAerodromeAdapter.sol";

import { DeployHelper } from "../DeployHelper.s.sol";
import { DeployUniversalAerodromeAdapterGuardianPayload } from
    "./DeployUniversalAerodromeAdapterGuardianPayload.sol";

contract DeployUniversalAerodromeAdapter is Script, DeployHelper {
    function run(address initialAdmin) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        UniversalAerodromeAdapter adapter =
            _deployUniversalAerodromeAdapter(deployerAddress);

        address payload =
            address(new DeployUniversalAerodromeAdapterGuardianPayload());

        _logAddress(
            "DeployUniversalAerodromeAdapterGuardianPayload: ", address(payload)
        );

        vm.stopBroadcast();
    }
}
