// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

contract MockEACAggregatorProxy {
    function latestAnswer() external pure returns (int256) {
        return 1e8;
    }
}
