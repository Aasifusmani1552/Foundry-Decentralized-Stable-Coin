// //SPDX-License-Identifier: MIT

// //we are gonna have our invariant here

// //1. the total amount of DSC should always be less than the amount of collateral
// //2. Getter view functions should never revert -> this is an evergreen invariant, we can use it in almost every contract to test

// pragma solidity ^0.8.18;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "script/DeployDSC.s.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "script/HelperConfig.s.sol";
// import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract InvariantTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         (,, weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 wethDeposited = IERC20(weth).balanceOf(address(dsce));
//         uint256 wbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

//         uint256 wethValue = dsce._getUsdValue(weth, wethDeposited);
//         uint256 wbtcValue = dsce._getUsdValue(wbtc, wbtcDeposited);

//         console.log("total supply: %s", totalSupply);
//         console.log("weth value: %s", wethValue);
//         console.log("wbtc value: %s", wbtcValue);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
