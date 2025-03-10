// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.21;

/// @title BaseMainnetConstants
/// @notice Constants and addresses of deployed contracts on the Base Mainnet
abstract contract BaseMainnetConstants {
    address public constant BASE_MAINNET_WETH =
        0x4200000000000000000000000000000000000006;
    address public constant BASE_MAINNET_USDbC =
        0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address public constant BASE_MAINNET_wstETH =
        0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    address public constant BASE_MAINNET_cbETH =
        0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address public constant BASE_MAINNET_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address public constant SEAMLESS_ADDRESS_PROVIDER_BASE_MAINNET =
        0x0E02EB705be325407707662C6f6d3466E939f3a0;

    address public constant AERODROME_ROUTER =
        0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address public constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    address public constant UNIVERSAL_ROUTER =
        0x6Cb442acF35158D5eDa88fe602221b67B400Be3E;

    // USDbC has 6 decimals
    uint256 public constant ONE_USDbC = 1e6;

    address public constant SEAMLESS_ATOKEN_IMPL =
        0x27076A995387458da63b23d9AFe3df851727A8dB;
    address public constant SEAMLESS_STABLE_DEBT_TOKEN_IMPL =
        0xb4D5e163738682A955404737f88FDCF15C1391bF;
    address public constant SEAMLESS_VARIABLE_DEBT_TOKEN_IMPL =
        0x3800DA378e17A5B8D07D0144c321163591475977;
    address public constant SEAMLESS_TREASURY =
        0x982F3A0e3183896f9970b8A9Ea6B69Cd53AF1089;
    address public constant SEAMLESS_INCENTIVES_CONTROLLER =
        0x91Ac2FfF8CBeF5859eAA6DdA661feBd533cD3780;

    address public constant SEAMLESS_GOV_SHORT_TIMELOCK_ADDRESS =
        0x639d2dD24304aC2e6A691d8c1cFf4a2665925fee;

    address public constant SEAMLESS_COMMUNITY_MULTISIG =
        0xA1b5f2cc9B407177CD8a4ACF1699fa0b99955A22;

    address public constant SWAPPER = 0xE314ae9D279919a00d4773cCe37946A98fADDaBc;
    address public constant WRAPPED_TOKEN_ADAPTER =
        0xc3e17CDac7C6ED317f0D9845d47df1a281B5f79E;
    address public constant AERODROME_ADAPTER =
        0x6Cfc78c96f87e522EBfDF86995609414cFB1DcB2;

    address public constant BASE_MAINNET_SEAMLESS_WRAPPED_WSTETH =
        0xc9ae3B5673341859D3aC55941D27C8Be4698C9e4;
    address public constant BASE_MAINNET_SEAMLESS_WRAPPED_WETH =
        0x3e8707557D4aD25d6042f590bCF8A06071Da2c5F;
}
