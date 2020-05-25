pragma solidity ^0.5.0;
//../node_modules/openzeppelin-solidity/contracts/
import "../node_modules/openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "./IDissTokenReceiver.sol";
import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-solidity/contracts/utils/Address.sol";
import "../node_modules/openzeppelin-solidity/contracts/drafts/Counters.sol";
import "../node_modules/openzeppelin-solidity/contracts/introspection/ERC165.sol";
import "../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../node_modules/openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "./IDissToken.sol";

/**
 * @title ERC721 Non-Fungible Token Standard basic implementation
 * @dev see https://eips.ethereum.org/EIPS/eip-721
 */
contract DissToken is ERC165, IDissToken, Ownable, Pausable {
    using SafeMath for uint256;
    using Address for address;
    using Counters for Counters.Counter;

    struct Diss {
        string text;
        uint256 nextTransactionPrice;
    }

    Diss[] public _disses;

    uint256 public _minimumMintPrice;
    uint256 public _transactionRateInPercent;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    //bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    bytes4 private constant _DissToken_RECEIVED = bytes4(keccak256("onDissTokenReceived(address,address,uint256,bytes)"));

    // Mapping from token ID to owner
    mapping (uint256 => address) public _dissToOwner;

    // Mapping from owner to number of owned token
    mapping (address => Counters.Counter) public _ownedDissesCount;

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /**
     * @dev Modifier to check if enough ether is sent for the transfer
     */
    modifier enoughEther(uint256 tokenId) {
        require(msg.value >= _disses[tokenId].nextTransactionPrice, "DissToken: Not enough ether sent");
        _;
    }

    constructor (uint256 minimumMintPrice, uint256 transactionRateInPercent) public {
        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721);
        _minimumMintPrice = minimumMintPrice;
        _transactionRateInPercent = transactionRateInPercent;
    }

    function() external payable { }

    function withdraw() external onlyOwner {
        address payable _owner = address(uint160(owner()));
        _owner.transfer(address(this).balance);
    }

    function setTransactionRateInPercent(uint256 transactionRateInPercent) public onlyOwner {
        _transactionRateInPercent = transactionRateInPercent;
    }

    function setMinimumMintPrice(uint256 minimumMintPrice) public onlyOwner {
        require(minimumMintPrice >= 0, "DissToken: _minimumMintPrice must be >= 0");
        _minimumMintPrice = minimumMintPrice;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param owner address to query the balance of
     * @return uint256 representing the amount owned by the passed address
     */
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "DissToken: Balance query for the zero address");

        return _ownedDissesCount[owner].current();
    }

    /**
     * @dev Gets the owner of the specified token ID.
     * @param tokenId uint256 ID of the token to query the owner of
     * @return address currently marked as the owner of the given token ID
     */
    function ownerOf(uint256 tokenId) public view returns (address) {
        require(_exists(tokenId), "DissToken: Owner query for nonexistent token");
        address owner = _dissToOwner[tokenId];
        return owner;
    }

    function getAllDissesOfOwner(address owner) public view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](_ownedDissesCount[owner].current());
        uint256 counter = 0;
        for (uint256 i = 0; i < _disses.length; i++) {
            if (_dissToOwner[i] == owner) {
                result[counter] = i;
                counter++;
            }
        }
        return result;
    }

    /**
     * @dev Safely transfers the ownership of a given token ID to another address
     * If the target address is a contract, it must implement `onERC721Received`,
     * which is called upon a safe transfer, and return the magic value
     * `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`; otherwise,
     * the transfer is reverted.
     * Requires the msg.sender to be the owner, approved, or operator
     * @param from current owner of the token
     * @param to address to receive the ownership of the given token ID
     * @param tokenId uint256 ID of the token to be transferred
     */
    function transferFrom(address from, address to, uint256 tokenId) public payable whenNotPaused enoughEther(tokenId) {
        require(_isDissOwner(msg.sender, tokenId), "DissToken: Transfer caller is not owner");
        require(_checkDissTokenReceived(from, to, tokenId, ""), "DissToken: Transfer to non ERC721Receiver implementer");
        _transferFrom(from, to, tokenId);
    }

    /**
     * @dev Returns whether the specified token exists.
     * @param tokenId uint256 ID of the token to query the existence of
     * @return bool whether the token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        address owner = _dissToOwner[tokenId];
        return owner != address(0);
    }

    /**
     * @dev Returns whether the given spender can transfer a given token ID.
     * @param spender address of the spender to query
     * @param tokenId uint256 ID of the token to be transferred
     * @return bool whether the msg.sender is approved for the given token ID,
     * is an operator of the owner, or is the owner of the token
     */
    function _isDissOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner);
    }

    function mint(address to, string calldata text) external payable whenNotPaused {
        require(msg.value >= _minimumMintPrice, "DissToken: Not enough ether to mint");
        _mint(to, text, msg.value);
    }

    function mintOwner(address to, string calldata text) external onlyOwner {
        _mint(to, text, _minimumMintPrice);
    }

    /**
     * @dev Internal function to mint a new token.
     * Reverts if the given token ID already exists.
     * @param to The address that will own the minted token
     * @param text The text of the diss, i.e. the diss
     */
    function _mint(address to, string memory text, uint256 mintPrice) internal {
        require(to != address(0), "DissToken: Mint to the zero address");

        uint256 nextTransactionPrice = _calculateNextTransactionPrice(mintPrice);
        uint tokenId = _disses.push(Diss(text, nextTransactionPrice)) - 1;
        require(_checkDissTokenReceived(address(69), to, tokenId, ""), "DissToken: Mint to non ERC721Receiver implementer");

        _dissToOwner[tokenId] = to;
        _ownedDissesCount[to].increment();

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Internal function to burn a specific token.
     * Reverts if the token does not exist.
     * Deprecated, use _burn(uint256) instead.
     * @param owner owner of the token to burn
     * @param tokenId uint256 ID of the token being burned
     */
    function _burn(address owner, uint256 tokenId) internal {
        require(_isDissOwner(owner, tokenId), "DissToken: Burn of token that is not own");

        _ownedDissesCount[owner].decrement();
        _dissToOwner[tokenId] = address(0);

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Internal function to burn a specific token.
     * Reverts if the token does not exist.
     * @param tokenId uint256 ID of the token being burned
     */
    function burn(uint256 tokenId) public payable whenNotPaused {
        require(msg.value >= _disses[tokenId].nextTransactionPrice * 10, "DissToken: Not enough ether sent");
        _burn(msg.sender, tokenId);
    }

    /**
     * @dev Internal function to transfer ownership of a given token ID to another address.
     * As opposed to transferFrom, this imposes no restrictions on msg.sender.
     * @param from current owner of the token
     * @param to address to receive the ownership of the given token ID
     * @param tokenId uint256 ID of the token to be transferred
     */
    function _transferFrom(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "DissToken: Transfer of token that is not own");
        require(to != address(0), "DissToken: Transfer to the zero address");

        _ownedDissesCount[from].decrement();
        _ownedDissesCount[to].increment();

        _dissToOwner[tokenId] = to;

        uint256 currentPrice = _disses[tokenId].nextTransactionPrice;
        _disses[tokenId].nextTransactionPrice = _calculateNextTransactionPrice(currentPrice);

        emit Transfer(from, to, tokenId);
    }

    function _calculateNextTransactionPrice(uint256 currentPrice) internal view returns(uint256) {
        uint256 hundred = 100;
        uint256 divisedByHundred = hundred.div(_transactionRateInPercent);
        uint256 addToCurrentPrice = currentPrice.div(divisedByHundred);
        return currentPrice.add(addToCurrentPrice);
    }

    /**
     * @dev Internal function to invoke `onERC721Received` on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * This function is deprecated.
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkDissTokenReceived(address from, address to, uint256 tokenId, bytes memory _data)
        internal returns (bool)
    {
        if (!to.isContract()) {
            return true;
        }

        bytes4 retval = IDissTokenReceiver(to).onDissTokenReceived(msg.sender, from, tokenId, _data);
        return (retval == _DissToken_RECEIVED);
    }
}