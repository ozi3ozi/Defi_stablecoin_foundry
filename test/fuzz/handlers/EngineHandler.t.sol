// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract EngineHandler is Test {
    uint256 public constant STARTING_BALANCE = 2500 ether;

    DSCEngine engine;
    DecentralizedStablecoin dsc;
    HelperConfig config;

    address[] public actors;
    ERC20Mock[] public allowedTokensCollateral;
    MockV3Aggregator[] public priceFeeds;

    address public currentActor;
    ERC20Mock public currentTokenCollateral;
    MockV3Aggregator public currentPriceFeed;

    uint256 public sumDepositedCollateralsUsd;
    uint256 public sumMintedDsc;

    mapping (address collateralToken => uint256 sumDeposited) public sumDepositedCollateral; 

    constructor(
        DecentralizedStablecoin _dsc, 
        DSCEngine _engine, 
        ERC20Mock[] memory _allowedTokensCollateral, 
        MockV3Aggregator[] memory _priceFeeds
    ) {
        dsc = _dsc;
        engine = _engine;
        makeUsers(2);
        allowedTokensCollateral = _allowedTokensCollateral;
        priceFeeds = _priceFeeds;
    }

    ///////////
    //Modifiers
    ///////////

    modifier useActor(uint256 _actorIndex) {
        currentActor = actors[bound(_actorIndex, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        currentTokenCollateral.mint(currentActor, STARTING_BALANCE);
        _;
        vm.stopPrank();
    }

    modifier useAllowedTokenCollateral(uint8 _tokenIndex) {
        _tokenIndex = uint8(bound(_tokenIndex, 0, allowedTokensCollateral.length - 1));
        currentTokenCollateral = allowedTokensCollateral[0];
        currentPriceFeed = priceFeeds[0];
        _;
    }

    //Helpers
    function makeUsers(uint _ammount) internal {
        for (uint i = 0; i < _ammount; i++) {
            actors.push(makeAddr(
                string(abi.encodePacked("user", i))
            ));
        }
    }

    function depositCollateral(
        uint256 _amount,
        uint256 _indexSeed
    ) 
        external 
        useAllowedTokenCollateral(uint8(_indexSeed))
        useActor(_indexSeed)
    {
        // Deposit between 1 and user balance. 0 deposit error already tested in DscEngine.t.sol
        _amount = uint96(bound(_amount, 1, currentTokenCollateral.balanceOf(currentActor) * 10 / 100));

        uint256 userBalanceBefore = currentTokenCollateral.balanceOf(currentActor);
        uint256 userDepositedCollateralBefore = engine.getDepositedCollateralFor(currentActor, address(currentTokenCollateral));
        uint256 engineBalanceBefore = currentTokenCollateral.balanceOf(address(engine));

        currentTokenCollateral.approve(address(engine), _amount);
        engine.depositCollateral(address(currentTokenCollateral), _amount);

        uint256 userBalanceAfter = currentTokenCollateral.balanceOf(currentActor);
        uint256 userDepositedCollateralAfter = engine.getDepositedCollateralFor(currentActor, address(currentTokenCollateral));
        uint256 engineBalanceAfter = currentTokenCollateral.balanceOf(address(engine));
        
        assertEq(// Comparing user balances in wallets
            userBalanceAfter, 
            userBalanceBefore - _amount
        );
        assertEq(// Comparing user balances in DSCEngine contract
            userDepositedCollateralAfter, 
            userDepositedCollateralBefore + _amount
        );
        assertEq(// Comparing contract wallet balance before and after
            engineBalanceAfter, 
            engineBalanceBefore + _amount
        );

        sumDepositedCollateral[address(currentTokenCollateral)] += _amount;
        sumDepositedCollateralsUsd += engine.getUsdValue(address(currentTokenCollateral), _amount);
        assertEq(// Comparing wallet balance with ghost variable sumDepositedCollateral
            engineBalanceAfter, 
            sumDepositedCollateral[address(currentTokenCollateral)]
        );
    }

    function mintDsc(
        uint256 _amountCollateral, 
        uint256 _indexSeed
    ) 
        external 
        useAllowedTokenCollateral(uint8(_indexSeed)) 
        useActor(_indexSeed) 
    {
        // Mint between 1 and user balance. 0 mint error already tested in DscEngine.t.sol
        _amountCollateral = uint96(bound(_amountCollateral, 1, currentTokenCollateral.balanceOf(currentActor) * 10 / 100));
        uint256 userDscBalanceBeforeMint = dsc.balanceOf(currentActor);

        // console.log("amountToMint", amountToMint);

        currentTokenCollateral.approve(address(engine), _amountCollateral);
        engine.depositCollateral(address(currentTokenCollateral), _amountCollateral);

        uint256 amountToMint = engine.getMaxCanMintFor(currentActor, address(currentTokenCollateral));
        engine.mintDsc(amountToMint, address(currentTokenCollateral));

        uint256 userDscBalanceAfterMint = dsc.balanceOf(currentActor);

        assertEq(
            userDscBalanceAfterMint, 
            userDscBalanceBeforeMint + amountToMint
        );
        assertEq(
            engine.getMintedDscFor(currentActor), 
            userDscBalanceAfterMint
        );

        sumMintedDsc += amountToMint;
        sumDepositedCollateral[address(currentTokenCollateral)] += _amountCollateral;
        sumDepositedCollateralsUsd += engine.getUsdValue(address(currentTokenCollateral), _amountCollateral);
        console.log(sumDepositedCollateralsUsd);
        console.log(sumMintedDsc);
        assertGt(
            sumDepositedCollateralsUsd, 
            sumMintedDsc
        );
    }

    function redeemCollateral(
        uint256 _amountCollateralToRedeem,
        uint256 _indexSeed
    )
        external 
        useAllowedTokenCollateral(uint8(_indexSeed))
        useActor(_indexSeed)
    {
        // Redeem between 1 and user deposited collateral balance. 0 redeem error already tested in DscEngine.t.sol
        _amountCollateralToRedeem = uint96(bound(_amountCollateralToRedeem, 1, STARTING_BALANCE));

        currentTokenCollateral.approve(address(engine), _amountCollateralToRedeem);
        engine.depositCollateral(address(currentTokenCollateral), _amountCollateralToRedeem);
        
        uint256 userBalanceBefore = currentTokenCollateral.balanceOf(currentActor);
        uint256 userDepositedCollateralBefore = engine.getDepositedCollateralFor(currentActor, address(currentTokenCollateral));
        uint256 engineBalanceBefore = currentTokenCollateral.balanceOf(address(engine));

        engine.redeemCollateral(address(currentTokenCollateral), _amountCollateralToRedeem);

        uint256 userBalanceAfter = currentTokenCollateral.balanceOf(currentActor);
        uint256 userDepositedCollateralAfter = engine.getDepositedCollateralFor(currentActor, address(currentTokenCollateral));
        uint256 engineBalanceAfter = currentTokenCollateral.balanceOf(address(engine));

        assertEq(// Comparing user balances in wallets
            userBalanceAfter, 
            userBalanceBefore + _amountCollateralToRedeem
        );
        assertEq(// Comparing user balances in DSCEngine contract
            userDepositedCollateralAfter, 
            userDepositedCollateralBefore - _amountCollateralToRedeem
        );
        assertEq(// Comparing contract wallet balance before and after
            engineBalanceAfter, 
            engineBalanceBefore - _amountCollateralToRedeem
        );

    }

    function burnDsc(
        uint256 _amountCollateral,
        uint256 _indexSeed
    ) 
        external
        useAllowedTokenCollateral(uint8(_indexSeed))
        useActor(_indexSeed)
    {
        _amountCollateral = uint96(bound(_amountCollateral, 1, currentTokenCollateral.balanceOf(currentActor) * 10 / 100));
        currentTokenCollateral.approve(address(engine), _amountCollateral);
        engine.depositCollateral(address(currentTokenCollateral), _amountCollateral);
        uint256 amountMinted = engine.getMaxCanMintFor(currentActor, address(currentTokenCollateral));
        engine.mintDsc(amountMinted, address(currentTokenCollateral));

        uint256 userDscBalanceBeforeBurn = dsc.balanceOf(currentActor);
        uint256 userMintedDscBeforeBurn = engine.getMintedDscFor(currentActor);

        dsc.approve(address(engine), amountMinted);
        engine.burnDsc(amountMinted, address(currentTokenCollateral));

        uint256 userDscBalanceAfterBurn = dsc.balanceOf(currentActor);
        uint256 userMintedDscAfterBurn = engine.getMintedDscFor(currentActor);

        sumDepositedCollateral[address(currentTokenCollateral)] += _amountCollateral;
        sumDepositedCollateralsUsd += engine.getUsdValue(address(currentTokenCollateral), _amountCollateral);

        assertEq(
            userDscBalanceAfterBurn,
            userDscBalanceBeforeBurn - amountMinted
        );
        assertEq(
            userMintedDscAfterBurn,
            userMintedDscBeforeBurn - amountMinted
        );
    }

    function liquidate(
        uint256 _amountCollateral,
        uint256 _indexSeed
    ) 
        external
        useAllowedTokenCollateral(uint8(_indexSeed))
        useActor(_indexSeed)
    {
        _amountCollateral = uint96(bound(_amountCollateral, 1, currentTokenCollateral.balanceOf(currentActor) * 10 / 100));
        currentTokenCollateral.approve(address(engine), _amountCollateral);
        engine.depositCollateral(address(currentTokenCollateral), _amountCollateral);
        uint256 amountMinted = engine.getMaxCanMintFor(currentActor, address(currentTokenCollateral));
        console.log("amountMinted");
        console.log(amountMinted);
        engine.mintDsc(amountMinted, address(currentTokenCollateral));

        uint256 userDscBalanceBeforeLiquidate = dsc.balanceOf(currentActor);
        uint256 userCollateralBalanceBeforeLiquidate = currentTokenCollateral.balanceOf(currentActor);

        currentPriceFeed.updateAnswer(1800e8);

        dsc.approve(address(engine), amountMinted);
        engine.liquidate(address(currentTokenCollateral), currentActor, amountMinted);
        uint256 collateralRedeemed = (amountMinted * 1e18) / 1800e18;
        uint256 liquidatorFee = collateralRedeemed * 10 / 100;

        uint256 userDscBalanceAfterLiquidate = dsc.balanceOf(currentActor);
        uint256 userCollateralBalanceAfterLiquidate = currentTokenCollateral.balanceOf(currentActor);

        currentPriceFeed.updateAnswer(2000e8);

        assertEq(
            userDscBalanceAfterLiquidate,
            userDscBalanceBeforeLiquidate - amountMinted
        );
        assertEq(
            userCollateralBalanceAfterLiquidate,
            userCollateralBalanceBeforeLiquidate + collateralRedeemed + liquidatorFee
        );


        sumDepositedCollateral[address(currentTokenCollateral)] += _amountCollateral - collateralRedeemed - liquidatorFee;
        sumDepositedCollateralsUsd += engine.getUsdValue(address(currentTokenCollateral), _amountCollateral);
    }
}