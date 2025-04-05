//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public user = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL_TO_REDEEM = 4 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 2;
    uint256 public constant AMOUNT_DSC_TO_BURN = 1;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, STARTING_BALANCE);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddreses;

    ///////////////////////
    //Constructor Tests  //
    ///////////////////////
    function testRevertsIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddreses.push(ethUsdPriceFeed);
        priceFeedAddreses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddreses, address(dsc));
    }

    /////////////////
    //Price Tests  //
    /////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce._getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }
    /////////////////////////////
    //depositCollateral Tests  //
    /////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); // this can be the mistake
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 actualCollateralDeposited = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assert(totalDscMinted == AMOUNT_DSC_TO_MINT);
        assert(actualCollateralDeposited == AMOUNT_COLLATERAL);
    }
    ////////////////////////////////////////////
    //MintDSC, BurnDsc & Health Factor Tests  //
    ////////////////////////////////////////////
    // we can't redeem collateral without minting some dsc, if we try so, we get panic error of division by zero

    function testMintDsc() public depositedCollateral {
        vm.prank(user);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(user);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
    }

    function testBurnDsc() public depositedCollateral {
        vm.startPrank(user);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dsce), 2); // as the burn function calls transferFrom, it needs the owner approval to transfer dsc from user to dsc engine, that's why we directly called approve from dsc
        (uint256 totalDscMintedbeforeBurn,) = dsce.getAccountInformation(user);
        dsce.burnDsc(AMOUNT_DSC_TO_BURN);
        (uint256 totalDscMintedAfterBurn,) = dsce.getAccountInformation(user);
        assert(totalDscMintedbeforeBurn == AMOUNT_DSC_TO_MINT);
        assert(totalDscMintedAfterBurn == AMOUNT_DSC_TO_BURN);
    }

    function testRevertsIfhealthFactorBreaks() public depositedCollateral {
        uint256 healthFactor;
        vm.startPrank(user);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, healthFactor));
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////////////////
    //Redeem Collateral Tests  //
    /////////////////////////////

    function testRedeemCollateralRevertsIfAmountIsLess() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughCollateralToRedeem.selector);
        dsce.redeemCollateral(weth, 11 ether);
        vm.stopPrank();
    }

    function testRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(user);
        dsce.redeemCollateral(weth, 6 ether);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        assertEq(collateralValueInUsd, 8000e18);
    }

    function testRedeemCollateralAndBurnDsc() public depositedCollateral {
        vm.startPrank(user);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_BURN);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL_TO_REDEEM, AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 totalTokensLeft = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assert(totalDscMinted == (AMOUNT_DSC_TO_MINT - AMOUNT_DSC_TO_BURN));
        assert(totalTokensLeft == 6 ether);
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    // we actually don't need this function now as we already checking for depositedCollateral Modifier
    // function testDepositCollateral() public depositedCollateral {}

    //can't test this yet
    // function testLiquidateFunction() public depositedCollateral {
    //     address alice = makeAddr("alice");

    // }

    ////////////////////////////
    //Getter Functions Tests  //
    ////////////////////////////

    function testGetHealthFactor() public depositedCollateral {
        vm.prank(user);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        uint256 expectedHealthfactor = 5000e36; // as we are working with the precision, so the returned amount of collateral will be in wei i.e. with 18 zeros, and we again use precision in gethealthfactor function so the amount will be 5000e36, this is one of the mistakes
        uint256 actualHealthFactor = dsce.getHealthFactor(user);
        assertEq(expectedHealthfactor, actualHealthFactor);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 actualCollateralValueInUsd = dsce._getAccountCollateralValue(user);
        uint256 expectedCollateralValueInUsd = dsce._getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(actualCollateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(user, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetDsc() public {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }
}
