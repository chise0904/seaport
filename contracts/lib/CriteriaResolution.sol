// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ItemType, Side } from "./ConsiderationEnums.sol";

import {
    OfferItem,
    ConsiderationItem,
    OrderParameters,
    AdvancedOrder,
    CriteriaResolver
} from "./ConsiderationStructs.sol";

import "./ConsiderationConstants.sol";

import {
    CriteriaResolutionErrors
} from "../interfaces/CriteriaResolutionErrors.sol";

/**
 * @title CriteriaResolution
 * @author 0age
 * @notice CriteriaResolution contains a collection of pure functions related to
 *         resolving criteria-based items.
 */
contract CriteriaResolution is CriteriaResolutionErrors {
    /**
     * @dev Internal pure function to apply criteria resolvers containing
     *      specific token identifiers and associated proofs to order items.
     *
     * @param advancedOrders     The orders to apply criteria resolvers to.
     * @param criteriaResolvers  An array where each element contains a
     *                           reference to a specific order as well as that
     *                           order's offer or consideration, a token
     *                           identifier, and a proof that the supplied token
     *                           identifier is contained in the order's merkle
     *                           root. Note that a root of zero indicates that
     *                           any transferable token identifier is valid and
     *                           that no proof needs to be supplied.
     */
    function _applyCriteriaResolvers(
        AdvancedOrder[] memory advancedOrders,
        CriteriaResolver[] memory criteriaResolvers
    ) internal pure {
        // Skip overflow checks as all for loops are indexed starting at zero.
        unchecked {
            // Retrieve length of criteria resolvers array and place on stack.
            uint256 totalCriteriaResolvers = criteriaResolvers.length;

            // Retrieve length of orders array and place on stack.
            uint256 totalAdvancedOrders = advancedOrders.length;

            // Iterate over each criteria resolver.
            for (uint256 i = 0; i < totalCriteriaResolvers; ++i) {
                // Retrieve the criteria resolver.
                CriteriaResolver memory criteriaResolver = (
                    criteriaResolvers[i]
                );

                // Read the order index from memory and place it on the stack.
                // criteriaResolver.orderIndex 用來指定這個 criteriaResolver 是針對哪個 order 作用的
                // advancedOrders array 裡面放了很多 order
                // 而 order 裡面的 parameters 又會放很多的 offer
                // criteriaResolver.index 就是用來指定哪一個 offer/consideration
                uint256 orderIndex = criteriaResolver.orderIndex;

                // Ensure that the order index is in range.
                if (orderIndex >= totalAdvancedOrders) {
                    revert OrderCriteriaResolverOutOfRange();
                }

                // Skip criteria resolution for order if not fulfilled.
                // ????
                if (advancedOrders[orderIndex].numerator == 0) {
                    continue;
                }

                // Retrieve the parameters for the order.
                OrderParameters memory orderParameters = (
                    advancedOrders[orderIndex].parameters
                );

                // Read component index from memory and place it on the stack.
                uint256 componentIndex = criteriaResolver.index;

                // Declare values for item's type and criteria.
                ItemType itemType;
                uint256 identifierOrCriteria;

                // If the criteria resolver refers to an offer item...
                if (criteriaResolver.side == Side.OFFER) {
                    // Retrieve the offer.
                    OfferItem[] memory offer = orderParameters.offer;

                    // Ensure that the component index is in range.
                    if (componentIndex >= offer.length) {
                        revert OfferCriteriaResolverOutOfRange();
                    }

                    // Retrieve relevant item using the component index.
                    // criteriaResolver.index 指定的 offer
                    OfferItem memory offerItem = offer[componentIndex];

                    // Read item type and criteria from memory & place on stack.
                    itemType = offerItem.itemType;
                    identifierOrCriteria = offerItem.identifierOrCriteria;

                    // Optimistically update item type to remove criteria usage.
                    // Use assembly to operate on ItemType enum as a number.
                    // enum ItemType {
                    //     NATIVE,                // 0
                    //     ERC20,                 // 1
                    //     ERC721,                // 2
                    //     ERC1155,               // 3
                    //     ERC721_WITH_CRITERIA,  // 4
                    //     ERC1155_WITH_CRITERIA  // 5
                    // }
                    // 
                    ItemType newItemType;
                    assembly {
                        // Item type 4 becomes 2 and item type 5 becomes 3.
                        // ERC721_WITH_CRITERIA -> ERC721
                        // ERC1155_WITH_CRITERIA -> ERC1155
                        // 如果 itemType == 4,
                        // -> eq(itemType, 4) = 1
                        // -> 3 - 1
                        // -> 2
                        //
                        // 如果 itemType == 5,
                        // -> eq(itemType, 5) = 0
                        // -> 3 - 0
                        // -> 3
                        newItemType := sub(3, eq(itemType, 4))
                    }
                    offerItem.itemType = newItemType;

                    // Optimistically update identifier w/ supplied identifier.
                    offerItem.identifierOrCriteria = criteriaResolver.identifier;

                } else {
                    // Otherwise, the resolver refers to a consideration item.
                    ConsiderationItem[] memory consideration = (
                        orderParameters.consideration
                    );

                    // Ensure that the component index is in range.
                    if (componentIndex >= consideration.length) {
                        revert ConsiderationCriteriaResolverOutOfRange();
                    }

                    // Retrieve relevant item using order and component index.
                    ConsiderationItem memory considerationItem = (
                        consideration[componentIndex]
                    );

                    // Read item type and criteria from memory & place on stack.
                    itemType = considerationItem.itemType;
                    identifierOrCriteria = (
                        considerationItem.identifierOrCriteria
                    );

                    // Optimistically update item type to remove criteria usage.
                    // Use assembly to operate on ItemType enum as a number.
                    ItemType newItemType;
                    assembly {
                        // Item type 4 becomes 2 and item type 5 becomes 3.
                        newItemType := sub(3, eq(itemType, 4))
                    }
                    considerationItem.itemType = newItemType;

                    // Optimistically update identifier w/ supplied identifier.
                    considerationItem.identifierOrCriteria = (
                        criteriaResolver.identifier
                    );
                }

                // Ensure the specified item type indicates criteria usage.
                if (!_isItemWithCriteria(itemType)) {
                    revert CriteriaNotEnabledForItem();
                }

                // If criteria is not 0 (i.e. a collection-wide offer)...
                if (identifierOrCriteria != uint256(0)) {
                    // Verify identifier inclusion in criteria root using proof.
                    _verifyProof(
                        criteriaResolver.identifier,
                        identifierOrCriteria,
                        criteriaResolver.criteriaProof
                    );
                }
            }

            // 目前猜測
            // 上面都執行完以後, advancedOrders[] 裡面的 offer/consideration 都不應該還是 ERC721_WITH_CRITERIA 或 ERC1155_WITH_CRITERIA
            // 還有的話, 就 revert
            // 也就是說, criteriaResolvers[] 就是要針對 itemType 為 ERC721_WITH_CRITERIA 或 ERC1155_WITH_CRITERIA 的 offer/consideration
            // 如果有沒對應到的, 例如 offer/consideration 為 ERC721_WITH_CRITERIA 或 ERC1155_WITH_CRITERIA
            // 卻沒有相對應到的 criteriaResolvers 來處理的話, 就 revert

            // Iterate over each advanced order.
            for (uint256 i = 0; i < totalAdvancedOrders; ++i) {
                // Retrieve the advanced order.
                AdvancedOrder memory advancedOrder = advancedOrders[i];

                // Skip criteria resolution for order if not fulfilled.
                if (advancedOrder.numerator == 0) {
                    continue;
                }

                // Retrieve the parameters for the order.
                OrderParameters memory orderParameters = (
                    advancedOrder.parameters
                );

                // Read consideration length from memory and place on stack.
                uint256 totalItems = orderParameters.consideration.length;

                // Iterate over each consideration item on the order.
                for (uint256 j = 0; j < totalItems; ++j) {
                    // Ensure item type no longer indicates criteria usage.
                    if (
                        _isItemWithCriteria(
                            orderParameters.consideration[j].itemType
                        )
                    ) {
                        revert UnresolvedConsiderationCriteria();
                    }
                }

                // Read offer length from memory and place on stack.
                totalItems = orderParameters.offer.length;

                // Iterate over each offer item on the order.
                for (uint256 j = 0; j < totalItems; ++j) {
                    // Ensure item type no longer indicates criteria usage.
                    if (
                        _isItemWithCriteria(orderParameters.offer[j].itemType)
                    ) {
                        revert UnresolvedOfferCriteria();
                    }
                }
            }
        }
    }

    /**
     * @dev Internal pure function to check whether a given item type represents
     *      a criteria-based ERC721 or ERC1155 item (e.g. an item that can be
     *      resolved to one of a number of different identifiers at the time of
     *      order fulfillment).
     *
     * @param itemType The item type in question.
     *
     * @return withCriteria A boolean indicating that the item type in question
     *                      represents a criteria-based item.
     */
    function _isItemWithCriteria(ItemType itemType)
        internal
        pure
        returns (bool withCriteria)
    {
        // ERC721WithCriteria is ItemType 4. 
        // ERC1155WithCriteria is ItemType 5.
        assembly {
            withCriteria := gt(itemType, 3)
        }
    }

    /**
     * @dev Internal pure function to ensure that a given element is contained
     *      in a merkle root via a supplied proof.
     *
     * @param leaf  The element for which to prove inclusion.
     * @param root  The merkle root that inclusion will be proved against.
     * @param proof The merkle proof.
     */
    function _verifyProof(
        uint256 leaf,
        uint256 root,
        bytes32[] memory proof
    ) internal pure {
        // Declare a variable that will be used to determine proof validity.
        bool isValid;

        // Utilize assembly to efficiently verify the proof against the root.
        assembly {
            // Store the leaf at the beginning of scratch space.
            mstore(0, leaf)

            // Derive the hash of the leaf to use as the initial proof element.
            let computedHash := keccak256(0, OneWord)

            // Based on: https://github.com/Rari-Capital/solmate/blob/v7/src/utils/MerkleProof.sol
            // Get memory start location of the first element in proof array.
            // data 指向 proof 的數據開始處, 最前面是 length
            let data := add(proof, OneWord)

            // Iterate over each proof element to compute the root hash.
            for {
                // Left shift by 5 is equivalent to multiplying by 0x20.
                // mload(proof) 可以拿到 length, 例如 5
                // shl(5, mload(proof)) 對 length 乘上 32 bytes, 得到總共的長度
                // data + shl(5, mload(proof)) 就是 proof 的最尾巴
                let end := add(data, shl(5, mload(proof)))
            } lt(data, end) {
                // Increment by one word at a time.
                // 每次 + 32 bytes
                data := add(data, OneWord)
            } {
                // Get the proof element.
                let loadedData := mload(data)

                // Sort proof elements and place them in scratch space.
                // Slot of `computedHash` in scratch space.
                // If the condition is true: 0x20, otherwise: 0x00.
                let scratch := shl(5, gt(computedHash, loadedData))

                // Store elements to hash contiguously in scratch space. Scratch
                // space is 64 bytes (0x00 - 0x3f) & both elements are 32 bytes.
                mstore(scratch, computedHash)
                mstore(xor(scratch, OneWord), loadedData)

                // Derive the updated hash.
                computedHash := keccak256(0, TwoWords)
            }

            // Compare the final hash to the supplied root.
            isValid := eq(computedHash, root)
        }

        // Revert if computed hash does not equal supplied root.
        if (!isValid) {
            revert InvalidProof();
        }
    }
}
