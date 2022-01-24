// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../ERC721/ERC721Enumerable.sol";
import "../interfaces/INFTFactory.sol";
import "../lib/InitializableOwnable.sol";


contract InitializableERC721 is ERC721Enumerable, InitializableOwnable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Strings for uint256;
    using Address for address;

    address public factory;
    string public baseURI;
    uint256 public nextTokenId;
    uint256 public maxSupply;

    struct SaleConfig {
        uint256  startTime;
        uint256  endTime;
        address  saleToken;
        address  treasury;
    }

    SaleConfig public saleConfig;

    event Mint(address minter, uint price, uint256 tokenId);
    event SaleConfigChanged(uint256 startTime, uint256 endTime, address saleToken, address treasury);

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "not eoa");
        _;
    }

    function initialize(
        address _admin,
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        address _treasury,
        uint256 _maxSupply,
        string memory name,
        string memory symbol,
        string memory _baseURI
    ) public {
        InitializableOwnable._initialize();
        transferOwnership(_admin);
        maxSupply = _maxSupply;
        saleConfig = SaleConfig({
            startTime: _startTime,
            endTime: _endTime,
            saleToken: _saleToken,
            treasury: _treasury
        });
        _name = name;
        _symbol = symbol;
        baseURI = _baseURI;

       factory = _msgSender();
    }

    function setUpSale(
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        address _treasury
    )external onlyOwner {
        require(_startTime > block.timestamp, "invalid start time");
        require(_endTime > _startTime, "invalid end time");

        saleConfig = SaleConfig({
            startTime: _startTime,
            endTime: _endTime,
            saleToken: _saleToken,
            treasury: _treasury
        });

        emit SaleConfigChanged(_startTime, _endTime, _saleToken, _treasury);
    }

    function mint(uint256 tokenId, uint256 price, uint8 v, bytes32 r, bytes32 s) external payable onlyEOA {
        // Make sure sale config has been set up
        SaleConfig memory _saleConfig = saleConfig;
        require(_saleConfig.startTime > 0, "ERC721: sale not configured");
        require(_saleConfig.treasury != address(0), "ERC721: treasury not set");
        require(block.timestamp >= _saleConfig.startTime, "ERC721: sale not started");
        require(block.timestamp <= _saleConfig.endTime, "ERC721: sale already end");

        // check signature
        bytes32 messageHash = keccak256(abi.encodePacked(this, _msgSender(), tokenId, price));
        require(INFTFactory(factory).verifySignedMessage(messageHash, v, r, s), "ERC721: signer should sign buyer address and tokenId");

        require(tokenId + 1 <= maxSupply, "ERC721: invalid tokenId");

        if (_saleConfig.saleToken == address(0)) {
            require(price == msg.value, "ERC721: incorrect Ether value");
            // The contract never holds any Ether. Everything gets redirected to treasury directly.
            payable(_saleConfig.treasury).transfer(msg.value);
        }else{
            IERC20(_saleConfig.saleToken).safeTransferFrom(_msgSender(), _saleConfig.treasury, price);
        }

        _safeMint(_msgSender(), tokenId);

        emit Mint(_msgSender(), price, tokenId);
    }


    function setBaseURI(string calldata newbaseURI) external onlyOwner {
        baseURI = newbaseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(tokenId + 1 <= maxSupply, "ERC721: invalid tokenId");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";

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