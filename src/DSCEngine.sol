// SPDX-License-Identifier: MIT

// This stablecoin is an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.24;

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DSCEngine
 * @author 0zi3zi
 * This system is designed to be as minimal as possible and maintain a 1 DSC == 1 USD peg.
 * This system has the following properties:
 *  - Exogenous collateral (wETH & wBTC)
 *  - Pegged to USD
 *  - Algorithmically stable
 *
 * Our DSC system should always be over-collateralized. At no point should the collateral $ value <= DSC $ value in circulation.
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic for minting and reddeming DSC.
 * As well as depositing and withdrawing collateral.
 * @notice This contract is very loosely based on the MakedDAO (DAI) Stablecoin system.
 * @notice The contract functions will follow the CEI(Check-Effect-Interactions) pattern
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////
    // Errors      //
    /////////////////
    error DSCEngine__InvalidCollateral();
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__AllowedCollateralTokensAndPriceFeedsMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsTooLow(uint256 _healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__DscAmntExceedsBalance();
    error DSCEngine__CollateralToReddemExceedsBalance();
    error DSCEngine__RedeemAmntExceedsBalance();
    error DSCEngine__HealthFactorIsNotBroken();
    error DSCEngine__NewHealthFactorTooLow();
    error DSCEngine__BurnAmntExceedsDebt();

    //////////////////////////990 099 009 900 990 099
    // State variables      //10 100 000 000 000 000 000 000
    //////////////////////////20 000 000 000 000 000 000 000
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50; //200% collateralization
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant LIQUIDATOR_FEE = 10; //10%
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    //Allowed collateral tokens for DSC with their price feeds. Set in constructor
    mapping(address token => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private depositedCollaterals;
    mapping(address user => mapping(address token => uint256 mintedAmount)) private mintedDsc;
    address[] private allowedCollateralTokens;

    DecentralizedStablecoin private immutable i_dsc;

    /////////////////
    // Events      //
    /////////////////
    event CollateralDeposited(address user, address token, uint256 amount);
    event CollateralWithdrawn(address user, address token, uint256 amount);
    event CollateralRedeemed(address redeemedFrom, address redeemedTo, address token, uint256 amount);
    event DSCMinted(address user, uint256 amount);
    event DSCBurned(address user, uint256 amount);

    /////////////////
    // Modifiers   //
    /////////////////
    modifier moreThanZero(uint256 _value) {
        if (_value <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (priceFeeds[_token] == address(0)) {
            revert DSCEngine__InvalidCollateral();
        }
        _;
    }

    modifier hasEnoughDsc(uint256 _dscAmount, address _tokenCollateral) {
        if (i_dsc.balanceOf(msg.sender) < _dscAmount) {
            revert DSCEngine__DscAmntExceedsBalance();
        }

        if (mintedDsc[msg.sender][_tokenCollateral] < _dscAmount) {
            revert DSCEngine__BurnAmntExceedsDebt();
        }
        _;
    }

    modifier hasEnoughCollateral(address _tokenCollareral, uint256 _collateralAmount) {
        if (depositedCollaterals[msg.sender][_tokenCollareral] < _collateralAmount) {
            revert DSCEngine__CollateralToReddemExceedsBalance();
        }
        _;
    }

    /////////////////
    // Functions   //
    /////////////////
    constructor(address[] memory _allowedCollateralTokens, address[] memory _PriceFeeds, address _dscAddy) {
        // USD price feeds
        if (_allowedCollateralTokens.length != _PriceFeeds.length) {
            revert DSCEngine__AllowedCollateralTokensAndPriceFeedsMustBeSameLength();
        }
        for (uint256 i = 0; i < _allowedCollateralTokens.length; i++) {
            priceFeeds[_allowedCollateralTokens[i]] = _PriceFeeds[i];
            allowedCollateralTokens.push(_allowedCollateralTokens[i]);
        }
        i_dsc = DecentralizedStablecoin(_dscAddy);
    }

    //////////////////////////
    // External Functions   //
    //////////////////////////

    /**
     * @param _tokenCollateral The address of the collateral token to deposit
     * @param _amountCollateral The amount of collateral to deposit
     * @param _amountDscToMint The amount of DSC to mint
     * @notice This function deposits collateral and mints DSC in one function
     */
    function depositCollateralAndMintDsc(
        address _tokenCollateral, 
        uint256 _amountCollateral, 
        uint256 _amountDscToMint
    )
        external
    {
        depositCollateral(_tokenCollateral, _amountCollateral);
        mintDsc(_amountDscToMint, _tokenCollateral);
    }

    /**
     * @param _tokenCollateralAddy The address of the collateral token to deposit
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address _tokenCollateralAddy, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddy)
        nonReentrant
    {
        depositedCollaterals[msg.sender][_tokenCollateralAddy] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddy, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddy).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev User must have more collateral than minimum threshold to proceed with minting
     * @param _amountDscToMint The amount of Decentralized Stablecoin(DSC) to mint
     * @param _tokenCollateral The address of the collateral token to use as collateral
     */
    function mintDsc(
        uint256 _amountDscToMint,
        address _tokenCollateral
    ) 
        public moreThanZero(_amountDscToMint) {
        mintedDsc[msg.sender][_tokenCollateral] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @param _tokenCollateral The address of the collateral token to redeem
     * @param _amountCollateralToRedeem The amount of collateral to redeem
     * @param _amountDscToBurn The amount of DSC to burn
     * @notice This function burns DSC and redeems collateral and transfers it to the user
     */
    function redeemCollateralForDsc(
        address _tokenCollateral,
        uint256 _amountCollateralToRedeem,
        uint256 _amountDscToBurn
    ) external {
        burnDsc(_amountDscToBurn, _tokenCollateral);
        redeemCollateral(_tokenCollateral, _amountCollateralToRedeem);
    }

    /**
     * @dev Health factor must stay above 1 after collateral is pulled
     * @param _amountCollateralToRedeem The amount of collateral to redeem
     * @notice This function redeems DSC and transfers it to the user
     */
    function redeemCollateral(
        address _tokenCollateral, 
        uint256 _amountCollateralToRedeem
    ) 
        public
        moreThanZero(_amountCollateralToRedeem)
        isAllowedToken(_tokenCollateral)
        hasEnoughCollateral(_tokenCollateral, _amountCollateralToRedeem)
        nonReentrant
    {
        _redeemCollateral(_tokenCollateral, _amountCollateralToRedeem, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(
        uint256 _amountDscToBurn,
        address _tokenCollateral
    ) 
        public 
        moreThanZero(_amountDscToBurn)
        hasEnoughDsc(_amountDscToBurn, _tokenCollateral)
    {
        _burnDsc(_amountDscToBurn, _tokenCollateral, msg.sender, msg.sender);
    }

    /**
     * @param _tokenCollateral The address of the collateral token
     * @param _user The user to liquidate because he has insufficient collateral. Health factor must be below MIN_HEALTH_FACTOR
     * @param _debtToCoverInUSD The amount of DSC to cover
     * @notice Liquidator can partially liquidate a user
     * @notice Because the collateral value at the time of liquidation is more than the debt value, 
     * the liquidator get a bonus proportionate to the debt % paid
     * 
     */
    function liquidate(
        address _tokenCollateral,
        address _user,
        uint256 _debtToCoverInUSD
    ) 
        external
        moreThanZero(_debtToCoverInUSD)
        nonReentrant 
    {
        uint256 startingHealthFactor = _getHealthFactor(_user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsNotBroken();
        }
        // Calculate how much collateral token is needed based on the debt amount liquidator is paying
        uint256 tokenAmountFromDebtToCover = getTokenAmntFromUsd(_tokenCollateral, _debtToCoverInUSD);
        // Liquidator fee based on the debt paid
        uint256 liquidatorFee = tokenAmountFromDebtToCover * LIQUIDATOR_FEE / LIQUIDATION_PRECISION;
        uint256 totalCollateralToLiquidate = tokenAmountFromDebtToCover + liquidatorFee;
        console.log(string(bytes(abi.encodePacked("totalCollateralToLiquidate: ", totalCollateralToLiquidate))));
        console.log(totalCollateralToLiquidate);
        console.log(string(bytes(abi.encodePacked("totalCollateralBalance: ", depositedCollaterals[_user][_tokenCollateral]))));
        console.log(depositedCollaterals[_user][_tokenCollateral]);
        _burnDsc(_debtToCoverInUSD, _tokenCollateral, _user, msg.sender);
        _redeemCollateral(_tokenCollateral, totalCollateralToLiquidate, _user, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address _user) external view returns (uint256) {
        return _getHealthFactor(_user);
    }

    function getExpectedHealthFactorFor(uint256 totalDscMinted, uint256 collateralValueInUsd) external view returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /////////////////////////////////////////
    // Private & internal view Functions   //
    /////////////////////////////////////////

    function _getAccountInfo(address _user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        for (uint i = 0; i < allowedCollateralTokens.length; i++) {
            totalDscMinted += mintedDsc[_user][allowedCollateralTokens[i]];
        }
        collateralValueInUsd = getAccountCollateralValueInUsd(_user);
    }

    /**
     * Returns how close a user is to liquidation
     * If the health factor goes under 1, the user is liquidated.
     * @param _user The address of the user
     * @return The health factor.
     */
    function _getHealthFactor(address _user) internal view returns (uint256) {
        // total DSC minted
        // total value of collateral deposited
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInfo(_user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal view returns (uint256) {
        if (totalDscMinted == 0) return MIN_HEALTH_FACTOR; // To avoid division by 0
        
        console.log("_calculateHealthFactor()");
        console.log("totalDscMinted");
        console.log(totalDscMinted);
        console.log("collateralValueInUsd");
        console.log(collateralValueInUsd);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @dev Chek the health factor (Is there enough collateral)
     * Revert if the health factor is under MIN_HEALTH_FACTOR
     * @param _user The address of the user
     */
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _getHealthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsTooLow(userHealthFactor);
        }
    }

    function _getLatestPriceFromOracle(address _token) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function _redeemCollateral(
        address _tokenCollateral, 
        uint256 _amountCollateralToRedeem,
        address _from,
        address _to
    ) 
        private
    {
        depositedCollaterals[_from][_tokenCollateral] -= _amountCollateralToRedeem;
        emit CollateralRedeemed(_from, _to, _tokenCollateral, _amountCollateralToRedeem);

        bool success = IERC20(_tokenCollateral).transfer(_to, _amountCollateralToRedeem);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(
        uint256 _amountDscToBurn,
        address _tokenCollareral,
        address _onBehalfOf,
        address _from
    ) 
        private 
    {
        mintedDsc[_onBehalfOf][_tokenCollareral] -= _amountDscToBurn;
        i_dsc.transferFrom(_from, address(this), _amountDscToBurn);
        i_dsc.burn(_amountDscToBurn);
    }

    ////////////////////////////////////////
    // Public & external view Functions   //
    ////////////////////////////////////////

    function getAccountCollateralValueInUsd(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < allowedCollateralTokens.length; i++) {
            totalCollateralValueInUsd +=
                getUsdValue(allowedCollateralTokens[i], depositedCollaterals[_user][allowedCollateralTokens[i]]);
        }
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        uint256 price = _getLatestPriceFromOracle(_token);
        return ((price * ADDITIONAL_FEED_PRECISION) * _amount) / PRECISION;
    }

    function getTokenAmntFromUsd(address _token, uint256 _amountUsd) public view returns (uint256) {
        uint256 price = _getLatestPriceFromOracle(_token);
        console.log("price: ");
        console.log(price);
        return _amountUsd * PRECISION / (price * ADDITIONAL_FEED_PRECISION);
    }

    function getAllowedCollateralTokens() public view returns (address[] memory) {
        return allowedCollateralTokens;
    }

    function getDscAddy() public view returns (address) {
        return address(i_dsc);
    }

    function getAccountInfo(address _user) 
        public view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInfo(_user);
    }

    function getDepositedCollateralFor(address _user, address _token) public view returns (uint256) {
        return depositedCollaterals[_user][_token];
    }

    function getPriceFeedFor(address _token) public view returns (address) {
        return priceFeeds[_token];
    }

    function getMintedDscFor(address _user) public view returns (uint256 totalMintedDsc) {
        for (uint i = 0; i < allowedCollateralTokens.length; i++) {
            totalMintedDsc += mintedDsc[_user][allowedCollateralTokens[i]];    
        }
    }

    function getMaxCanMintFor(address _user, address _tokenCollateral) public view returns (uint256) {
        return (
            getUsdValue(_tokenCollateral, depositedCollaterals[_user][_tokenCollateral]) * 
                LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION
            ) - mintedDsc[_user][_tokenCollateral];
    }
}
