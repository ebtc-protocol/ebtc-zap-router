pragma solidity 0.8.17;

abstract contract ZapRouterPropertiesDescriptions {
    ///////////////////////////////////////////////////////
    // Zap Router - High Level
    ///////////////////////////////////////////////////////

    string constant ZR_01 =
        "ZR-01: The balances of tracked tokens in the ZapRouter should never change after a valid user operation";
    string constant ZR_02 =
        "ZR-02: The balance of ETH in the ZapRouter should never change after creation";
    string constant ZR_03 = "ZR-03: The ZapRouter should never be the borrower of a Cdp";
    string constant ZR_04 =
        "ZR-04: The ZapRouter should always renounce positionManagerApproval during a valid user operation";
    string constant ZR_05 =
        "ZR-05: The balance of WETH in the ZapRouter should never change after creation";
    string constant ZR_06 =
        "ZR-06: The balance of wstETH in the ZapRouter should never change after creation";
    string constant ZR_07 = "ZR-07: Parameters that lead to a valid ICR shouldn't revert";
    // Unit test asserts
    // Not self liquidatable
    // Loss through slippage
    // Dust amount
    // Common mistakes of routers
    // Arbitrarily revert
    //

    ///////////////////////////////////////////////////////
    // Zap Router - Unit Tests
    ///////////////////////////////////////////////////////
}
