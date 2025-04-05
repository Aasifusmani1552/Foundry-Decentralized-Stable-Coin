// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint96 MAX_AMOUNT_TO_DEPOSIT = type(uint96).max;

    uint256 public timesMintIsCalled;
    address[] public userWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (userWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = userWithCollateralDeposited[addressSeed % userWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        // calculate the additional dsc we can mint, like the maximum amount of mintable dsc
        int256 maxDscToMint = (int256(collateralValueInUsd) - int256(totalDscMinted)) / 2;
        // if we reach the max limit of mintable dsc
        if (maxDscToMint <= 0) {
            return;
        }
        uint256 additionalDscToMint = uint256(maxDscToMint);
        amount = bound(amount, 0, additionalDscToMint);
        if (amount == 0) {
            return;
        }

        uint256 expectedHealthFactor = dsce.calculateHealthFactor(totalDscMinted + amount, collateralValueInUsd);
        if (expectedHealthFactor < dsce.getMinHealthFactor()) {
            return;
        }
        if (maxDscToMint < 0) {
            return;
        }
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        if (amount <= 0) {
            return;
        }
        amount = bound(amount, 1, MAX_AMOUNT_TO_DEPOSIT);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(dsce), amount);
        dsce.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        userWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        (uint256 totalDSCminted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);
        uint256 collateralToken = dsce.getCollateralBalanceOfToken(address(collateral), msg.sender);
        if (collateralToken <= 0) {
            return;
        }
        uint256 tokenValue = dsce._getUsdValue(address(collateral), collateralToken);
        int256 maxAllowedRedeemAmountInUsd = ((int256(tokenValue) - int256(totalDSCminted)) / 2);
        if (maxAllowedRedeemAmountInUsd <= 0) {
            maxAllowedRedeemAmountInUsd = 0;
        }
        uint256 additionalRedeemAmountInTokens =
            dsce.getTokenAmountFromUsd(address(collateral), uint256(maxAllowedRedeemAmountInUsd));
        amountCollateral = bound(amountCollateral, 0, additionalRedeemAmountInTokens);
        if (amountCollateral == 0) {
            return;
        }
        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(totalDSCminted, collateralValueInUsd - uint256(maxAllowedRedeemAmountInUsd));

        if (expectedHealthFactor < dsce.getMinHealthFactor()) {
            return;
        }
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    //Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function _GetTotalNumberOfTokens(address user) private view returns (uint256, uint256, uint256) {
        uint256 wethBalance = dsce.getCollateralBalanceOfToken(address(weth), user);
        uint256 wbtcBalance = dsce.getCollateralBalanceOfToken(address(wbtc), user);
        uint256 totalNumberOfTokens = wethBalance + wbtcBalance;
        return (totalNumberOfTokens, wethBalance, wbtcBalance);
    }
}
