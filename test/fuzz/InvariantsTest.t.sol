//SPDX-License-Identifier: MIT

//we are gonna have our invariant here

//1. the total amount of DSC should always be less than the amount of collateral
//2. Getter view functions should never revert -> this is an evergreen invariant, we can use it in almost every contract to test

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce._getUsdValue(weth, wethDeposited);
        uint256 wbtcValue = dsce._getUsdValue(wbtc, wbtcDeposited);

        console2.log("total supply: ", uint256(totalSupply));
        console2.log("weth value: ", uint256(wethValue));
        console2.log("wbtc value: ", uint256(wbtcValue));
        console2.log("times mint is called is: ", uint256(handler.timesMintIsCalled()));

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
