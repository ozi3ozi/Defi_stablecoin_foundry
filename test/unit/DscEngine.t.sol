// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DscEngineTest is Test {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_BALANCE = 25 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 100 ether;
    uint256 public constant ONE_WEI = 1 wei;
    uint256 public i_engineInitWethBalance;

    uint256 public sepoliaFork;

    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    DSCEngine engine;
    HelperConfig config;

    ERC20Mock invalidTkn = new ERC20Mock();

    address public USER = makeAddr("user");

    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    ERC20Mock wethMock;
    ERC20Mock wbtcMock;

    address[] public allowedTokensCollateral;
    address[] public allowedTokensPriceFeed;
    
    function setUp() public {
        sepoliaFork = vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, wethMock, wbtcMock,) = config.activeNetworkConfig();
        weth = address(wethMock);
        wbtc = address(wbtcMock);
        wethMock.mint(USER, STARTING_BALANCE);
        i_engineInitWethBalance = wethMock.balanceOf(address(engine));
    }

    ///////////////////////////
    // Constructor tests     //
    ///////////////////////////
    function testRevertsIfTokensArrAndPriceFeedArrNotSameLen() public {
        allowedTokensCollateral.push(weth);
        allowedTokensPriceFeed = [ethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.expectRevert(DSCEngine.DSCEngine__AllowedCollateralTokensAndPriceFeedsMustBeSameLength.selector);
        new DSCEngine(allowedTokensCollateral, allowedTokensPriceFeed, address(dsc));
    }

    function testInitializeAllowedCollateralTokensAndPriceFeeds() public {
        allowedTokensCollateral = [weth, wbtc];
        allowedTokensPriceFeed = [ethUsdPriceFeed, wbtcUsdPriceFeed];
        DSCEngine dscEngine = new DSCEngine(allowedTokensCollateral, allowedTokensPriceFeed, address(dsc));
        for (uint i = 0; i < allowedTokensCollateral.length; i++) {
            assertEq(dscEngine.getAllowedCollateralTokens()[i], allowedTokensCollateral[i]);
            assertEq(dscEngine.getPriceFeedFor(allowedTokensCollateral[i]), allowedTokensPriceFeed[i]);
        }
    }

    function testInitializesDscAddy() public view {
        assertEq(engine.getDscAddy(), address(dsc));
    }

    /////////////////////
    // Price tests     //
    /////////////////////

    function testgetUsdValue() public view {
        uint256 ethAmnt = 15e18;
        //i.e. 2000e8 * 1e10 * 15e18 / 1e18
        uint256 expectedEthInUsd = uint256(config.ETH_USD_PRICE()) * ADDITIONAL_FEED_PRECISION * ethAmnt / PRECISION;
        uint256 actualEthInUsd = engine.getUsdValue(weth, ethAmnt);

        uint256 wbtcAmnt = 15e18;
        uint256 expectedWbtcInUsd = uint256(config.BTC_USD_PRICE()) * ADDITIONAL_FEED_PRECISION * wbtcAmnt / PRECISION;
        uint256 actualWbtcInUsd = engine.getUsdValue(wbtc, wbtcAmnt);

        assertEq(expectedEthInUsd, actualEthInUsd);
        assertEq(expectedWbtcInUsd, actualWbtcInUsd);
    }

    function testGetTokenAmntFromUsd() public view {
        uint256 usdAmnt = 1500e18; //$1500
        //i.e. 1500e18 * 1e18 / 2000e8 * 1e10
        uint256 expectedTknAmnt = usdAmnt * PRECISION / (uint256(config.ETH_USD_PRICE()) * ADDITIONAL_FEED_PRECISION);
        uint256 actualTknAMnt = engine.getTokenAmntFromUsd(weth, usdAmnt);
        assertEq(expectedTknAmnt, actualTknAMnt);
    }

    //////////////////////////////////
    // depositCollateral() tests    //
    //////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfInvalidCollateralTkn() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__InvalidCollateral.selector);
        engine.depositCollateral(address(invalidTkn), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testShouldIncreaseDepositedCollateral() 
        public depositWethCollateralBefore(USER, AMOUNT_COLLATERAL) {
        (uint256 dscMinted, uint256 totalCollateralInUsd) = engine.getAccountInfo(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedTotalCollateralInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(expectedDscMinted, dscMinted);
        assertEq(expectedTotalCollateralInUsd, totalCollateralInUsd);
    }

    function testShouldEmitCollateralDepositedEvent() 
        public 
        depositWethCollateralAfter(USER, AMOUNT_COLLATERAL) {
        vm.expectEmit();
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
    }

    function testShouldTransferTokenCollateralToEngine() 
        public
        depositWethCollateralBefore(USER, AMOUNT_COLLATERAL) {
        assertEq(wethMock.balanceOf(address(engine)), i_engineInitWethBalance + AMOUNT_COLLATERAL);
        assertEq(wethMock.balanceOf(USER), STARTING_BALANCE - AMOUNT_COLLATERAL);
    }

    //////////////////////
    // mintDsc() tests  //
    //////////////////////

    function testRevertsIfDscToMintZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        vm.prank(USER);
        engine.mintDsc(0, weth);
    }

    function testRevertsIfNotEnoughCollateral() public {
        (, uint256 collateralValueInUsd) = engine.getAccountInfo(USER);
        uint256 healthFactor = engine.getExpectedHealthFactorFor(AMOUNT_DSC_TO_MINT, collateralValueInUsd);
        vm.expectRevert(abi.encodeWithSignature("DSCEngine__HealthFactorIsTooLow(uint256)", healthFactor));
        vm.prank(USER);
        engine.mintDsc(AMOUNT_DSC_TO_MINT, weth);
    }

    function testRevertsIfDscToMintTooHigh() 
        public depositWethCollateralBefore(USER, AMOUNT_COLLATERAL) {
        (, uint256 collateralValueInUsd) = engine.getAccountInfo(USER);
        uint256 maxDscAllowedToMint = engine.getUsdValue(weth, AMOUNT_COLLATERAL) / 2;// half of collateral
        uint256 healthFactor = engine.getExpectedHealthFactorFor(maxDscAllowedToMint + ONE_WEI, collateralValueInUsd);
        vm.expectRevert(abi.encodeWithSignature("DSCEngine__HealthFactorIsTooLow(uint256)", healthFactor));
        vm.prank(USER);
        engine.mintDsc(maxDscAllowedToMint + ONE_WEI, weth);
    }

    function testShouldIncreaseMintedDsc() 
        public depositWethCollateralBefore(USER, AMOUNT_COLLATERAL) {
        vm.prank(USER);
        engine.mintDsc(AMOUNT_DSC_TO_MINT, weth);
        (uint256 dscMinted, ) = engine.getAccountInfo(USER);
        assertEq(AMOUNT_DSC_TO_MINT, dscMinted);
    }

    //////////////////////////////////////////
    // depositCollateralAndMintDsc() tests  //
    //////////////////////////////////////////

    function testDepositCollateralAndMintDsc() public {
        (uint256 dscMintedBefore, uint256 collateralInUsdBefore) = engine.getAccountInfo(USER);
        approveCollateral(USER, weth, AMOUNT_COLLATERAL);
        vm.prank(USER);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);

        (uint256 dscMintedAfter, uint256 collateralInUsdAfter) = engine.getAccountInfo(USER);
        assertEq(
            dscMintedBefore + AMOUNT_DSC_TO_MINT, 
            dscMintedAfter
        );
        assertEq(
            collateralInUsdBefore + engine.getUsdValue(weth, AMOUNT_COLLATERAL), 
            collateralInUsdAfter
        );
    }

    ///////////////////////////////
    // redeemCollateral() tests  //
    ///////////////////////////////

    function testRevertsIfAmntToRedeemZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        vm.prank(USER);
        engine.redeemCollateral(weth, 0);
    }

    function testRevertsIfTknToRedeemInvalid() public {
        vm.expectRevert(DSCEngine.DSCEngine__InvalidCollateral.selector);
        vm.prank(USER);
        engine.redeemCollateral(address(invalidTkn), AMOUNT_COLLATERAL);
    }

    function testRevertsIfAmntTOReddemExceedsDeposited() public {
        vm.expectRevert(DSCEngine.DSCEngine__CollateralToReddemExceedsBalance.selector);
        vm.prank(USER);
        engine.redeemCollateral(weth, ONE_WEI);
    }

    function testShouldDecreaseCollateralBalance() 
        public depositWethCollateralBefore(USER, AMOUNT_COLLATERAL) {
        uint256 collateralBeforeRedeem = engine.getDepositedCollateralFor(USER, weth);
        vm.prank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        assertEq(
            collateralBeforeRedeem - AMOUNT_COLLATERAL, 
            engine.getDepositedCollateralFor(USER, weth)
        );
    }

    function testShouldSendRedeemedAmntToUser() 
        public depositWethCollateralBefore(USER, AMOUNT_COLLATERAL) {
        uint256 balanceBefore = wethMock.balanceOf(USER);
        vm.prank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        assertEq(wethMock.balanceOf(USER), balanceBefore + AMOUNT_COLLATERAL);
    }

    //////////////////////
    // burnDsc() tests  //
    //////////////////////

    function testRevertsIfAmntToBurnZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        vm.prank(USER);
        engine.burnDsc(0, weth);
    }

    function testRevertsIfUserBalanceLTAmntToBurn() public {
        vm.expectRevert(DSCEngine.DSCEngine__DscAmntExceedsBalance.selector);
        vm.prank(USER);
        engine.burnDsc(ONE_WEI, weth);
    }

    function testShouldDecreaseUserMintedDsc() 
        public depositWethCollateralBefore(USER, AMOUNT_COLLATERAL) {
        approveCollateral(USER, weth, AMOUNT_COLLATERAL);
        approveDsc(USER, AMOUNT_DSC_TO_MINT);
        vm.startPrank(USER);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        (uint256 dscMintedBalanceBefore, ) = engine.getAccountInfo(USER);
        uint256 dscWalletBalanceBefore = ERC20(dsc).balanceOf(USER);
        engine.burnDsc(AMOUNT_DSC_TO_MINT, weth);
        vm.stopPrank();
        (uint256 dscMintedBalanceAfter, ) = engine.getAccountInfo(USER);
        assertEq(
            dscMintedBalanceAfter, 
            dscMintedBalanceBefore - AMOUNT_DSC_TO_MINT
        );
        assertEq(
            dscWalletBalanceBefore - AMOUNT_DSC_TO_MINT, 
            ERC20(dsc).balanceOf(USER)
        );
    }

    //////////////////////
    // Helper functions //
    //////////////////////

    function approveCollateral(address _user, address _tokenCollateral, uint256 _amount) public {
        _approveToken(_user, _tokenCollateral, _amount);
    }

    function approveDsc(address _user, uint256 _amount) public {
        _approveToken(_user, address(dsc), _amount);
    }

    function _approveToken(address _user, address _tokenCollateral, uint256 _amount) internal {
        vm.prank(_user);
        ERC20Mock(_tokenCollateral).approve(address(engine), _amount);
    }

    function depositCollateral(address _user, address _tokenCollateral, uint256 _amount) public {
        vm.prank(_user);
        engine.depositCollateral(_tokenCollateral, _amount);
    }

    ///////////////
    // Modifiers //
    ///////////////

    modifier depositWethCollateralBefore(address _user, uint256 _amount) {
        approveCollateral(_user, weth, _amount);
        depositCollateral(_user, weth, _amount);
        _;
    }

    modifier depositWethCollateralAfter(address _user, uint256 _amount) {
        approveCollateral(_user, weth, _amount);
        _;
        depositCollateral(_user, weth, _amount);
    }
}