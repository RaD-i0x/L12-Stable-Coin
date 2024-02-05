//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    MockV3Aggregator mockTokenPrice;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 1;
    uint256 public constant AMOUNT_COLLATERAL_TO_REDEEM = 1 ether;
    uint256 public constant AMOUNT_DSC_TO_BURN = 1;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////
    // Constructor Tests     ////
    ////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////
    // Price Tests     ////
    //////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        //15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        //$2000 / ETH, 100/2000 = 0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////////
    // depositCollateral Tests     ////
    //////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedDepositCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedMintedValue = AMOUNT_DSC_TO_MINT;
        uint256 expectedCollateralValue = (AMOUNT_COLLATERAL * 2000);
        assertEq(totalDscMinted, expectedMintedValue);
        assertEq(collateralValueInUsd, expectedCollateralValue);
    }

    ////////////////////////////////////
    // redeemCollateral Tests      ////
    //////////////////////////////////

    function testRevertsIfRedeemCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    modifier redeemedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_TO_REDEEM);

        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM);
        vm.stopPrank();
        _;
    }

    function testCanRedeemCollateralAndGetAccountInfo() public depositedCollateral mintedDsc redeemedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = AMOUNT_DSC_TO_MINT;
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq((AMOUNT_COLLATERAL - AMOUNT_COLLATERAL_TO_REDEEM), expectedDepositedAmount);
    }

    function testRedeemCollateralForDsc() public depositedCollateral mintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL_TO_REDEEM, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedDscAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(expectedDscAmount, AMOUNT_COLLATERAL - AMOUNT_COLLATERAL_TO_REDEEM);
    }

    ///////////////////////////
    // mintDsc Tests      ////
    /////////////////////////

    modifier mintedDsc() {
        vm.startPrank(USER);

        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testRevertsIfMintedIsZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
    }

    function testMintedDscAndGetAccountInfo() public depositedCollateral mintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedAmountDscToMint = AMOUNT_DSC_TO_MINT;
        assertEq(totalDscMinted, expectedAmountDscToMint);
    }

    ///////////////////////////
    // burnDsc Tests      ////
    /////////////////////////

    modifier burnedDsc() {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_BURN);
        dsce.burnDsc(AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        _;
    }

    function testRevertsIfBurnedIsZero() public depositedCollateral mintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDscAndGetAccountInfo() public depositedCollateral mintedDsc burnedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscBurned = (AMOUNT_DSC_TO_MINT - AMOUNT_DSC_TO_BURN);
        assertEq(totalDscMinted, expectedTotalDscBurned);
    }

    /////////////////////////////
    // liquidate Tests      ////
    ///////////////////////////

    function testRevertsIfLiquidateIsZero() public depositedCollateral mintedDsc {
        address USER2 = makeAddr("user2");
        vm.startPrank(USER2);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testCanLiquidateIfHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(10000 ether);
        vm.stopPrank();

        mockTokenPrice = MockV3Aggregator(ethUsdPriceFeed);
        mockTokenPrice.updateAnswer(1500e8);

        address USER2 = makeAddr("user2");
        ERC20Mock(weth).mint(USER2, STARTING_ERC20_BALANCE + AMOUNT_COLLATERAL);
        vm.startPrank(USER2);
        ERC20Mock(weth).approve(address(dsce), STARTING_ERC20_BALANCE + AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, STARTING_ERC20_BALANCE + AMOUNT_COLLATERAL);
        dsce.mintDsc(10000 ether);
        dsc.approve(address(dsce), 2500 ether);
        dsce.liquidate(weth, USER, 2500 ether);
        vm.stopPrank();
    }

    ////////////////////////////////////////
    // healthFactor & Account Tests    ////
    //////////////////////////////////////

    function testHealthFactorIsWorkingProperly() public depositedCollateral mintedDsc {
        address USER2 = makeAddr("user2");
        uint256 expectedHealthFactor = dsce.getHealthFactor(USER2);
        assert(expectedHealthFactor >= 1e18);
    }

    function testHealthFactorAndGetAccountInfo() public depositedCollateral mintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = AMOUNT_DSC_TO_MINT;
        uint256 expectedCollateralValueInUsd = AMOUNT_COLLATERAL;
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, (2000 * expectedCollateralValueInUsd));
    }

    function testCanGetAccountCollateralValue() public depositedCollateral {
        uint256 expectedCollateral = dsce.getAccountCollateralValue(USER);
        assertEq(expectedCollateral, (AMOUNT_COLLATERAL * 2000));
    }
}
