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

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralized Stablecoin
 * @author 0zi3zi
 * Collateral: Exogenous (Crypto) wETH & wBTC
 * Minting: Algorithmic
 * Relative stability: Pegged to USD 
 * @notice This contract is just the ERC20 implementation of the Decentralized Stablecoin system. 
 * This contract is meant to be governed by DSCEngine contract.
 */
contract DecentralizedStablecoin is ERC20Burnable, Ownable {
    error DecentralizedStablecoin_MustBeMoreThanZero();
    error DecentralizedStablecoin_BurnAmntExceedsBalance();
    error DecentralizedStablecoin_ZeroAddress();

    constructor() ERC20("Decentralized Stablecoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (balance <= 0) {
            revert DecentralizedStablecoin_MustBeMoreThanZero();
        } else if (_amount > balance) {
            revert DecentralizedStablecoin_BurnAmntExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to, 
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin_ZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStablecoin_MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
