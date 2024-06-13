// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IERC6551Account } from "erc6551/interfaces/IERC6551Account.sol";
import { ERC6551, Receiver } from "@solady/src/accounts/ERC6551.sol";

import { IAccessController } from "./interfaces/access/IAccessController.sol";
import { IIPAccount } from "./interfaces/IIPAccount.sol";
import { MetaTx } from "./lib/MetaTx.sol";
import { Errors } from "./lib/Errors.sol";
import { IPAccountStorage } from "./IPAccountStorage.sol";

/// @title IPAccountImpl
/// @notice The Story Protocol's implementation of the IPAccount.
/// @custom:oz-upgrades-from contracts/old/v1.0.0/contracts/IPAccountImpl.sol:IPAccountImpl
contract IPAccountImpl is ERC6551, IPAccountStorage, IIPAccount {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable ACCESS_CONTROLLER;

    receive() external payable override(Receiver, IIPAccount) {}

    /// @notice Creates a new IPAccountImpl contract instance
    /// @dev Initializes the IPAccountImpl with an AccessController address which is stored
    /// in the implementation code's storage.
    /// This means that each cloned IPAccount will inherently use the same AccessController
    /// without the need for individual configuration.
    /// @param accessController The address of the AccessController contract to be used for permission checks
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address accessController,
        address ipAssetRegistry,
        address licenseRegistry,
        address moduleRegistry
    ) IPAccountStorage(ipAssetRegistry, licenseRegistry, moduleRegistry) {
        if (accessController == address(0)) revert Errors.IPAccount__ZeroAccessController();
        ACCESS_CONTROLLER = accessController;
    }

    /// @notice Checks if the contract supports a specific interface
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return bool is true if the contract supports the interface, false otherwise
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC6551, IPAccountStorage, IERC165) returns (bool) {
        return (interfaceId == type(IIPAccount).interfaceId ||
            interfaceId == type(IERC6551Account).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId));
    }

    /// @notice Returns the identifier of the non-fungible token which owns the account
    /// @return chainId The EIP-155 ID of the chain the token exists on
    /// @return tokenContract The contract address of the token
    /// @return tokenId The ID of the token
    function token() public view override(ERC6551, IIPAccount) returns (uint256, address, uint256) {
        return super.token();
    }

    /// @notice Checks if the signer is valid for the given data
    /// @param signer The signer to check
    /// @param data The data to check against
    /// @return The function selector if the signer is valid, 0 otherwise
    function isValidSigner(
        address signer,
        bytes calldata data
    ) public view override(ERC6551, IIPAccount) returns (bytes4) {
        return super.isValidSigner(signer, data);
    }

    /// @notice Returns the owner of the IP Account.
    /// @return The address of the owner.
    function owner() public view override(ERC6551, IIPAccount) returns (address) {
        return super.owner();
    }

    /// @notice Returns the IPAccount's internal nonce for transaction ordering.
    function state() public view override(ERC6551, IIPAccount) returns (bytes32 result) {
        return super.state();
    }

    /// @dev Checks if the signer is valid for the given data and recipient via the AccessController permission system.
    /// @param signer The signer to check
    /// @param to The recipient of the transaction
    /// @param data The calldata to check against
    /// @return bool is true if the signer is valid, false otherwise
    function _isValidSigner(address signer, address to, bytes calldata data) internal view returns (bool) {
        if (data.length > 0 && data.length < 4) {
            revert Errors.IPAccount__InvalidCalldata();
        }
        bytes4 selector = bytes4(0);
        if (data.length >= 4) {
            selector = bytes4(data[:4]);
        }
        // the check will revert if permission is denied
        IAccessController(ACCESS_CONTROLLER).checkPermission(address(this), signer, to, selector);
        return true;
    }

    /// @notice Executes a transaction from the IP Account on behalf of the signer.
    /// @param to The recipient of the transaction.
    /// @param value The amount of Ether to send.
    /// @param data The data to send along with the transaction.
    /// @param signer The signer of the transaction.
    /// @param deadline The deadline of the transaction signature.
    /// @param signature The signature of the transaction, EIP-712 encoded.
    function executeWithSig(
        address to,
        uint256 value,
        bytes calldata data,
        address signer,
        uint256 deadline,
        bytes calldata signature
    ) external payable returns (bytes memory result) {
        if (signer == address(0)) {
            revert Errors.IPAccount__InvalidSigner();
        }

        if (deadline < block.timestamp) {
            revert Errors.IPAccount__ExpiredSignature();
        }

        _updateStateForExecute(to, value, data);

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({ to: to, value: value, data: data, nonce: state(), deadline: deadline })
            )
        );

        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert Errors.IPAccount__InvalidSignature();
        }

        result = _execute(signer, to, value, data);
        emit ExecutedWithSig(to, value, data, state(), deadline, signer, signature);
    }

    /// @notice Executes a transaction from the IP Account.
    /// @param to The recipient of the transaction.
    /// @param value The amount of Ether to send.
    /// @param data The data to send along with the transaction.
    /// @return result The return data from the transaction.
    function execute(address to, uint256 value, bytes calldata data) external payable returns (bytes memory result) {
        _updateStateForExecute(to, value, data);
        result = _execute(msg.sender, to, value, data);
        emit Executed(to, value, data, state());
    }

    /// @dev Override 6551 execute function.
    /// Only "CALL" operation is supported.
    /// @param to The recipient of the transaction.
    /// @param value The amount of Ether to send.
    /// @param data The data to send along with the transaction.
    /// @param operation The operation type to perform, only 0 - CALL is supported.
    /// @return result The return data from the transaction.
    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) public payable override returns (bytes memory result) {
        // Only "CALL" operation is supported.
        if (operation != 0) {
            revert Errors.IPAccount__InvalidOperation();
        }
        _updateStateForExecute(to, value, data);
        result = _execute(msg.sender, to, value, data);
        emit Executed(to, value, data, state());
    }

    /// @notice Executes a batch of transactions from the IP Account.
    /// @param calls The array of calls to execute.
    /// @param operation The operation type to perform, only 0 - CALL is supported.
    /// @return results The return data from the transactions.
    function executeBatch(
        Call[] calldata calls,
        uint8 operation
    ) public payable override returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            results[i] = execute(calls[i].target, calls[i].value, calls[i].data, operation);
        }
    }

    /// @dev Executes a transaction from the IP Account.
    function _execute(
        address signer,
        address to,
        uint256 value,
        bytes calldata data
    ) internal returns (bytes memory result) {
        require(_isValidSigner(signer, to, data), "Invalid signer");

        bool success;
        (success, result) = to.call{ value: value }(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @dev Updates the IP Account's state all execute transactions.
    /// @param to The "target" of the execute transactions.
    /// @param value The amount of Ether to send.
    /// @param data The data to send along with the transaction.
    function _updateStateForExecute(address to, uint256 value, bytes calldata data) internal {
        bytes32 newState = keccak256(
            abi.encode(state(), abi.encodeWithSignature("execute(address,uint256,bytes)", to, value, data))
        );
        assembly {
            sstore(_ERC6551_STATE_SLOT, newState)
        }
    }

    /// @dev Override Solady 6551 _isValidSigner function.
    /// @param signer The signer to check
    /// @param extraData The extra data to check against, it should bethe address of the recipient for IPAccount
    /// @param context The context for validating the signer
    /// @return bool is true if the signer is valid, false otherwise
    function _isValidSigner(address signer, bytes32 extraData, bytes calldata context) internal view returns (bool) {
        return _isValidSigner(signer, address(uint160(uint256(extraData))), context);
    }

    /// @dev Override Solady EIP712 function and return EIP712 domain name for IPAccount.
    function _domainNameAndVersion() internal view override returns (string memory name, string memory version) {
        name = "Story Protocol IP Account";
        version = "1";
    }
}
