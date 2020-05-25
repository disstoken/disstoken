pragma solidity ^0.5.0;

import "../node_modules/openzeppelin-solidity/contracts/introspection/IERC165.sol";

/**
 * @dev Required interface of a DissToken compliant contract.
 */
contract IDissToken is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Returns the number of NFTs in `owner`'s account.
     */
    function balanceOf(address owner) public view returns (uint256 balance);

    /**
     * @dev Returns the owner of the NFT specified by `tokenId`.
     */
    function ownerOf(uint256 tokenId) public view returns (address owner);

    /**
     * @dev Transfers a specific NFT (`tokenId`) from one account (`from`) to
     * another (`to`).
     *
     *
     * Requirements:
     * - `from`, `to` cannot be zero.
     * - `tokenId` must be owned by `from`.
     * - caller must be `from`
     */

    function transferFrom(address from, address to, uint256 tokenId) public payable;
}
