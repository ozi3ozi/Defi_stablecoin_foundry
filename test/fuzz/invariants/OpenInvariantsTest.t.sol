// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/**
 * invariants:
 *   - mintedDsc(_user) * 2 >= getAccountCollateralValueInUsd(_user)
 *   - i_dsc.totalSupply() * 2 >= totalCollateralValueInUsd held by usersS
 *
 */
import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {EngineHandler} from "test/fuzz/handlers/EngineHandler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DSCEngine engine;
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    HelperConfig config;
    EngineHandler engineHandler;
    ERC20Mock[] public allowedTokens;
    MockV3Aggregator[] public priceFeeds;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, ERC20Mock weth, ERC20Mock wbtc,) = config.activeNetworkConfig();
        allowedTokens.push(weth);
        allowedTokens.push(wbtc);
        priceFeeds.push(MockV3Aggregator(wethUsdPriceFeed));
        priceFeeds.push(MockV3Aggregator(wbtcUsdPriceFeed));
        engineHandler = new EngineHandler(dsc, engine, allowedTokens, priceFeeds);
        targetContract(address(engineHandler));
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 10
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_protocolRecordedColletaralBalanceMustMatchActualBalance() public view {
        // Comparing contract wallet balance wit handler ghost varibale
        // assertGt(
        //     engineHandler.sumDepositedCollateralsUsd(), 
        //     engineHandler.sumMintedDsc()
        // );sd
    }
}
