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
    error DSCEngine_BurnAmntExceedsBalance();
    error DSCEngine_ZeroAddress();

    //////////////////////////
    // State variables      //
    //////////////////////////
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50; //200% collateralization
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALTH_FACTOR = 1;

    //Allowed collateral tokens for DSC with their price feeds. Set in constructor
    mapping(address token => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private depositedCollaterals;
    mapping(address user => uint256 mintedAmount) private mintedDsc;
    address[] private allowedCollateralTokens;

    DecentralizedStablecoin private immutable i_dsc;

    /////////////////
    // Events      //
    /////////////////
    event CollateralDeposited(address user, address token, uint256 amount);
    event CollateralWithdrawn(address user, address token, uint256 amount);

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
    function depositCollateralAndMintDsc() external {}

    /**
     * @param _tokenCollateralAddy The address of the collateral token to deposit
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address _tokenCollateralAddy, uint256 _amountCollateral)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * @dev User must have more collateral than minimum threshold to proceed with minting
     * @param _amountDscToMint The amount of Decentralized Stablecoin(DSC) to mint
     */
    function mintDsc(uint256 _amountDscToMint) external moreThanZero(_amountDscToMint) {
        mintedDsc[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    // Private & internal view Functions   //
    /////////////////////////////////////////

    function _getAccountInfo(address _user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = mintedDsc[_user];
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
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / PRECISION;
    }
}
