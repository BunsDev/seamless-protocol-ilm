// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

interface IScaledToken {
    /// @notice returns total supply of strategy shares
    /// @dev this function returns the same value as totalSupply
    /// @dev required so rewards controller can calculate rewards, it is used only from the rewards controller
    /// @return scaledTotalSupply total supply of strategy shares
    function scaledTotalSupply()
        external
        view
        returns (uint256 scaledTotalSupply);

    /// @notice returns balance of user and total supply
    /// @dev required so rewards controller can calculate rewards, it is used only from the rewards controller
    /// @param user address of user
    /// @return scaledBalance balance of user
    /// @return scaledTotalSupply total supply of strategy shares
    function getScaledUserBalanceAndSupply(address user)
        external
        view
        returns (uint256 scaledBalance, uint256 scaledTotalSupply);
}
