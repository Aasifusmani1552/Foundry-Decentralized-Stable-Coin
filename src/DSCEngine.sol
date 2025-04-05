//SPDX-License-Identifier: MIT
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

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";
// import {console2} from "forge-std/console2.sol"; added this for debugging, it's very helpful!!
/*
 * @title DSCEngine
 * @author Aasif
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 *  1. Exogenous Collateral
 *  2. Dollar pegged
 *  3. Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of all the collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////
    // errors     //
    ////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__NotEnoughCollateralToRedeem();

    ///////////
    //types  //
    ///////////

    using OracleLib for AggregatorV3Interface;

    /////////////////////////
    // State Variables     //
    /////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized(it's like if collateral is 100$, then 100 * 50 = 5000/100 = 50, so dsc shouldn't be more)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus to the liquidators

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPricefeeds(like btc to it's pricefeed from chainlink)
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    DecentralizedStableCoin private immutable i_dsc;
    address[] private s_collateralTokens;

    ////////////////
    // Events     //
    ////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed addressfrom, address indexed addressTo, uint256 amount, address indexed token
    );

    ////////////////
    // Modifiers  //
    ////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////
    // Functions  //
    ////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////
    // External Functions  //
    /////////////////////////

    /*
    * @param tokenCollateralAddress The address of token to be used as Collateral
    * @param amountCollateral The amount of Collateral
    * @param amountDscToMint the amount of DSC to mint
    * 
    * @notice This function will deposit collateral and mint dsc in one transaction.
    */

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of Collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
    * @param tokenCollateralAddress The address of token to be used as Collateral
    * @param amountCollateral The amount of Collateral to be redeemed
    * @param amountDscToBurn The amount of DSC to burn
    * @notice This function redeems collateral as well as burns the amount of DSC in one transaction
    */
    // test this!!!!
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // don't need to check health factor here, as we check it in redeemCollateral function
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        if (s_collateralDeposited[msg.sender][tokenCollateralAddress] < amountCollateral) {
            revert DSCEngine__NotEnoughCollateralToRedeem();
        }
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @notice follows CEI(checks, effects, integration)
    * @param amountDscToMint the amount of decentralized stable coin to mint
    * @notice they must have more collateral value than the minimum threshold
    */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        // to create this function we will need the price feed of tokens
        s_DSCMinted[msg.sender] += amountDscToMint;
        // to check if user doesn't mint more dsc than the collateral deposited, we will create an internal function
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint); //it is the dscEngine which actually mints the tokens to the msg.sender, it shows the algorithmic stability
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    // to be safe from undercollateralization and not being able to fulfull people's redeem requests!.

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender); // as engine is the owner, we burn the tokens here to remove them permanentaly
        _revertIfHealthFactorIsBroken(msg.sender); //this is redundant as burning won't affect the health score of a user.
    }

    // let's say if someone deposit 100$ worth of eth as collateral
    // he mints 50$ worht of dsc, in the meantime the value of eth comes down to let's say 75$'s
    // the threshold was set at 80%, LIQUIDATION REQUIRED!! so another person may find this and pays back the 50$ of dsc back to get the 75$
    // now the second person got incentive of 25$'s and the first person got penalized for not maintaining the collateral threshold.
    // to make people able to liquidate a person's collateral by paying his/her debt to earn some incentive

    /*
    * @param collateralToken The erc20 collateral address to liquidate from the user
    * @param user The address of the user who has broken health factor. _healthfactor should be below MIN_HEALTH_FACTOR.
    * @param debtToCover The amount of DSC you want to burn to improve user's health factor.
    * 
    * @notice You can partially liquidate the user.
    * @notice You will get liquidation bonus for improving or paying user's debt.
    * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
    * @notice A bug would be there if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators.
    * For example: If someone collateralized $100 of ETH for $50 of DSC, it's fine, but if the value of eth falls below $100, like $75, the liquidators will
    * still get money, but if the value of eth falls below the value of the minted DSC like $40 or less, then liquidation of that user will not be an incentivized
    * liquidation.
    * @dev Follows CEI: Checks, Effects, Interactions
    */
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);
        // we will give 10% of bonus to the liquidator as the bonus
        // rest of the amount will go to the treasury
        uint256 bonusCollateralToLiquidator = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION; // getting 10% of the total tokens to be given to liquidator
        uint256 totalCollateral = tokenAmountFromDebtCovered + bonusCollateralToLiquidator;
        _redeemCollateral(collateralToken, totalCollateral, user, msg.sender);
        // now we need to burn the dsc of the user
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);

        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    ////////////////////////////////////////
    // Private & Internal View Functions  //
    ////////////////////////////////////////

    /*
    * @dev Low-level internal function, do not call unless the functions calling it is checking for health factors being broken
    */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function __calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 numerator = collateralValueInUsd * PRECISION * LIQUIDATION_THRESHOLD;
        uint256 denominator = totalDscMinted * LIQUIDATION_PRECISION;
        uint256 result = numerator / denominator;

        return result;
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, amountCollateral, tokenCollateralAddress);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = _getAccountCollateralValue(user);

        return (totalDscMinted, collateralValueInUsd);
    }

    /*
    * Returns how close to liquidation a User is
    * If a user get close to 1, they can get liquidated
    */
    function _healthFactor(address user) private view returns (uint256) {
        //we will need a user's dsc balance and his/her amount of collateral right
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // 100 * 50 = 5000/100 = 50, which is 200% of the original value, so ratio looks like 50 * 1e18 / 50, if  user is on the pivot of threshold
        return __calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////
    // Public & External View Functions   //
    ////////////////////////////////////////
    // it is simple math, we are getting the total amount of token by dividing the total price i.e. usdAmountInWei by the amount of one Token
    // like if the total amount to be burned is $100 and the amount of one token is $2000, then the amount of eth would be 100/2000 = 0.05 DSC.
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        uint256 precisedUsdAmount = usdAmountInWei * PRECISION;
        uint256 precisedPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
        return precisedUsdAmount / precisedPrice;
    }

    function getCollateralBalanceOfToken(address token, address user) public view returns (uint256 tokenBalance) {
        tokenBalance = s_collateralDeposited[user][token];
        return tokenBalance;
    }

    function _getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function _getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
        return (totalDscMinted, collateralValueInUsd);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return __calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
