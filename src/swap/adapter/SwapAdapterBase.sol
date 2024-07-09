// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { ISwapAdapter } from "../../interfaces/ISwapAdapter.sol";

/// @title SwapAdapterBase
/// @notice Base adapter contract for all swap adapters
/// @dev should be inherited and overridden by all SwapAdapter implementations
abstract contract SwapAdapterBase is AccessControl, ISwapAdapter {
    /// @dev role which can deposit to this contract to wrap underlying token
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev role which can call `executeSwap`
    bytes32 public constant SWAPPER_ROLE = keccak256("SWAPPER_ROLE");

    /// @notice swaps a given amount of a token to another token, sending the final amount to the beneficiary
    /// @param from address of token to swap from
    /// @param to address of token to swap to
    /// @param fromAmount amount of from token to swap
    /// @param beneficiary receiver of final to token amount
    /// @return toAmount amount of to token returned from swapping
    function _executeSwap(
        IERC20 from,
        IERC20 to,
        uint256 fromAmount,
        address payable beneficiary
    ) internal virtual returns (uint256 toAmount) {
        // override with adapter specific swap logic
    }
}
