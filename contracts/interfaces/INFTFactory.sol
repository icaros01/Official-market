// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface INFTFactory {
    function verifySignedMessage(bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) external view returns (bool);
}