// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DeployDSC is Script {
    address[] public allowedTokens;
    address[] public allowedTokensPriceFeed;

    function run() external returns (DecentralizedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, ERC20Mock weth, ERC20Mock wbtc, uint256 deployerKey) = config.activeNetworkConfig();

        allowedTokens = [address(weth), address(wbtc)];
        allowedTokensPriceFeed = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStablecoin dsc = new DecentralizedStablecoin();
        DSCEngine dscEngine = new DSCEngine(allowedTokens, allowedTokensPriceFeed, address(dsc));

        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, config);
    }
}