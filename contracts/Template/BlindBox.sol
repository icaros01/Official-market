// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../lib/InitializableOwnable.sol";
import "../interfaces/INFTFactory.sol";
import "../ERC721/ERC721Enumerable.sol";


contract BlindBox is ERC721Enumerable, InitializableOwnable, Pausable {

    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using SafeMath for uint256;
    using Address for address;

    EnumerableSet.UintSet private pools;
    address public factory;

    uint256 public nextTokenId;
    string public boxURI;
    string public baseURI;

    uint256 public maxSupply;

    struct SaleConfig {
        uint256  startTime;
        uint256  endTime;
        address  saleToken;
        uint256  salePrice;
        address  treasury;
    }

    struct boxState {
        bool isOpen;
        uint256 realTokenId;
    }

    // Mapping from blindbox token ID to index of the token ID
    mapping(uint256 => boxState) private boxStatus;
    SaleConfig public saleConfig;


    event SaleConfigChanged(uint256 startTime, uint256 endTime, address saleToken, uint256 salePrice, address treasury);
    event IsBurnEnabledChanged(bool newIsBurnEnabled);
    event BaseURIChanged(string newBaseURI);
    event BoxURIChanged(string newBoxURI);
    event SaleMint(address minter, uint256 tokenId);
    event Open(address owner, uint256 boxId, uint256 tokenId);

    
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "not eoa");
        _;
    }

    function initialize(
        address _admin,
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        uint256 _salePrice,
        address _treasury,
        uint256 _maxSupply,
        string memory name,
        string memory symbol,
        string memory _boxURI,
        string memory _baseURI
    ) public {
        InitializableOwnable._initialize();
        transferOwnership(_admin);
        maxSupply = _maxSupply;
        saleConfig = SaleConfig({
            startTime: _startTime,
            endTime: _endTime,
            saleToken: _saleToken,
            salePrice: _salePrice,
            treasury: _treasury
        });
        _name = name;
        _symbol = symbol;
        boxURI = _boxURI;
        baseURI = _baseURI;

        factory = _msgSender();
    }

    function setUpSale(
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        uint256 _salePrice,
        address _treasury
    )external onlyOwner {
        require(_startTime > block.timestamp, "invalid start time");
        require(_endTime > _startTime, "invalid end time");

        saleConfig = SaleConfig({
            startTime: _startTime,
            endTime: _endTime,
            saleToken: _saleToken,
            salePrice: _salePrice,
            treasury: _treasury
        });

        emit SaleConfigChanged(_startTime, _endTime, _saleToken, _salePrice, _treasury);
    }



    function setBaseURI(string calldata newbaseURI) external onlyOwner {
        baseURI = newbaseURI;
        emit BaseURIChanged(newbaseURI);
    }

    function setBoxURI(string calldata newboxURI) external onlyOwner {
        boxURI = newboxURI;
        emit BoxURIChanged(newboxURI);
    }

    function mint(uint256 count, uint8 v, bytes32 r, bytes32 s) external payable onlyEOA {
        bytes32 messageHash = keccak256(abi.encodePacked(this, _msgSender(), count));
        require(INFTFactory(factory).verifySignedMessage(messageHash, v, r, s),"BlindBox: signer should sign buyer address and tokenId");

        // Gas optimization
        uint256 _nextTokenId = nextTokenId;

        // Make sure sale config has been set up
        SaleConfig memory _saleConfig = saleConfig;
        require(_saleConfig.startTime > 0, "BlindBox: sale not configured");
        require(_saleConfig.salePrice > 0, "BlindBox: sale price not set");
        require(_saleConfig.treasury != address(0), "BlindBox: treasury not set");
        require(count > 0, "BlindBox: invalid count");
        require(block.timestamp >= _saleConfig.startTime, "BlindBox: sale not started");
        require(block.timestamp <= _saleConfig.endTime, "BlindBox: sale already end");

        require(_nextTokenId + count <= maxSupply, "BlindBox: max supply exceeded");
        if (_saleConfig.saleToken == address(0)) {
            require(_saleConfig.salePrice * count == msg.value, "BlindBox: incorrect Ether value");
            // The contract never holds any Ether. Everything gets redirected to treasury directly.
            payable(_saleConfig.treasury).transfer(msg.value);
        }else{
            uint256 amount = _saleConfig.salePrice * count;
            IERC20(_saleConfig.saleToken).safeTransferFrom(_msgSender(), _saleConfig.treasury, amount);
        }

        for (uint256 ind = 0; ind < count; ind++) {
            _safeMint(_msgSender(), _nextTokenId + ind);
            pools.add(_nextTokenId + ind);
        }

        nextTokenId += count;

        emit SaleMint(_msgSender(), _nextTokenId);
    }

    function _generateSignature(uint256 salt) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, salt)));
    }


    function open(uint256 _boxTokenId, uint8 v, bytes32 r, bytes32 s) external onlyEOA {

        require(ownerOf(_boxTokenId) == _msgSender(), "BlindBox: not owner");
        require(boxStatus[_boxTokenId].isOpen == false, "BlindBox: box already open");

        bytes32 messageHash = keccak256(abi.encodePacked(this, _msgSender(), _boxTokenId));
        require(INFTFactory(factory).verifySignedMessage(messageHash, v, r, s),"BlindBox: signer should sign buyer address and tokenId");

        uint256 salt = uint256(keccak256(abi.encodePacked(msg.sender, _boxTokenId, pools.length())));
        uint256 seed = _generateSignature(salt);
        uint256 randomIdx = uint256(keccak256(abi.encodePacked(seed))).mod(pools.length());
        uint256 tokenId = pools.at(randomIdx);
        pools.remove(tokenId);
        boxStatus[_boxTokenId].isOpen = true;
        boxStatus[_boxTokenId].realTokenId = tokenId;
        emit Open(_msgSender(), _boxTokenId, tokenId);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        // check blindbox status
        if(boxStatus[tokenId].isOpen == true){
            tokenId = boxStatus[tokenId].realTokenId;
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
        }else{
            return bytes(boxURI).length > 0 ? string(abi.encodePacked(boxURI, tokenId.toString())) : "";
        }
    }

    function setPause() external onlyOwner {
        _pause();
    }

    function unsetPause() external onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        require(!paused(), "ERC721Pausable: token transfer while paused");
    }


}