// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Commands } from "../../vendor/aerodrome/Commands.sol";
import { IUniversalRouter } from "../../vendor/aerodrome/IUniversalRouter.sol";
import { IUniversalAerodromeAdapter } from
    "../../interfaces/IUniversalAerodromeAdapter.sol";
import { ISwapAdapter } from "../../interfaces/ISwapAdapter.sol";
import { SwapAdapterBase } from "./SwapAdapterBase.sol";

/// @title AerodromeAdapter
/// @notice Adapter contract for executing swaps on aerodrome
contract UniversalAerodromeAdapter is
    SwapAdapterBase,
    IUniversalAerodromeAdapter
{
    using SafeERC20 for IERC20;

    /// @dev thrown when the token array does not have a length 1 greater that
    /// tickspacings array in `setPath` call
    error IncorrectArrayLengths();

    address public immutable UNIVERSAL_ROUTER;

    mapping(IERC20 from => mapping(IERC20 to => bytes path)) public swapPaths;

    constructor(
        address initialAdmin,
        address universalRouter,
        address swapper
    ) {
        UNIVERSAL_ROUTER = universalRouter;
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(SWAPPER_ROLE, swapper);
    }

    /// @inheritdoc ISwapAdapter
    function executeSwap(
        IERC20 from,
        IERC20 to,
        uint256 fromAmount,
        address payable beneficiary
    ) external onlyRole(SWAPPER_ROLE) returns (uint256 toAmount) {
        return _executeSwap(from, to, fromAmount, beneficiary);
    }

    /// @notice swaps a given amount of a token to another token, sending the final amount to the beneficiary
    /// @dev overridden internal _executeSwap function from SwapAdapterBase contract
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
    ) internal override returns (uint256 toAmount) {
        from.safeTransferFrom(msg.sender, address(this), fromAmount);

        from.forceApprove(UNIVERSAL_ROUTER, fromAmount);

        bytes[] memory inputs = new bytes[](1);

        inputs[0] =
            _encodeSlipstreamExactInSwap(beneficiary, from, to, fromAmount, 0);

        uint256 oldBalance = to.balanceOf(beneficiary);

        IUniversalRouter(UNIVERSAL_ROUTER).execute(
            abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN))),
            inputs,
            block.timestamp
        );

        toAmount = to.balanceOf(beneficiary) - oldBalance;
    }

    /// @inheritdoc IUniversalAerodromeAdapter
    function setPath(address[] calldata tokens, int24[] calldata tickSpacings)
        external
        onlyRole(MANAGER_ROLE)
    {
        bytes memory path = _encodeSlipstreamPath(tokens, tickSpacings);

        IERC20 from = IERC20(tokens[0]);
        IERC20 to = IERC20(tokens[tokens.length - 1]);

        swapPaths[from][to] = path;

        emit PathSet(from, to, path);
    }

    /// @notice encodes the swapData needed for a Slpistream swap execution
    /// @param beneficiary address receiving the amount of tokens received after the swap
    /// @param from token being swapped
    /// @param to token being received
    /// @param amountIn amount of from token being swapped
    /// @param amountOutMin minimum amount to receive of to token
    /// @return swapData encoded swapData as bytes
    function _encodeSlipstreamExactInSwap(
        address beneficiary,
        IERC20 from,
        IERC20 to,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal view returns (bytes memory swapData) {
        // `true` sets `payerIsUser` in execution
        swapData = abi.encode(
            beneficiary, amountIn, amountOutMin, swapPaths[from][to], true
        );
    }

    /// @notice encodes the expected route for swapping tokens for slipstream's
    /// concentrated liquidity pools
    /// @dev tickSpacings are interpolated between token addresses
    /// @param tokens addresses of tokens which are in path
    /// @param tickSpacings values of tickspacings for CL pools of token pairs
    /// @return path encoded path
    function _encodeSlipstreamPath(
        address[] calldata tokens,
        int24[] calldata tickSpacings
    ) internal pure returns (bytes memory path) {
        if (tokens.length != tickSpacings.length + 1) {
            revert IncorrectArrayLengths();
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (i == tokens.length - 1) {
                path = abi.encodePacked(path, tokens[i]);
            } else {
                path = abi.encodePacked(path, tokens[i], tickSpacings[i]);
            }
        }

        return path;
    }
}
