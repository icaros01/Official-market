// SPDX-License-Identifier: MIT  
pragma solidity 0.8.4;


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../lib/InitializableOwnable.sol";
import "../interfaces/INFTFactory.sol";
import "../ERC1155/ERC1155.sol";
import "../interfaces/INFTFactory.sol";

contract InitializableERC1155 is InitializableOwnable, ERC1155 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Strings for uint256;
    using Address for address;
    
    mapping (uint256 => string) private _tokenURIs;
    string internal _baseUri = "";

    address public factory;


    struct SaleConfig {
        uint256  startTime;
        uint256  endTime;
        address  saleToken;
        address  treasury;
    }

    SaleConfig public saleConfig;

    // ============ Event =============
    event Mint(address creator, uint256 tokenId, uint256 price, uint256 amount);

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "not eoa");
        _;
    }

    function initialize(
        address _admin,
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        address _treasury
    ) public {
        InitializableOwnable._initialize();
        transferOwnership(_admin);
        saleConfig = SaleConfig({
            startTime: _startTime,
            endTime: _endTime,
            saleToken: _saleToken,
            treasury: _treasury
        });

        factory = _msgSender();
    }

    function mint(uint256 tokenId, uint256 amount, uint256 price, string calldata _uri, uint8 v, bytes32 r, bytes32 s) external payable onlyEOA {

        // Make sure sale config has been set up
        SaleConfig memory _saleConfig = saleConfig;
        require(_saleConfig.startTime > 0, "ERC1155: sale not configured");
        require(_saleConfig.treasury != address(0), "ERC1155: treasury not set");
        require(block.timestamp >= _saleConfig.startTime, "ERC1155: sale not started");
        require(block.timestamp <= _saleConfig.endTime, "ERC1155: sale already end");
        
        // check signature
        bytes32 messageHash = keccak256(abi.encodePacked(this, _msgSender(), tokenId, amount, price, _uri));
        require(INFTFactory(factory).verifySignedMessage(messageHash, v, r, s), "ERC1155: signer should sign buyer address and tokenId");

        if (_saleConfig.saleToken == address(0)) {
            require(price * amount == msg.value, "ERC1155: incorrect Ether value");
            // The contract never holds any Ether. Everything gets redirected to treasury directly.
            payable(_saleConfig.treasury).transfer(msg.value);
        }else{
            uint256 value = amount * price;
            IERC20(_saleConfig.saleToken).safeTransferFrom(msg.sender, _saleConfig.treasury, value);
        }
        _mint(msg.sender, tokenId, amount, "");
        _setTokenURI(tokenId, _uri);  
        emit Mint(msg.sender, tokenId, price, amount);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseUri;

        if (bytes(base).length == 0) {
            return _tokenURI;
        }

        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.uri(tokenId);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal {
        _tokenURIs[tokenId] = _tokenURI;
    }

}