// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./lib/LibRoles.sol";
import "./lib/CloneFactory.sol";
import "./Template/InitializableERC1155.sol";
import "./Template/InitializableERC721.sol";
import "./Template/BlindBox.sol";


contract NFTFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    using AddressUpgradeable for address;
    using LibRoles for LibRoles.Role;

    LibRoles.Role private _signers;
    // ============ Templates ============
    address public CLONE_FACTORY;
    address public ERC721_TEMPLATE;
    address public ERC1155_TEMPLATE;
    address public ERC721_BLINDBOX;

    // ============ Registry ============
    mapping(address => address[]) public USER_ERC721_REGISTRY;
    mapping(address => address[]) public USER_ERC1155_REGISTRY;
    mapping(address => address[]) public USER_BLINDBOX_REGISTRY;

    event NewERC721(address erc721, address creator);
    event NewERC1155(address erc1155, address creator);
    event NewBlindBox(address blindbox, address creator);
    event SignerAdded(address indexed account);
    event SignerRemoved(address indexed account);

    function initialize(
        address cloneFactory,
        address erc721Template,
        address erc1155Template,
        address blindboxTemplate, 
        address signer
    ) public initializer {

        __Ownable_init();
        __UUPSUpgradeable_init();

        CLONE_FACTORY = cloneFactory;
        ERC721_TEMPLATE = erc721Template;
        ERC1155_TEMPLATE = erc1155Template;
        ERC721_BLINDBOX = blindboxTemplate;
        _signers.add(signer);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}


    function isSigner(address account) internal view returns (bool) {
        return _signers.has(account);
    }

    function addSigner(address account) external onlyOwner {
        _signers.add(account);
        emit SignerAdded(account);
    }

    function removeSigner(address account) external onlyOwner {
        _signers.remove(account);
        emit SignerRemoved(account);
    }

    function verifySignedMessage(
        bytes32 messageHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public view returns (bool) {
         address recoveredSigner = ECDSAUpgradeable.recover(
            ECDSAUpgradeable.toEthSignedMessageHash(messageHash),
            v,
            r,
            s
        );
        return isSigner(recoveredSigner);
    }


    function changeERC721Template(address newERC721Template) external onlyOwner {
        ERC721_TEMPLATE = newERC721Template;
    }

    function changeERC1155Template(address newERC1155Template) external onlyOwner {
        ERC1155_TEMPLATE = newERC1155Template;
    }

    function changeBlindBoxTemplate(address newBlindBoxTemplate) external onlyOwner {
        ERC721_BLINDBOX = newBlindBoxTemplate;
    }

    function createERC721(
        address _admin,
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        address _treasury,
        uint256 _maxSupply,
        string memory _name,
        string memory _symbol,
        string memory _baseURI
    ) external returns (address newERC721) {
        newERC721 = ICloneFactory(CLONE_FACTORY).clone(ERC721_TEMPLATE);
        InitializableERC721(newERC721).initialize(_admin, _startTime,_endTime, _saleToken, _treasury,_maxSupply, _name, _symbol, _baseURI);
        USER_ERC721_REGISTRY[msg.sender].push(newERC721);
        emit NewERC721(newERC721, msg.sender);
    }

    function createBlindBox(
        address _admin,
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        uint256 _salePrice,
        address _treasury,
        uint256 _maxSupply,
        string memory _name,
        string memory _symbol,
        string memory _boxURI,
        string memory _baseURI
    ) external returns (address newBlindBox) {
        newBlindBox = ICloneFactory(CLONE_FACTORY).clone(ERC721_BLINDBOX);
        BlindBox(newBlindBox).initialize(_admin, _startTime, _endTime, _saleToken, _salePrice, _treasury,_maxSupply, _name, _symbol, _boxURI, _baseURI);
        USER_BLINDBOX_REGISTRY[msg.sender].push(newBlindBox);
        emit NewBlindBox(newBlindBox, msg.sender);
    }

    function createERC1155(
        address _admin,
        uint256 _startTime,
        uint256 _endTime,
        address _saleToken,
        address _treasury
    ) external returns (address newERC1155) {
        newERC1155 = ICloneFactory(CLONE_FACTORY).clone(ERC1155_TEMPLATE);
        InitializableERC1155(newERC1155).initialize(_admin, _startTime, _endTime, _saleToken, _treasury);
        USER_ERC1155_REGISTRY[msg.sender].push(newERC1155);
        emit NewERC1155(newERC1155, msg.sender);
    }

    function version() pure public returns(string memory) {
        return "v1";
    }

}