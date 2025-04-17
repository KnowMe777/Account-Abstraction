// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC } from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import { Transaction, MemoryTransactionHelper } from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import { SystemContractsCaller } from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import { NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, DEPLOYER_SYSTEM_CONTRACT } from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import { INonceHolder  } from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ECDSA } from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import { Utils } from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";


contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    /*/////////////////////////////////////////
                   ERRORS
   /////////////////////////////////////////*/

    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotFromBootLoaderOrOwner();
    error ZkMinimalAccount__FailedToPay();
    error ZkMinimalAccount__InvalidSignature();



    /*/////////////////////////////////////////
                   MODIFIERS
   /////////////////////////////////////////*/

    modifier requireFromBootLoader() {
        if (msg.sender != address(BOOTLOADER_FORMAL_ADDRESS)) {
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    modifier requireFromBootLoaderOrOwner() {
        if (msg.sender != address(BOOTLOADER_FORMAL_ADDRESS) &&  msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootLoaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    /*/////////////////////////////////////////
                EXTERNAL FUNCTIONS
   /////////////////////////////////////////*/

    function validateTransaction(bytes32 /*_txHash*/, bytes32 /*_suggestedSignedHash*/, Transaction memory _transaction) external payable requireFromBootLoader returns (bytes4 magic)  {
        return _validateTransaction(_transaction);
    }

    function executeTransaction(bytes32 /*_txHash*/, bytes32 /*_suggestedSignedHash*/,  Transaction memory _transaction) external payable requireFromBootLoaderOrOwner {
       return _executeTenasaction(_transaction);
    }

    function executeTransactionFromOutside(Transaction memory _transaction) external payable { 
       bytes4 magic =  _validateTransaction(_transaction);
       if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
        revert ZkMinimalAccount__InvalidSignature();
       }
        _executeTenasaction(_transaction);
    }

    function payForTransaction(bytes32 /*_txHash*/, bytes32 /*_suggestedSignedHash*/, Transaction memory _transaction) external payable {
        bool success  = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    } 

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction) external payable {}

    /*/////////////////////////////////////////
                INTERNAL FUNCTIONS
   /////////////////////////////////////////*/

   function _validateTransaction(Transaction memory _transaction) internal returns(bytes4 magic) {
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        uint256 totalRequiredBalance  = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        bytes32 txHash = _transaction.encodeHash();
        bytes32 convertedHash = MessageHashUtils.toEthSignedMessageHash(txHash);
        address signer = ECDSA.recover(convertedHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes2(0);
        }
        return magic;
   }

   function _executeTenasaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success ;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if(!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
   }
 }