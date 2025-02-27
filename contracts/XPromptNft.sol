// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ERC721URIStorage } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract XPromptNft is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, Ownable {
    using Strings for uint256;

    // NFT struct to store basic details
    struct NFT {
        uint256 tokenId;
        string tokenURI;
        address owner;
        uint256 price;
        bool isListed;
        string prompt; // Store the AI prompt used to generate the image
        uint256 createdAt;
    }

    // Storage for all NFTs
    mapping(uint256 => NFT) public nfts;

    // Marketplace NFTs (listed NFTs)
    uint256[] private marketplaceNFTs;

    // Mapping from owner to their NFT IDs
    mapping(address => uint256[]) private ownerNFTs;

    // Events
    event Purchase(address indexed previousOwner, address indexed newOwner, uint price, uint nftID, string uri);
    event Minted(address indexed minter, uint price, uint nftID, string uri, string prompt);
    event PriceUpdate(address indexed owner, uint oldPrice, uint newPrice, uint nftID);
    event NftListStatus(address indexed owner, uint nftID, bool isListed);

    constructor() ERC721("XPromptNFT", "XPNT") {}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // Modified mint function to include prompt details
    function mint(
        string memory _tokenURI,
        address _toAddress,
        uint _price,
        string memory _prompt
    ) public whenNotPaused returns (uint) {
        uint _tokenId = totalSupply() + 1;

        // Create new NFT struct
        NFT memory newNFT = NFT({
            tokenId: _tokenId,
            tokenURI: _tokenURI,
            owner: _toAddress,
            price: _price,
            isListed: false, // Initially not listed in marketplace
            prompt: _prompt,
            createdAt: block.timestamp
        });

        // Store NFT data
        nfts[_tokenId] = newNFT;

        // Add to owner's portfolio
        ownerNFTs[_toAddress].push(_tokenId);

        _safeMint(_toAddress, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);

        emit Minted(_toAddress, _price, _tokenId, _tokenURI, _prompt);

        return _tokenId;
    }

    // List NFT in marketplace
    function sellNFT(uint256 _tokenId, uint256 _price) public returns (bool) {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");
        require(!nfts[_tokenId].isListed, "Already listed");

        // Update price if needed
        if (nfts[_tokenId].price != _price) {
            uint oldPrice = nfts[_tokenId].price;
            nfts[_tokenId].price = _price;
            emit PriceUpdate(msg.sender, oldPrice, _price, _tokenId);
        }

        // Mark as listed
        nfts[_tokenId].isListed = true;

        // Add to marketplace
        marketplaceNFTs.push(_tokenId);

        emit NftListStatus(msg.sender, _tokenId, true);

        return true;
    }

    // Buy NFT from marketplace
    function buyNFT(uint256 _tokenId) external payable {
        NFT storage nft = nfts[_tokenId];
        require(_exists(_tokenId), "NFT does not exist");
        require(nft.isListed, "NFT not listed for sale");
        require(msg.value >= nft.price, "Insufficient funds");
        require(msg.sender != ownerOf(_tokenId), "Cannot buy your own NFT");

        address previousOwner = nft.owner;

        // Process the trade
        _processNFTPurchase(_tokenId);

        emit Purchase(previousOwner, msg.sender, nft.price, _tokenId, nft.tokenURI);
    }

    // Internal function to process NFT purchase
    function _processNFTPurchase(uint256 _tokenId) internal {
        NFT storage nft = nfts[_tokenId];
        address payable seller = payable(nft.owner);
        address payable buyer = payable(msg.sender);
        uint256 salePrice = nft.price;

        // Transfer ownership
        _transfer(seller, buyer, _tokenId);

        // Update NFT data
        nft.owner = buyer;
        nft.isListed = false;

        // Calculate commission (2.5%)
        uint256 commission = salePrice / 40;
        uint256 sellerProceeds = salePrice - commission;

        // Transfer funds
        seller.transfer(sellerProceeds);
        payable(owner()).transfer(commission);

        // Refund excess payment
        if (msg.value > salePrice) {
            buyer.transfer(msg.value - salePrice);
        }

        // Remove from marketplace
        _removeFromMarketplace(_tokenId);

        // Remove from seller's portfolio
        _removeFromOwnerPortfolio(seller, _tokenId);

        // Add to buyer's portfolio
        ownerNFTs[buyer].push(_tokenId);
    }

    // Remove NFT from marketplace array
    function _removeFromMarketplace(uint256 _tokenId) internal {
        for (uint i = 0; i < marketplaceNFTs.length; i++) {
            if (marketplaceNFTs[i] == _tokenId) {
                // Replace with last element and pop
                marketplaceNFTs[i] = marketplaceNFTs[marketplaceNFTs.length - 1];
                marketplaceNFTs.pop();
                break;
            }
        }
    }

    // Remove NFT from owner's portfolio
    function _removeFromOwnerPortfolio(address owner, uint256 _tokenId) internal {
        uint256[] storage ownerTokens = ownerNFTs[owner];
        for (uint i = 0; i < ownerTokens.length; i++) {
            if (ownerTokens[i] == _tokenId) {
                // Replace with last element and pop
                ownerTokens[i] = ownerTokens[ownerTokens.length - 1];
                ownerTokens.pop();
                break;
            }
        }
    }

    // Cancel listing
    function cancelListing(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");
        require(nfts[_tokenId].isListed, "Not listed");

        nfts[_tokenId].isListed = false;

        // Remove from marketplace
        _removeFromMarketplace(_tokenId);

        emit NftListStatus(msg.sender, _tokenId, false);
    }

    // Get all marketplace NFTs
    function getMarketplaceNFTs() public view returns (NFT[] memory) {
        NFT[] memory listedNFTs = new NFT[](marketplaceNFTs.length);

        for (uint i = 0; i < marketplaceNFTs.length; i++) {
            listedNFTs[i] = nfts[marketplaceNFTs[i]];
        }

        return listedNFTs;
    }

    // Get NFT details
    function getNFTDetails(uint256 _tokenId) public view returns (NFT memory) {
        require(_exists(_tokenId), "NFT does not exist");
        return nfts[_tokenId];
    }

    // Get all NFTs owned by an address
    function getMyNFTs(address _owner) public view returns (NFT[] memory) {
        uint256[] storage ownerTokens = ownerNFTs[_owner];
        NFT[] memory myNFTs = new NFT[](ownerTokens.length);

        for (uint i = 0; i < ownerTokens.length; i++) {
            myNFTs[i] = nfts[ownerTokens[i]];
        }

        return myNFTs;
    }

    // Update NFT price
    function updatePrice(uint256 _tokenId, uint256 _price) public returns (bool) {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");

        uint oldPrice = nfts[_tokenId].price;
        nfts[_tokenId].price = _price;

        emit PriceUpdate(msg.sender, oldPrice, _price, _tokenId);
        return true;
    }

    // The following functions are overrides required by Solidity.
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
