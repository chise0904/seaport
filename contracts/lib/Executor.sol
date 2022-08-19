// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ConduitInterface } from "../interfaces/ConduitInterface.sol";

import { ConduitItemType } from "../conduit/lib/ConduitEnums.sol";

import { ItemType } from "./ConsiderationEnums.sol";

import { ReceivedItem } from "./ConsiderationStructs.sol";

import { Verifiers } from "./Verifiers.sol";

import { TokenTransferrer } from "./TokenTransferrer.sol";

import "./ConsiderationConstants.sol";

/**
 * @title Executor
 * @author 0age
 * @notice Executor contains functions related to processing executions (i.e.
 *         transferring items, either directly or via conduits).
 */
contract Executor is Verifiers, TokenTransferrer {
    /**
     * @dev Derive and set hashes, reference chainId, and associated domain
     *      separator during deployment.
     *
     * @param conduitController A contract that deploys conduits, or proxies
     *                          that may optionally be used to transfer approved
     *                          ERC20/721/1155 tokens.
     */
    constructor(address conduitController) Verifiers(conduitController) {}

    /**
     * @dev Internal function to transfer a given item, either directly or via
     *      a corresponding conduit.
     *
     * @param item        The item to transfer, including an amount and a
     *                    recipient.
     * @param from        The account supplying the item.
     * @param conduitKey  A bytes32 value indicating what corresponding conduit,
     *                    if any, to source token approvals from. The zero hash
     *                    signifies that no conduit should be used, with direct
     *                    approvals set on this contract.
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     */
    //  _transferConsiderationItem(
    //      considerationItem,
    //      msg.sender,
    //      fulfillerConduitKey,
    //      accumulator
    //  );
    function _transfer(
        ReceivedItem memory item,
        address from,
        bytes32 conduitKey,
        bytes memory accumulator
    ) internal {
        // If the item type indicates Ether or a native token...
        if (item.itemType == ItemType.NATIVE) {
            // Ensure neither the token nor the identifier parameters are set.
            if ((uint160(item.token) | item.identifier) != 0) {
                revert UnusedItemParameters();
            }

            // transfer the native tokens to the recipient.
            _transferEth(item.recipient, item.amount);
        } else if (item.itemType == ItemType.ERC20) {
            // Ensure that no identifier is supplied.
            if (item.identifier != 0) {
                revert UnusedItemParameters();
            }

            // Transfer ERC20 tokens from the source to the recipient.
            _transferERC20(
                item.token,
                from,
                item.recipient,
                item.amount,
                conduitKey,
                accumulator
            );
        } else if (item.itemType == ItemType.ERC721) {
            // Transfer ERC721 token from the source to the recipient.
            _transferERC721(
                item.token,
                from,
                item.recipient,
                item.identifier,
                item.amount,
                conduitKey,
                accumulator
            );
        } else {
            // Transfer ERC1155 token from the source to the recipient.
            _transferERC1155(
                item.token,
                from,
                item.recipient,
                item.identifier,
                item.amount,
                conduitKey,
                accumulator
            );
        }
    }

    /**
     * @dev Internal function to transfer an individual ERC721 or ERC1155 item
     *      from a given originator to a given recipient. The accumulator will
     *      be bypassed, meaning that this function should be utilized in cases
     *      where multiple item transfers can be accumulated into a single
     *      conduit call. Sufficient approvals must be set, either on the
     *      respective conduit or on this contract itself.
     *
     * @param itemType   The type of item to transfer, either ERC721 or ERC1155.
     * @param token      The token to transfer.
     * @param from       The originator of the transfer.
     * @param to         The recipient of the transfer.
     * @param identifier The tokenId to transfer.
     * @param amount     The amount to transfer.
     * @param conduitKey A bytes32 value indicating what corresponding conduit,
     *                   if any, to source token approvals from. The zero hash
     *                   signifies that no conduit should be used, with direct
     *                   approvals set on this contract.
     */
    //  _transferIndividual721Or1155Item(
    //      offeredItemType,
    //      parameters.offerToken,
    //      parameters.offerer,
    //      msg.sender,
    //      parameters.offerIdentifier,
    //      parameters.offerAmount,
    //      conduitKey
    //  );
    function _transferIndividual721Or1155Item(
        ItemType itemType,
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount,
        bytes32 conduitKey
    ) internal {
        // Determine if the transfer is to be performed via a conduit.
        if (conduitKey != bytes32(0)) {
            // Use free memory pointer as calldata offset for the conduit call.
            uint256 callDataOffset;

            // Utilize assembly to place each argument in free memory.
            assembly {
                // 這邊就是要構建調用 conduit 的 execute() 的 calldata
                // 所以會先塞 execute() 的 function selector
                // 再來塞 execute() 的參數 ConduitTransfer[]

                // Retrieve the free memory pointer and use it as the offset.
                callDataOffset := mload(FreeMemoryPointerSlot) // FreeMemoryPointerSlot = 0x40;

                // Write ConduitInterface.execute.selector to memory.
                // 先放 execute() 的 function selector
                mstore(callDataOffset, Conduit_execute_signature) // Conduit_execute_signature = 0x4ce34aa200000000000000000000000000000000000000000000000000000000

                // function execute(ConduitTransfer[] calldata transfers)
                // struct ConduitTransfer {
                //     ConduitItemType itemType; // 0x00
                //     address token;            // 0x20
                //     address from;             // 0x40
                //     address to;               // 0x60
                //     uint256 identifier;       // 0x80
                //     uint256 amount;           // 0xa0
                // }

                
                // uint256 constant Conduit_execute_ConduitTransfer_offset_ptr = 0x04;
                // uint256 constant Conduit_execute_ConduitTransfer_length_ptr = 0x24;

                // uint256 constant Conduit_execute_ConduitTransfer_ptr = 0x20;
                // uint256 constant Conduit_execute_ConduitTransfer_length = 0x01;

                // Write the offset to the ConduitTransfer array in memory.
                mstore(
                    add(
                        callDataOffset,
                        Conduit_execute_ConduitTransfer_offset_ptr 
                    ),
                    Conduit_execute_ConduitTransfer_ptr
                )

                // Write the length of the ConduitTransfer array to memory.
                mstore(
                    add(
                        callDataOffset,
                        Conduit_execute_ConduitTransfer_length_ptr 
                    ),
                    Conduit_execute_ConduitTransfer_length
                )

                // Write the item type to memory.
                mstore(
                    add(callDataOffset, Conduit_execute_transferItemType_ptr),
                    itemType
                )

                // Write the token to memory.
                mstore(
                    add(callDataOffset, Conduit_execute_transferToken_ptr),
                    token
                )

                // Write the transfer source to memory.
                mstore(
                    add(callDataOffset, Conduit_execute_transferFrom_ptr),
                    from
                )

                // Write the transfer recipient to memory.
                mstore(add(callDataOffset, Conduit_execute_transferTo_ptr), to)

                // Write the token identifier to memory.
                mstore(
                    add(callDataOffset, Conduit_execute_transferIdentifier_ptr),
                    identifier
                )

                // Write the transfer amount to memory.
                mstore(
                    add(callDataOffset, Conduit_execute_transferAmount_ptr),
                    amount
                )
            }

            // Perform the call to the conduit.
            _callConduitUsingOffsets(
                conduitKey,
                callDataOffset,
                OneConduitExecute_size // OneConduitExecute_size = 0x104 = 260
            );
        } else {
            // Otherwise, determine whether it is an ERC721 or ERC1155 item.
            if (itemType == ItemType.ERC721) {
                // Ensure that exactly one 721 item is being transferred.
                if (amount != 1) {
                    revert InvalidERC721TransferAmount();
                }

                // Perform transfer via the token contract directly.
                _performERC721Transfer(token, from, to, identifier);
            } else {
                // Perform transfer via the token contract directly.
                _performERC1155Transfer(token, from, to, identifier, amount);
            }
        }
    }

    /**
     * @dev Internal function to transfer Ether or other native tokens to a
     *      given recipient.
     *
     * @param to     The recipient of the transfer.
     * @param amount The amount to transfer.
     */
    function _transferEth(address payable to, uint256 amount) internal {
        // Ensure that the supplied amount is non-zero.
        _assertNonZeroAmount(amount);

        // Declare a variable indicating whether the call was successful or not.
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        // If the call fails...
        if (!success) {
            // Revert and pass the revert reason along if one was returned.
            _revertWithReasonIfOneIsReturned();

            // Otherwise, revert with a generic error message.
            revert EtherTransferGenericFailure(to, amount);
        }
    }

    /**
     * @dev Internal function to transfer ERC20 tokens from a given originator
     *      to a given recipient using a given conduit if applicable. Sufficient
     *      approvals must be set on this contract or on a respective conduit.
     *
     * @param token       The ERC20 token to transfer.
     * @param from        The originator of the transfer.
     * @param to          The recipient of the transfer.
     * @param amount      The amount to transfer.
     * @param conduitKey  A bytes32 value indicating what corresponding conduit,
     *                    if any, to source token approvals from. The zero hash
     *                    signifies that no conduit should be used, with direct
     *                    approvals set on this contract.
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     */
    function _transferERC20(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes32 conduitKey,
        bytes memory accumulator
    ) internal {
        // Ensure that the supplied amount is non-zero.
        _assertNonZeroAmount(amount);

        // Trigger accumulated transfers if the conduits differ.
        _triggerIfArmedAndNotAccumulatable(accumulator, conduitKey);

        // If no conduit has been specified...
        if (conduitKey == bytes32(0)) {
            // Perform the token transfer directly.
            _performERC20Transfer(token, from, to, amount);
        } else {
            // Insert the call to the conduit into the accumulator.
            _insert(
                conduitKey,
                accumulator,
                ConduitItemType.ERC20,
                token,
                from,
                to,
                uint256(0),
                amount
            );
        }
    }

    /**
     * @dev Internal function to transfer a single ERC721 token from a given
     *      originator to a given recipient. Sufficient approvals must be set,
     *      either on the respective conduit or on this contract itself.
     *
     * @param token       The ERC721 token to transfer.
     * @param from        The originator of the transfer.
     * @param to          The recipient of the transfer.
     * @param identifier  The tokenId to transfer (must be 1 for ERC721).
     * @param amount      The amount to transfer.
     * @param conduitKey  A bytes32 value indicating what corresponding conduit,
     *                    if any, to source token approvals from. The zero hash
     *                    signifies that no conduit should be used, with direct
     *                    approvals set on this contract.
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     */
    // 用 ERC20 去換 ERC721
    //  _transferERC721(
    //      parameters.offerToken,
    //      parameters.offerer,
    //      msg.sender,
    //      parameters.offerIdentifier,
    //      parameters.offerAmount,
    //      conduitKey,
    //      accumulator
    //  );

    // 買家用 ERC721 去換 賣家的ERC20
    // _transferERC721(
    //     parameters.considerationToken,
    //     msg.sender,
    //     parameters.offerer,
    //     parameters.considerationIdentifier,
    //     parameters.considerationAmount,
    //     conduitKey,
    //     accumulator
    // );
    // 這種order
    // 賣家會填
    
    function _transferERC721(
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount,
        bytes32 conduitKey,
        bytes memory accumulator
    ) internal {
        // Trigger accumulated transfers if the conduits differ.
        _triggerIfArmedAndNotAccumulatable(accumulator, conduitKey);

        // If no conduit has been specified...
        if (conduitKey == bytes32(0)) {
            // Ensure that exactly one 721 item is being transferred.
            if (amount != 1) {
                revert InvalidERC721TransferAmount();
            }

            // Perform transfer via the token contract directly.
            _performERC721Transfer(token, from, to, identifier);
        } else {
            // Insert the call to the conduit into the accumulator.
            // ????
            _insert(
                conduitKey,
                accumulator,
                ConduitItemType.ERC721,
                token,
                from,
                to,
                identifier,
                amount
            );
        }
    }

    /**
     * @dev Internal function to transfer ERC1155 tokens from a given originator
     *      to a given recipient. Sufficient approvals must be set, either on
     *      the respective conduit or on this contract itself.
     *
     * @param token       The ERC1155 token to transfer.
     * @param from        The originator of the transfer.
     * @param to          The recipient of the transfer.
     * @param identifier  The id to transfer.
     * @param amount      The amount to transfer.
     * @param conduitKey  A bytes32 value indicating what corresponding conduit,
     *                    if any, to source token approvals from. The zero hash
     *                    signifies that no conduit should be used, with direct
     *                    approvals set on this contract.
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     */
    function _transferERC1155(
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount,
        bytes32 conduitKey,
        bytes memory accumulator
    ) internal {
        // Ensure that the supplied amount is non-zero.
        _assertNonZeroAmount(amount);

        // Trigger accumulated transfers if the conduits differ.
        // ????
        _triggerIfArmedAndNotAccumulatable(accumulator, conduitKey);

        // If no conduit has been specified...
        if (conduitKey == bytes32(0)) {
            // Perform transfer via the token contract directly.
            _performERC1155Transfer(token, from, to, identifier, amount);
        } else {
            // Insert the call to the conduit into the accumulator.
            // ????
            _insert(
                conduitKey,
                accumulator,
                ConduitItemType.ERC1155,
                token,
                from,
                to,
                identifier,
                amount
            );
        }
    }

    /**
     * @dev Internal function to trigger a call to the conduit currently held by
     *      the accumulator if the accumulator contains item transfers (i.e. it
     *      is "armed") and the supplied conduit key does not match the key held
     *      by the accumulator.
     *
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     * @param conduitKey  A bytes32 value indicating what corresponding conduit,
     *                    if any, to source token approvals from. The zero hash
     *                    signifies that no conduit should be used, with direct
     *                    approvals set on this contract.
     */
    function _triggerIfArmedAndNotAccumulatable(
        bytes memory accumulator,
        bytes32 conduitKey
    ) internal {
        // Retrieve the current conduit key from the accumulator.
        bytes32 accumulatorConduitKey = _getAccumulatorConduitKey(accumulator);

        // Perform conduit call if the set key does not match the supplied key.
        if (accumulatorConduitKey != conduitKey) {
            _triggerIfArmed(accumulator);
        }
    }

    /**
     * @dev Internal function to trigger a call to the conduit currently held by
     *      the accumulator if the accumulator contains item transfers (i.e. it
     *      is "armed").
     *
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     */
    function _triggerIfArmed(bytes memory accumulator) internal {
        // Exit if the accumulator is not "armed".
        if (accumulator.length != AccumulatorArmed) {
            return;
        }

        // Retrieve the current conduit key from the accumulator.
        bytes32 accumulatorConduitKey = _getAccumulatorConduitKey(accumulator);

        // Perform conduit call.
        _trigger(accumulatorConduitKey, accumulator);
    }

    /**
     * @dev Internal function to trigger a call to the conduit corresponding to
     *      a given conduit key, supplying all accumulated item transfers. The
     *      accumulator will be "disarmed" and reset in the process.
     *
     * @param conduitKey  A bytes32 value indicating what corresponding conduit,
     *                    if any, to source token approvals from. The zero hash
     *                    signifies that no conduit should be used, with direct
     *                    approvals set on this contract.
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     */
    function _trigger(bytes32 conduitKey, bytes memory accumulator) internal {
        // Declare variables for offset in memory & size of calldata to conduit.
        uint256 callDataOffset;
        uint256 callDataSize;

        // Call the conduit with all the accumulated transfers.
        assembly {
            // Call begins at third word; the first is length or "armed" status,
            // and the second is the current conduit key.

            // 0x00        0x20         0x40        0x44                            0x64
            // +-----------+------------+-----------+-------------------------------+--------------+
            // |   length  | conduitKey |  selector | Accumulator_array_offset (20) | elements (1) |
            // +-----------+------------+-----------+-------------------------------+--------------+
            //                          TwoWords

            // TwoWords 後就是 要調用 execute() 時需要用到的參數
            // function execute(ConduitTransfer[] calldata transfers)
            // 先是 execute.selector 了
            // 再來是 ConduitTransfer[]

            callDataOffset := add(accumulator, TwoWords)

            // 68 + items * 192
            callDataSize := add(
                
                //      selector                 =  4 bytes (0x04)
                //      Accumulator_array_offset = 32 bytes (0x20)
                //   +) elements                 = 32 bytes (0x20)
                // --------------------------------------------------
                //                                 68 bytes (0x44)
                Accumulator_array_offset_ptr, // Accumulator_array_offset_ptr = 0x44;

                // 下面的 mul() 把 0x64 處的 length 的值拿出來 乘上 struct ConduitTransfer{} 的 size
                // struct ConduitTransfer{} 的 size = 0xc0 = 192
                mul(
                    mload(
                        add(
                            accumulator, 
                            Accumulator_array_length_ptr // Accumulator_array_length_ptr = 0x64 = 100;
                        )
                    ), 
                    Conduit_transferItem_size // Conduit_transferItem_size = 0xc0 = 192;
                )
            )
        }

        // Call conduit derived from conduit key & supply accumulated transfers.
        _callConduitUsingOffsets(conduitKey, callDataOffset, callDataSize);

        // Reset accumulator length to signal that it is now "disarmed".
        assembly {
            mstore(accumulator, AccumulatorDisarmed)
        }
    }

    /**
     * @dev Internal function to perform a call to the conduit corresponding to
     *      a given conduit key based on the offset and size of the calldata in
     *      question in memory.
     *
     * @param conduitKey     A bytes32 value indicating what corresponding
     *                       conduit, if any, to source token approvals from.
     *                       The zero hash signifies that no conduit should be
     *                       used, with direct approvals set on this contract.
     * @param callDataOffset The memory pointer where calldata is contained.
     * @param callDataSize   The size of calldata in memory.
     */
    function _callConduitUsingOffsets(
        bytes32 conduitKey,
        uint256 callDataOffset,
        uint256 callDataSize
    ) internal {
        // Derive the address of the conduit using the conduit key.
        // conduit 是我們 conduit 的 contract address
        address conduit = _deriveConduit(conduitKey);

        bool success;
        bytes4 result;

        // call the conduit.
        assembly {
            // Ensure first word of scratch space is empty.
            mstore(0, 0)

            // Perform call, placing first word of return data in scratch space.
            success := call(
                gas(),
                conduit,
                0,
                callDataOffset,
                callDataSize,
                0,
                OneWord
            )

            // Take value from scratch space and place it on the stack.
            result := mload(0)
        }

        // If the call failed...
        if (!success) {
            // Pass along whatever revert reason was given by the conduit.
            _revertWithReasonIfOneIsReturned();

            // Otherwise, revert with a generic error.
            revert InvalidCallToConduit(conduit);
        }

        // Ensure result was extracted and matches EIP-1271 magic value.
        if (result != ConduitInterface.execute.selector) {
            revert InvalidConduit(conduitKey, conduit);
        }
    }

    /**
     * @dev Internal pure function to retrieve the current conduit key set for
     *      the accumulator.
     *
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     *
     * @return accumulatorConduitKey The conduit key currently set for the
     *                               accumulator.
     */
    function _getAccumulatorConduitKey(bytes memory accumulator)
        internal
        pure
        returns (bytes32 accumulatorConduitKey)
    {
        // 0x00        0x20         0x40        0x44                            0x64
        // +----------+------------+----------+-------------------------------+--------------+------------------------+------------------------+
        // |  length  | conduitKey | selector | Accumulator_array_offset (20) | elements (1) | struct ConduitTransfer | struct ConduitTransfer |
        // +----------+-----------------------+-------------------------------+--------------+------------------------+------------------------+

        // Retrieve the current conduit key from the accumulator.
        assembly {
            // bytes memory accumulator 的前 32 bytes 是 length
            // bytes memory accumulator + 0x20 就是真實內容
            accumulatorConduitKey := mload(
                add(accumulator, Accumulator_conduitKey_ptr) // Accumulator_conduitKey_ptr = 0x20;
            )
        }
    }

    /**
     * @dev Internal pure function to place an item transfer into an accumulator
     *      that collects a series of transfers to execute against a given
     *      conduit in a single call.
     *
     * @param conduitKey  A bytes32 value indicating what corresponding conduit,
     *                    if any, to source token approvals from. The zero hash
     *                    signifies that no conduit should be used, with direct
     *                    approvals set on this contract.
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     * @param itemType    The type of the item to transfer.
     * @param token       The token to transfer.
     * @param from        The originator of the transfer.
     * @param to          The recipient of the transfer.
     * @param identifier  The tokenId to transfer.
     * @param amount      The amount to transfer.
     */
    function _insert(
        bytes32 conduitKey,
        bytes memory accumulator,
        ConduitItemType itemType,
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount
    ) internal pure {
        // uint256 constant AccumulatorDisarmed = 0x20;
        // uint256 constant AccumulatorArmed = 0x40;
        // uint256 constant Accumulator_conduitKey_ptr = 0x20;
        // uint256 constant Accumulator_selector_ptr = 0x40;
        // uint256 constant Accumulator_array_offset_ptr = 0x44;
        // uint256 constant Accumulator_array_length_ptr = 0x64;

        uint256 elements;
        // "Arm" and prime accumulator if it's not already armed. The sentinel
        // value is held in the length of the accumulator array.
        // uint256 constant AccumulatorDisarmed = 0x20;
        if (accumulator.length == AccumulatorDisarmed) {
            elements = 1;
            bytes4 selector = ConduitInterface.execute.selector;
            assembly {
                // 0x00        0x20         0x40        0x44                            0x64
                // +----------+------------+----------+-------------------------------+--------------+
                // |  length  | conduitKey | selector | Accumulator_array_offset (20) | elements (1) |
                // +----------+-----------------------+-------------------------------+--------------+
                mstore(accumulator, AccumulatorArmed) // "arm" the accumulator.
                mstore(add(accumulator, Accumulator_conduitKey_ptr), conduitKey)
                mstore(add(accumulator, Accumulator_selector_ptr), selector)
                mstore(
                    add(accumulator, Accumulator_array_offset_ptr),
                    Accumulator_array_offset // Accumulator_array_offset = 0x20;
                )
                mstore(add(accumulator, Accumulator_array_length_ptr), elements)
            }
        } else {
            // Otherwise, increase the number of elements by one.
            assembly {
                // 這邊表示已經是 AccumulatorArmed 的狀態了
                // 也就是說, 已經是上面的 layout 圖的狀態了
                // 所以, 就從0x64處取出element的值, +1, 放回去
                elements := add(
                    mload(add(accumulator, Accumulator_array_length_ptr)),
                    1
                )
                mstore(add(accumulator, Accumulator_array_length_ptr), elements)
            }
        }

        // Insert the item.
        // +-----------------------------------+
        // | struct ConduitTransfer {          |                           
        // +-----------------------------------+                                     
        // |     ConduitItemType itemType;     |                               
        // |     address token;                |                    
        // |     address from;                 |                   
        // |     address to;                   |                 
        // |     uint256 identifier;           |                         
        // |     uint256 amount;               |                     
        // | }                                 |   
        // +-----------------------------------+

        // 0x00        0x20         0x40        0x44                            0x64
        // +----------+------------+----------+-------------------------------+--------------+------------------------+------------------------+
        // |  length  | conduitKey | selector | Accumulator_array_offset (20) | elements (1) | struct ConduitTransfer | struct ConduitTransfer |
        // +----------+-----------------------+-------------------------------+--------------+------------------------+------------------------+
        assembly {
            // 在放入 struct ConduitTransfer 之前, 要先計算出位置
            // 每個 struct ConduitTransfer{} 的 size 為 0xc0
            // 最後減去 60 ????
            let itemPointer := sub(
                add(
                    accumulator, 
                    mul(
                        elements, 
                        Conduit_transferItem_size // Conduit_transferItem_size = 0xc0;
                    )
                ),
                Accumulator_itemSizeOffsetDifference // Accumulator_itemSizeOffsetDifference = 0x3c = 60;
            )
            mstore(itemPointer, itemType)
            mstore(add(itemPointer, Conduit_transferItem_token_ptr), token)
            mstore(add(itemPointer, Conduit_transferItem_from_ptr), from)
            mstore(add(itemPointer, Conduit_transferItem_to_ptr), to)
            mstore(
                add(itemPointer, Conduit_transferItem_identifier_ptr),
                identifier
            )
            mstore(add(itemPointer, Conduit_transferItem_amount_ptr), amount)
        }
    }
}
