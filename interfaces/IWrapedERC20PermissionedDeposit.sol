// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

/// @title IWrapedERC20PermissionedDeposit
/// @notice interface for the Wrapper of ERC20 with permissioned deposit
/// @dev Wraps the underlying ERC20 contract and mints the same amount of a wrapped token. 
/// @dev Deposits are permissioned but withdrawals are open to any address.
interface IWrapedERC20PermissionedDeposit {
    /// @notice retruns the underlying token address
    function underlying() external view returns (address);

    /// @notice deposits underlying tokens and mint the same amount of wrapped tokens
    /// @param amount amount of the tokens to wrap, in wei
    /// @dev only permissioned depositors are allowed to deposit
    function deposit(uint256 amount) external;

    /// @notice burns amount of wrapped tokens and recieves back the underlying token
    /// @param amount amount of the tokens to withdraw, in wei
    function withdraw(uint256 amount) external;

    /// @notice function used to recover underlying tokens sent directly to this contract by mistake
    function recover() external;

    /// @notice gives or withdraws permission to deposit
    /// @param account account address to give/withdraw permission
    /// @param toSet flag set to true to give permission, or false to withdraw permission
    function setDepositPermission(address account, bool toSet) external;
}