// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ConduitInterface } from "../interfaces/ConduitInterface.sol";

import {
    OrderType,
    ItemType,
    BasicOrderRouteType
} from "./ConsiderationEnums.sol";

import {
    AdditionalRecipient,
    BasicOrderParameters,
    OfferItem,
    ConsiderationItem,
    SpentItem,
    ReceivedItem
} from "./ConsiderationStructs.sol";

import { OrderValidator } from "./OrderValidator.sol";

import "./ConsiderationConstants.sol";

/**
 * @title BasicOrderFulfiller
 * @author 0age
 * @notice BasicOrderFulfiller contains functionality for fulfilling "basic"
 *         orders with minimal overhead. See documentation for details on what
 *         qualifies as a basic order.
 */
contract BasicOrderFulfiller is OrderValidator {
    /**
     * @dev Derive and set hashes, reference chainId, and associated domain
     *      separator during deployment.
     *
     * @param conduitController A contract that deploys conduits, or proxies
     *                          that may optionally be used to transfer approved
     *                          ERC20/721/1155 tokens.
     */
    constructor(address conduitController) OrderValidator(conduitController) {}

    /**
     * @dev Internal function to fulfill an order offering an ERC20, ERC721, or
     *      ERC1155 item by supplying Ether (or other native tokens), ERC20
     *      tokens, an ERC721 item, or an ERC1155 item as consideration. Six
     *      permutations are supported: Native token to ERC721, Native token to
     *      ERC1155, ERC20 to ERC721, ERC20 to ERC1155, ERC721 to ERC20, and
     *      ERC1155 to ERC20 (with native tokens supplied as msg.value). For an
     *      order to be eligible for fulfillment via this method, it must
     *      contain a single offer item (though that item may have a greater
     *      amount if the item is not an ERC721). An arbitrary number of
     *      "additional recipients" may also be supplied which will each receive
     *      native tokens or ERC20 items from the fulfiller as consideration.
     *      Refer to the documentation for a more comprehensive summary of how
     *      to utilize this method and what orders are compatible with it.
     *
     * @param parameters Additional information on the fulfilled order. Note
     *                   that the offerer and the fulfiller must first approve
     *                   this contract (or their chosen conduit if indicated)
     *                   before any tokens can be transferred. Also note that
     *                   contract recipients of ERC1155 consideration items must
     *                   implement `onERC1155Received` in order to receive those
     *                   items.
     *
     * @return A boolean indicating whether the order has been fulfilled.
     */
    function _validateAndFulfillBasicOrder(
        BasicOrderParameters calldata parameters
    ) internal returns (bool) {
        // Declare enums for order type & route to extract from basicOrderType.
        BasicOrderRouteType route;
        OrderType orderType;

        // Declare additional recipient item type to derive from the route type.
        ItemType additionalRecipientsItemType;

        // Utilize assembly to extract the order type and the basic order route.
        assembly {
            // Read basicOrderType from calldata.
            let basicOrderType := calldataload(BasicOrder_basicOrderType_cdPtr) // 0x124

            // Mask all but 2 least-significant bits to derive the order type.

            // 這邊是為了要把 enum BasicOrderType 變成 enum OrderType

            // BasicOrderType 的 prefix 都是 
            // XXX_TO_OOO_FULL_OPEN
            // XXX_TO_OOO_PARTIAL_OPEN,     
            // XXX_TO_OOO_FULL_RESTRICTED,  
            // XXX_TO_OOO_PARTIAL_RESTRICTED

            // 用 and(basicOrderType, 3) 就可以把前面的 XXX_TO_OOO_ 去除, 
            // 最後得到我們想要的
            // FULL_OPEN,        
            // PARTIAL_OPEN,     
            // FULL_RESTRICTED,  
            // PARTIAL_RESTRICTED
            orderType := and(basicOrderType, 3) // 3 = 0011

            // ETH_TO_ERC721_XXXX >> 2    會得到 0 對應於 BasicOrderRouteType.ETH_TO_ERC721
            // ETH_TO_ERC1155_XXXX >> 2   會得到 1 對應於 BasicOrderRouteType.ETH_TO_ERC1155
            // ERC20_TO_ERC721_XXXX >> 2  會得到 2 對應於 BasicOrderRouteType.ERC20_TO_ERC721
            // ERC20_TO_ERC1155_XXXX >> 2 會得到 3 對應於 BasicOrderRouteType.ERC20_TO_ERC1155
            // ERC721_TO_ERC20_XXXX >> 2  會得到 4 對應於 BasicOrderRouteType.ERC721_TO_ERC20 
            // ERC1155_TO_ERC20_XXXX >> 2 會得到 5 對應於 BasicOrderRouteType.ERC1155_TO_ERC20
            route := shr(2, basicOrderType)

            // If route > 1 additionalRecipient items are ERC20 (1) else Eth (0)

            // 這邊是用 gt(), 所以要大於0, 才會為 true

            // gt(route, 1) 為 0 時, 是下面的情況
            // ETH_TO_ERC721,
            // ETH_TO_ERC1155

            // gt(route, 1) 為 0 時, 是下面的情況
            // ERC20_TO_ERC721, 
            // ERC20_TO_ERC1155,
            // ERC721_TO_ERC20, 
            // ERC1155_TO_ERC20 
            // 用 additionalRecipientsItemType 來判斷是要用 native eth 來交易, 還是要用 ERC token
            additionalRecipientsItemType := gt(route, 1)
        }
            
            // ERC20_TO_ERC721_FULL_OPEN,             // 8       
            // ERC20_TO_ERC721_PARTIAL_OPEN,          // 9          
            // ERC20_TO_ERC721_FULL_RESTRICTED,       // 10             
            // ERC20_TO_ERC721_PARTIAL_RESTRICTED,    // 11                
                            
            // ERC20_TO_ERC1155_FULL_OPEN,            // 12        
            // ERC20_TO_ERC1155_PARTIAL_OPEN,         // 13           
            // ERC20_TO_ERC1155_FULL_RESTRICTED,      // 14              
            // ERC20_TO_ERC1155_PARTIAL_RESTRICTED,   // 15                 
                        
            // ERC721_TO_ERC20_FULL_OPEN,             // 16       
            // ERC721_TO_ERC20_PARTIAL_OPEN,          // 17          
            // ERC721_TO_ERC20_FULL_RESTRICTED,       // 18             
            // ERC721_TO_ERC20_PARTIAL_RESTRICTED,    // 19                
                        
            // ERC1155_TO_ERC20_FULL_OPEN,            // 20        
            // ERC1155_TO_ERC20_PARTIAL_OPEN,         // 21           
            // ERC1155_TO_ERC20_FULL_RESTRICTED,      // 22              
            // ERC1155_TO_ERC20_PARTIAL_RESTRICTED    // 23  

        {
            // Declare temporary variable for enforcing payable status.
            // 這邊就是用來檢查
            // 如果是 ETH_ 開頭的話, 就應該夾帶 xxx wei 上來
            // 如果是 ERC20_ 開頭的話, 就不應該夾帶 xxx wei 上來
            bool correctPayableStatus;

            // Utilize assembly to compare the route to the callvalue.
            assembly {
                // route 0 and 1 are payable, otherwise route is not payable.

                // 如果沒有夾帶wei, 就表示要用 ERC20 來付, orderType 應該要 > 7 (0111),
                // => shr(2, basicOrderType) > 1
                // => additionalRecipientsItemType = 1
                // => iszero(callvalue()) = 1
                // => correctPayableStatus = 1

                // 如果夾帶wei, 就表示要用 ETH 來付, orderType 應該要 < 7 (0111),
                // => shr(2, basicOrderType) <= 1
                // => additionalRecipientsItemType = 0
                // => iszero(callvalue()) = 0
                // => correctPayableStatus = 1
                correctPayableStatus := eq(
                    additionalRecipientsItemType,
                    // callvalue() 會返回隨著tx挾帶的wei
                    // 如果沒有夾帶wei的話, iszero(callvalue()) == 1
                    // 如果有夾帶wei的話, iszero(callvalue()) == 0
                    iszero(callvalue())
                )
            }

            // Revert if msg.value has not been supplied as part of payable
            // routes or has been supplied as part of non-payable routes.
            if (!correctPayableStatus) {
                revert InvalidMsgValue(msg.value);
            }
        }

        // Declare more arguments that will be derived from route and calldata.
        address additionalRecipientsToken;
        ItemType offeredItemType;
        bool offerTypeIsAdditionalRecipientsType;

        // Declare scope for received item type to manage stack pressure.
        {
            ItemType receivedItemType;

            // Utilize assembly to retrieve function arguments and cast types.
            assembly {
                // Check if offered item type == additional recipient item type.

                // === offerTypeIsAdditionalRecipientsType 為 1 ===
                // 如果 gt(route, 3) 為 true, 就表示 route 是
                // ERC721_TO_ERC20, 
                // ERC1155_TO_ERC20 

                // 即
                // ERC721_TO_ERC20_FULL_OPEN,             // 16       
                // ERC721_TO_ERC20_PARTIAL_OPEN,          // 17          
                // ERC721_TO_ERC20_FULL_RESTRICTED,       // 18             
                // ERC721_TO_ERC20_PARTIAL_RESTRICTED,    // 19                
                            
                // ERC1155_TO_ERC20_FULL_OPEN,            // 20        
                // ERC1155_TO_ERC20_PARTIAL_OPEN,         // 21           
                // ERC1155_TO_ERC20_FULL_RESTRICTED,      // 22              
                // ERC1155_TO_ERC20_PARTIAL_RESTRICTED    // 23 
                //
                // 代表 seller 要用 ERC20 來換 ERC721/ERC1155
                // 所以 offer 會是 ERC20
                // consideration 會放 ERC721/ERC1155

                // === offerTypeIsAdditionalRecipientsType 為 0 ===
                // 如果 gt(route, 3) 為 false, 就表示 route 是
                // ETH_TO_ERC721,  
                // ETH_TO_ERC1155, 
                // ERC20_TO_ERC721,
                // ERC20_TO_ERC1155
                //
                // 代表 seller 要用 ERC721/ERC1155 來換 ETH/ERC20
                // 所以 offer 會是 ERC721/ERC1155
                // consideration 會放 ETH/ERC20

                offerTypeIsAdditionalRecipientsType := gt(route, 3)

                // If route > 3 additionalRecipientsToken is at 0xc4 else 0x24.
                // address considerationToken;                 // 0x24 
                // address offerToken;                         // 0xc4 = 0x24 + 0xa0
                //
                // 如果是 ERC721_TO_ERC20_XXX | ERC1155_TO_ERC20_XXX 的話, 
                // 也就是 seller 出 ERC20 要換 ERC721/ERC1155
                // 那 additionalRecipientsToken 就是 offerToken
                //
                // 如果是 ERC20_TO_ERC721_XXX | ERC20_TO_ERC1155_XXX
                // 也就是 seller 出 ERC721/ERC1155 要換 ERC20
                // 那 additionalRecipientsToken 就是 considerationToken

                // additionalRecipientsToken 用來存放 ERC20 token address
                additionalRecipientsToken := calldataload(
                    add(
                        BasicOrder_considerationToken_cdPtr, // 0x24
                        mul(
                            offerTypeIsAdditionalRecipientsType, // 1 或 0
                            BasicOrder_common_params_size    // 0xa0 = 160 = 32*5
                        )
                    )
                )

                // If route > 2, receivedItemType is route - 2. If route is 2,
                // the receivedItemType is ERC20 (1). Otherwise, it is Eth (0).
                // 如果是 ETH_TO_ERC721_OOXX 開頭的話, route = 0, receivedItemType == ItemType.NATIVE == 0
                // 如果是 ETH_TO_ERC1155_OOXX 開頭的話, route = 1, receivedItemType == ItemType.NATIVE == 0
                // 如果是 ERC20_TO_ERC721_OOXX 開頭的話, route = 2, receivedItemType == ItemType.ERC20 == 1
                // 如果是 ERC20_TO_ERC1155_OOXX 開頭的話, route = 3, receivedItemType == ItemType.ERC20 == 1
                // 如果是 ERC721_ 開頭的話, route = 4, receivedItemType == ItemType.ERC721 == 2
                // 如果是 ERC1155_ 開頭的話, route = 5, receivedItemType == ItemType.ERC1155 == 3
                //
                // receivedItemType 用來存放是 NATIVE|ERC20|ERC721|ERC1155
                // 即
                // 賣家想要收到什麼要的東西? 是 eth ? 還是 ERC20 ? 還是 ERC721 ? 還是 ERC1155 ?
                receivedItemType := add(
                    mul(sub(route, 2), gt(route, 2)),
                    eq(route, 2)
                )

                // offeredItemType 用來表示是 ItemType 的哪一個
                //
                // BasicOrderType 都是長下面這些樣子
                // ETH_TO_ERC721_XXX
                // ETH_TO_ERC1155_XXX
                // ERC20_TO_ERC721_XXX
                // ERC20_TO_ERC1155_XXX
                // ERC721_TO_ERC20_XXX
                // ERC1155_TO_ERC20_XXX
                //
                // 如果是 ETH_TO_ERC721_XXX 那 offeredItemType = ItemType.ERC721
                // 如果是 ETH_TO_ERC1155_XXX 那 offeredItemType = ItemType.ERC1155
                // 如果是 ERC20_TO_ERC721_XXX 那 offeredItemType = ItemType.ERC721
                // 如果是 ERC20_TO_ERC1155_XXX 那 offeredItemType = ItemType.ERC1155
                // 如果是 ERC721_TO_ERC20_XXX 那 offeredItemType = ItemType.ERC20
                // 如果是 ERC1155_TO_ERC20_XXX 那 offeredItemType = ItemType.ERC20
                //
                // 也就是說, 只要是 TO_OOXX 那 offeredItemType = ItemType.OOXX
                // 即
                // 賣家出什麼類型的token

                // 下面是 offeredItemType 的計算過程

                // If route > 3, offeredItemType is ERC20 (1). Route is 2 or 3,
                // offeredItemType = route. Route is 0 or 1, it is route + 2.

                // route = 0, 
                // additionalRecipientsItemType = 0, offerTypeIsAdditionalRecipientsType = 0, receivedItemType = 0
                // => offeredItemType = sub( add(0, mul(1,2)), mul(0, add(0,1)) )
                // => offeredItemType = 2
                
                // route = 1, 
                // additionalRecipientsItemType = 0, offerTypeIsAdditionalRecipientsType = 0, receivedItemType = 0
                // => offeredItemType = sub( add(1, mul(1,2)), mul(0, add(0,1)) )
                // => offeredItemType = 3
                
                // route = 2, 
                // additionalRecipientsItemType = 1, offerTypeIsAdditionalRecipientsType = 0, receivedItemType = 1
                // => offeredItemType = sub( add(2, mul(0,2)), mul(0, add(1,1)) )
                // => offeredItemType = 2

                // route = 3, 
                // additionalRecipientsItemType = 1, offerTypeIsAdditionalRecipientsType = 0, receivedItemType = 1
                // => offeredItemType = sub( add(3, mul(0,2)), mul(0, add(1,1)) ) 
                // => offeredItemType = 3

                // route = 4, 
                // additionalRecipientsItemType = 1, offerTypeIsAdditionalRecipientsType = 1, receivedItemType = 2
                // => offeredItemType = sub( add(4, mul(0,2)), mul(1, add(2,1)) )
                // => offeredItemType = 1

                // route = 5, 
                // additionalRecipientsItemType = 1, offerTypeIsAdditionalRecipientsType = 1, receivedItemType = 3
                // => offeredItemType = sub( add(5, mul(0,2)), mul(1, add(3,1)) )
                // => offeredItemType = 1
                
                offeredItemType := sub(
                    add(route, mul(iszero(additionalRecipientsItemType), 2)),
                    mul(
                        // ERC721_TO_ERC20_FULL_OPEN (16, route = 4) 以前的都是 0, 以後的都是 1
                        offerTypeIsAdditionalRecipientsType,
                        add(receivedItemType, 1)
                    )
                )
            }

            // Derive & validate order using parameters and update order status.
            _prepareBasicFulfillmentFromCalldata(
                parameters,
                orderType,
                receivedItemType,
                additionalRecipientsItemType,
                additionalRecipientsToken,
                offeredItemType
            );
        }

        // Declare conduitKey argument used by transfer functions.
        bytes32 conduitKey;

        // Utilize assembly to derive conduit (if relevant) based on route.
        assembly {
            // use offerer conduit for routes 0-3, fulfiller conduit otherwise.
           
            // bytes32 offererConduitKey;                  // 0x1c4 
            // bytes32 fulfillerConduitKey;                // 0x1e4

            // 賣家出 nft 要換 ERC20 時, 就是用 offererConduitKey
            // 賣家出 ERC20 要換 nft 時, 就是用 fulfillerConduitKey
            conduitKey := calldataload(
                add(
                    BasicOrder_offererConduit_cdPtr, // 0x1c4

                    // offerTypeIsAdditionalRecipientsType 為 0 的情況是
                    // ETH_TO_ERC721,    
                    // ETH_TO_ERC1155,   
                    // ERC20_TO_ERC721,  
                    // ERC20_TO_ERC1155, 

                    // offerTypeIsAdditionalRecipientsType 為 1 的情況是
                    // ERC721_TO_ERC20,
                    // ERC1155_TO_ERC20
                    mul(offerTypeIsAdditionalRecipientsType, OneWord)
                )
            )
        }

        // Transfer tokens based on the route.
        // 只要 BasicOrderType 是 ETH_ 開頭的, additionalRecipientsItemType 就為 0
        // 只要 BasicOrderType 是 ERC20_ 開頭的, additionalRecipientsItemType 就為 1
        if (additionalRecipientsItemType == ItemType.NATIVE) {
            // Ensure neither the token nor the identifier parameters are set.
            if (
                (uint160(parameters.considerationToken) |
                    parameters.considerationIdentifier) != 0
            ) {
                revert UnusedItemParameters();
            }

            // Transfer the ERC721 or ERC1155 item, bypassing the accumulator.
            // 將 ERC721/ERC1155 從 offerer 轉給 msg.sender
            _transferIndividual721Or1155Item(
                offeredItemType,
                parameters.offerToken,
                parameters.offerer,
                msg.sender,
                parameters.offerIdentifier,
                parameters.offerAmount,
                conduitKey
            );

            // Transfer native to recipients, return excess to caller & wrap up.
            _transferEthAndFinalize(
                parameters.considerationAmount, // value
                parameters.offerer,             // to
                parameters.additionalRecipients
            );
        } else {
            // Initialize an accumulator array. From this point forward, no new
            // memory regions can be safely allocated until the accumulator is
            // no longer being utilized, as the accumulator operates in an
            // open-ended fashion from this memory pointer; existing memory may
            // still be accessed and modified, however.
            bytes memory accumulator = new bytes(AccumulatorDisarmed);

            // Choose transfer method for ERC721 or ERC1155 item based on route.
            
            if (route == BasicOrderRouteType.ERC20_TO_ERC721) {
                // 買家用 ERC20 去買 賣家提供的 ERC721
                // Transfer ERC721 to caller using offerer's conduit preference.
                _transferERC721(
                    parameters.offerToken,
                    parameters.offerer,
                    msg.sender,
                    parameters.offerIdentifier,
                    parameters.offerAmount,
                    conduitKey,
                    accumulator
                );
            } else if (route == BasicOrderRouteType.ERC20_TO_ERC1155) {
                // 買家用 ERC20 去買 賣家提供的 ERC1155
                // 換句話說, 賣家提供 ERC1155 要換 ERC20
                // 所以, offerXXX 就會填 ERC1155 相關info
                // Transfer ERC1155 to caller with offerer's conduit preference.
                _transferERC1155(
                    parameters.offerToken,
                    parameters.offerer,
                    msg.sender,
                    parameters.offerIdentifier,
                    parameters.offerAmount,
                    conduitKey,
                    accumulator
                );
            } else if (route == BasicOrderRouteType.ERC721_TO_ERC20) {
                // 買家用 ERC721 去買 賣家提供的 ERC20
                // 換句話說, 賣家提供 ERC20 要換 ERC721
                // 所以, considerationXXX 就會填 ERC721 相關info
                // Transfer ERC721 to offerer using caller's conduit preference.
                _transferERC721(
                    parameters.considerationToken,
                    msg.sender,
                    parameters.offerer,
                    parameters.considerationIdentifier,
                    parameters.considerationAmount,
                    conduitKey,
                    accumulator
                );
            } else {
                // route == BasicOrderRouteType.ERC1155_TO_ERC20
                // 買家用 ERC1155 去買 賣家提供的 ERC20
                // 換句話說, 賣家提供 ERC20 要換 ERC1155
                // 所以, considerationXXX 就會填 ERC1155 相關info
                // Transfer ERC1155 to offerer with caller's conduit preference.
                _transferERC1155(
                    parameters.considerationToken,
                    msg.sender,
                    parameters.offerer,
                    parameters.considerationIdentifier,
                    parameters.considerationAmount,
                    conduitKey,
                    accumulator
                );
            }

            // Transfer ERC20 tokens to all recipients and wrap up.
            _transferERC20AndFinalize(
                parameters.offerer,
                parameters,
                offerTypeIsAdditionalRecipientsType,
                accumulator
            );

            // Trigger any remaining accumulated transfers via call to conduit.
            _triggerIfArmed(accumulator);
        }

        // Clear the reentrancy guard.
        _clearReentrancyGuard();

        return true;
    }

    /**
     * @dev Internal function to prepare fulfillment of a basic order with
     *      manual calldata and memory access. This calculates the order hash,
     *      emits an OrderFulfilled event, and asserts basic order validity.
     *      Note that calldata offsets must be validated as this function
     *      accesses constant calldata pointers for dynamic types that match
     *      default ABI encoding, but valid ABI encoding can use arbitrary
     *      offsets. Checking that the offsets were produced by default encoding
     *      will ensure that other functions using Solidity's calldata accessors
     *      (which calculate pointers from the stored offsets) are reading the
     *      same data as the order hash is derived from. Also note that This
     *      function accesses memory directly. It does not clear the expanded
     *      memory regions used, nor does it update the free memory pointer, so
     *      other direct memory access must not assume that unused memory is
     *      empty.
     *
     * @param parameters                   The parameters of the basic order.
     * @param orderType                    The order type.
     * @param receivedItemType             The item type of the initial
     *                                     consideration item on the order.
     * @param additionalRecipientsItemType The item type of any additional
     *                                     consideration item on the order.
     * @param additionalRecipientsToken    The ERC20 token contract address (if
     *                                     applicable) for any additional
     *                                     consideration item on the order.
     * @param offeredItemType              The item type of the offered item on
     *                                     the order.
     */
    function _prepareBasicFulfillmentFromCalldata(
        BasicOrderParameters calldata parameters,
        OrderType orderType,
        ItemType receivedItemType,
        ItemType additionalRecipientsItemType,
        address additionalRecipientsToken,
        ItemType offeredItemType
    ) internal {
        // Ensure this function cannot be triggered during a reentrant call.
        _setReentrancyGuard();

        // Ensure current timestamp falls between order start time and end time.
        _verifyTime(parameters.startTime, parameters.endTime, true);

        // Verify that calldata offsets for all dynamic types were produced by
        // default encoding. This ensures that the constants we use for calldata
        // pointers to dynamic types are the same as those calculated by
        // Solidity using their offsets. Also verify that the basic order type
        // is within range.
        _assertValidBasicOrderParameters();

        // Ensure supplied consideration array length is not less than original.
        // additionalRecipients.length 的大小必須大於 totalOriginalAdditionalRecipients
        _assertConsiderationLengthIsNotLessThanOriginalConsiderationLength(
            parameters.additionalRecipients.length,
            parameters.totalOriginalAdditionalRecipients
        );

        // Declare stack element for the order hash.
        bytes32 orderHash;

        {
            /**
             * First, handle consideration items. Memory Layout:

             *  0x60: final hash of the array of consideration item hashes

            struct ConsiderationItem {
                ItemType itemType;
                address token;
                uint256 identifierOrCriteria;
                uint256 startAmount;
                uint256 endAmount;
                address payable recipient;
            }
             *  0x80-0x160: reused space for EIP712 hashing of each item
             *   - 0x80: ConsiderationItem EIP-712 typehash (constant)
             *   - 0xa0: itemType
             *   - 0xc0: token
             *   - 0xe0: identifier
             *   - 0x100: startAmount
             *   - 0x120: endAmount
             *   - 0x140: recipient

             *  0x160-END_ARR: array of consideration item hashes
             *   - 0x160: primary consideration item EIP712 hash
             *   - 0x180-END_ARR: additional recipient item EIP712 hashes

             *  END_ARR: beginning of data for OrderFulfilled event
             *   - END_ARR + 0x120: length of ReceivedItem array
             *   - END_ARR + 0x140: beginning of data for first ReceivedItem

             * (Note: END_ARR = 0x180 + RECIPIENTS_LENGTH * 0x20)
             */

            // Load consideration item typehash from runtime and place on stack.
            bytes32 typeHash = _CONSIDERATION_ITEM_TYPEHASH;

            // Utilize assembly to enable reuse of memory regions and use
            // constant pointers when possible.
            assembly {
                /*
                 * 1. Calculate the EIP712 ConsiderationItem hash for the
                 * primary consideration item of the basic order.
                 */

                // Write ConsiderationItem type hash and item type to memory.
                // BasicOrder_considerationItem_typeHash_ptr = 0x80
                mstore(BasicOrder_considerationItem_typeHash_ptr, typeHash)

                mstore(
                    // BasicOrder_considerationItem_token_ptr = 0xa0;
                    BasicOrder_considerationItem_itemType_ptr,
                    receivedItemType
                )

                // Copy calldata region with (token, identifier, amount) from
                // BasicOrderParameters to ConsiderationItem. The
                // considerationAmount is written to startAmount and endAmount
                // as basic orders do not have dynamic amounts.

                // 注意:
                // 這邊的 calldata 是從 _validateAndFulfillBasicOrder() 來的
                // 雖然 _validateAndFulfillBasicOrder() 裡面又調用了 _prepareBasicFulfillmentFromCalldata()
                // 但 calldata 仍舊是 _validateAndFulfillBasicOrder() 中的參數

                // 將 BasicOrderParameters 的 considerationToken, considerationIdentifier, considerationAmount 的值 複製到 BasicOrder_considerationItem_token_ptr
                // 這邊複製的 considerationAmount 是 startAmount
                calldatacopy(
                    BasicOrder_considerationItem_token_ptr, // BasicOrder_considerationItem_token_ptr = 0xc0;
                    BasicOrder_considerationToken_cdPtr,    // BasicOrder_considerationToken_cdPtr    = 0x24;
                    ThreeWords // 0x60
                )

                // Copy calldata region with considerationAmount and offerer
                // from BasicOrderParameters to endAmount and recipient in
                // ConsiderationItem.
                // 這邊共複製了 considerationAmount, offerer
                // 這邊又再複製了一次 considerationAmount 用來當作 emdAmount
                // offerer 是 recipient
                calldatacopy(
                    // BasicOrder_considerationItem_endAmount_ptr = 0x120;
                    // BasicOrder_considerationAmount_cdPtr = 0x64;
                    BasicOrder_considerationItem_endAmount_ptr,
                    BasicOrder_considerationAmount_cdPtr,
                    TwoWords // 0x40
                )

                // Calculate EIP712 ConsiderationItem hash and store it in the
                // array of EIP712 consideration hashes.
                // BasicOrder_considerationHashesArray_ptr = 0x160;
                mstore(
                    BasicOrder_considerationHashesArray_ptr,
                    keccak256(
                        BasicOrder_considerationItem_typeHash_ptr,
                        EIP712_ConsiderationItem_size
                    )
                )

                // ===============================================================

                /*
                 * 2. Write a ReceivedItem struct for the primary consideration
                 * item to the consideration array in OrderFulfilled.
                 */

                // Get the length of the additional recipients array.
                // BasicOrder_additionalRecipients_length_cdPtr = 0x264;
                let totalAdditionalRecipients := calldataload(
                    BasicOrder_additionalRecipients_length_cdPtr
                )

                // Calculate pointer to length of OrderFulfilled consideration
                // array.
                // OrderFulfilled_consideration_length_baseOffset = 0x2a0;
                let eventConsiderationArrPtr := add(
                    OrderFulfilled_consideration_length_baseOffset,
                    mul(
                        totalAdditionalRecipients, 
                        OneWord
                    )
                )

                // Set the length of the consideration array to the number of
                // additional recipients, plus one for the primary consideration
                // item.
                mstore(
                    eventConsiderationArrPtr,
                    add(
                        calldataload(
                            BasicOrder_additionalRecipients_length_cdPtr
                        ),
                        1
                    )
                )

                // Overwrite the consideration array pointer so it points to the
                // body of the first element
                eventConsiderationArrPtr := add(
                    eventConsiderationArrPtr,
                    OneWord
                )

                // Set itemType at start of the ReceivedItem memory region.
                mstore(eventConsiderationArrPtr, receivedItemType)

                // Copy calldata region (token, identifier, amount & recipient)
                // from BasicOrderParameters to ReceivedItem memory.
                calldatacopy(
                    add(eventConsiderationArrPtr, Common_token_offset),
                    BasicOrder_considerationToken_cdPtr,
                    FourWords
                )

                /*
                 * 3. Calculate EIP712 ConsiderationItem hashes for original
                 * additional recipients and add a ReceivedItem for each to the
                 * consideration array in the OrderFulfilled event. The original
                 * additional recipients are all the considerations signed by
                 * the offerer aside from the primary consideration of the
                 * order. Uses memory region from 0x80-0x160 as a buffer for
                 * calculating EIP712 ConsiderationItem hashes.
                 */

                // Put pointer to consideration hashes array on the stack.
                // This will be updated as each additional recipient is hashed
                let
                    considerationHashesPtr
                := BasicOrder_considerationHashesArray_ptr

                // Write item type, token, & identifier for additional recipient
                // to memory region for hashing EIP712 ConsiderationItem; these
                // values will be reused for each recipient.
                mstore(
                    BasicOrder_considerationItem_itemType_ptr,
                    additionalRecipientsItemType
                )
                mstore(
                    BasicOrder_considerationItem_token_ptr,
                    additionalRecipientsToken
                )
                mstore(BasicOrder_considerationItem_identifier_ptr, 0)

                // Read length of the additionalRecipients array from calldata
                // and iterate.
                totalAdditionalRecipients := calldataload(
                    BasicOrder_totalOriginalAdditionalRecipients_cdPtr
                )
                let i := 0
                // prettier-ignore
                for {} lt(i, totalAdditionalRecipients) {
                    i := add(i, 1)
                } {
                    /*
                     * Calculate EIP712 ConsiderationItem hash for recipient.
                     */

                    // Retrieve calldata pointer for additional recipient.
                    let additionalRecipientCdPtr := add(
                        BasicOrder_additionalRecipients_data_cdPtr,
                        mul(AdditionalRecipients_size, i)
                    )

                    // Copy startAmount from calldata to the ConsiderationItem
                    // struct.
                    calldatacopy(
                        BasicOrder_considerationItem_startAmount_ptr,
                        additionalRecipientCdPtr,
                        OneWord
                    )

                    // Copy endAmount and recipient from calldata to the
                    // ConsiderationItem struct.
                    calldatacopy(
                        BasicOrder_considerationItem_endAmount_ptr,
                        additionalRecipientCdPtr,
                        AdditionalRecipients_size
                    )

                    // Add 1 word to the pointer as part of each loop to reduce
                    // operations needed to get local offset into the array.
                    considerationHashesPtr := add(
                        considerationHashesPtr,
                        OneWord
                    )

                    // Calculate EIP712 ConsiderationItem hash and store it in
                    // the array of consideration hashes.
                    mstore(
                        considerationHashesPtr,
                        keccak256(
                            BasicOrder_considerationItem_typeHash_ptr,
                            EIP712_ConsiderationItem_size
                        )
                    )

                    /*
                     * Write ReceivedItem to OrderFulfilled data.
                     */

                    // At this point, eventConsiderationArrPtr points to the
                    // beginning of the ReceivedItem struct of the previous
                    // element in the array. Increase it by the size of the
                    // struct to arrive at the pointer for the current element.
                    eventConsiderationArrPtr := add(
                        eventConsiderationArrPtr,
                        ReceivedItem_size
                    )

                    // Write itemType to the ReceivedItem struct.
                    mstore(
                        eventConsiderationArrPtr,
                        additionalRecipientsItemType
                    )

                    // Write token to the next word of the ReceivedItem struct.
                    mstore(
                        add(eventConsiderationArrPtr, OneWord),
                        additionalRecipientsToken
                    )

                    // Copy endAmount & recipient words to ReceivedItem struct.
                    calldatacopy(
                        add(
                            eventConsiderationArrPtr,
                            ReceivedItem_amount_offset
                        ),
                        additionalRecipientCdPtr,
                        TwoWords
                    )
                }

                /*
                 * 4. Hash packed array of ConsiderationItem EIP712 hashes:
                 *   `keccak256(abi.encodePacked(receivedItemHashes))`
                 * Note that it is set at 0x60 — all other memory begins at
                 * 0x80. 0x60 is the "zero slot" and will be restored at the end
                 * of the assembly section and before required by the compiler.
                 */
                mstore(
                    receivedItemsHash_ptr,
                    keccak256(
                        BasicOrder_considerationHashesArray_ptr,
                        mul(add(totalAdditionalRecipients, 1), OneWord)
                    )
                )

                /*
                 * 5. Add a ReceivedItem for each tip to the consideration array
                 * in the OrderFulfilled event. The tips are all the
                 * consideration items that were not signed by the offerer and
                 * were provided by the fulfiller.
                 */

                // Overwrite length to length of the additionalRecipients array.
                totalAdditionalRecipients := calldataload(
                    BasicOrder_additionalRecipients_length_cdPtr
                )
                // prettier-ignore
                for {} lt(i, totalAdditionalRecipients) {
                    i := add(i, 1)
                } {
                    // Retrieve calldata pointer for additional recipient.
                    let additionalRecipientCdPtr := add(
                        BasicOrder_additionalRecipients_data_cdPtr,
                        mul(AdditionalRecipients_size, i)
                    )

                    // At this point, eventConsiderationArrPtr points to the
                    // beginning of the ReceivedItem struct of the previous
                    // element in the array. Increase it by the size of the
                    // struct to arrive at the pointer for the current element.
                    eventConsiderationArrPtr := add(
                        eventConsiderationArrPtr,
                        ReceivedItem_size
                    )

                    // Write itemType to the ReceivedItem struct.
                    mstore(
                        eventConsiderationArrPtr,
                        additionalRecipientsItemType
                    )

                    // Write token to the next word of the ReceivedItem struct.
                    mstore(
                        add(eventConsiderationArrPtr, OneWord),
                        additionalRecipientsToken
                    )

                    // Copy endAmount & recipient words to ReceivedItem struct.
                    calldatacopy(
                        add(
                            eventConsiderationArrPtr,
                            ReceivedItem_amount_offset
                        ),
                        additionalRecipientCdPtr,
                        TwoWords
                    )
                }
            }
        }

        // ============================================================

        {
            /**
             * Next, handle offered items. Memory Layout:
             *  EIP712 data for OfferItem
             *   - 0x80:  OfferItem EIP-712 typehash (constant)
             *   - 0xa0:  itemType
             *   - 0xc0:  token
             *   - 0xe0:  identifier (reused for offeredItemsHash)
             *   - 0x100: startAmount
             *   - 0x120: endAmount
             */

            // Place offer item typehash on the stack.
            bytes32 typeHash = _OFFER_ITEM_TYPEHASH;

            // Utilize assembly to enable reuse of memory regions when possible.
            assembly {
                /*
                 * 1. Calculate OfferItem EIP712 hash
                 */

                // Write the OfferItem typeHash to memory.
                // uint256 constant BasicOrder_offerItem_typeHash_ptr = DefaultFreeMemoryPointer = 0x80;
                mstore(BasicOrder_offerItem_typeHash_ptr, typeHash)

                // struct OfferItem {
                //     ItemType itemType;
                //     address token;
                //     uint256 identifierOrCriteria;
                //     uint256 startAmount;
                //     uint256 endAmount;
                // }

                // Write the OfferItem item type to memory.
                mstore(
                    BasicOrder_offerItem_itemType_ptr, // BasicOrder_offerItem_itemType_ptr = 0xa0;
                    offeredItemType
                )

                // Copy calldata region with (offerToken, offerIdentifier,
                // offerAmount) from OrderParameters to (token, identifier,
                // startAmount) in OfferItem struct. The offerAmount is written
                // to startAmount and endAmount as basic orders do not have
                // dynamic amounts.

                // 將下面的 BasicOrder_offerItem_token_ptr
                // address offerToken;                         // 0xc4  
                // uint256 offerIdentifier;                    // 0xe4  
                // uint256 offerAmount;                        // 0x104 
                calldatacopy(
                    BasicOrder_offerItem_token_ptr, // BasicOrder_offerItem_token_ptr = 0xc0;
                    BasicOrder_offerToken_cdPtr,    // BasicOrder_offerToken_cdPtr = 0xc4;
                    ThreeWords
                )

                // Copy offerAmount from calldata to endAmount in OfferItem
                // struct.
                // 0xc0 + 0x60 = 0x120
                calldatacopy(
                    BasicOrder_offerItem_endAmount_ptr, // BasicOrder_offerItem_endAmount_ptr = 0x120;
                    BasicOrder_offerAmount_cdPtr,       // BasicOrder_offerAmount_cdPtr = 0x104;
                    OneWord
                )

                // Compute EIP712 OfferItem hash, write result to scratch space:
                //   `keccak256(abi.encode(offeredItem))`
                mstore(
                    0,
                    keccak256(
                        BasicOrder_offerItem_typeHash_ptr,
                        EIP712_OfferItem_size
                    )
                )

                /*
                 * 2. Calculate hash of array of EIP712 hashes and write the
                 * result to the corresponding OfferItem struct:
                 *   `keccak256(abi.encodePacked(offerItemHashes))`
                 */
                mstore(
                    BasicOrder_order_offerHashes_ptr, 
                    keccak256(0, OneWord)
                )

                /*
                 * 3. Write SpentItem to offer array in OrderFulfilled event.
                 */
                let eventConsiderationArrPtr := add(
                    OrderFulfilled_offer_length_baseOffset,
                    mul(
                        calldataload(
                            BasicOrder_additionalRecipients_length_cdPtr
                        ),
                        OneWord
                    )
                )

                // Set a length of 1 for the offer array.
                mstore(eventConsiderationArrPtr, 1)

                // Write itemType to the SpentItem struct.
                mstore(add(eventConsiderationArrPtr, OneWord), offeredItemType)

                // Copy calldata region with (offerToken, offerIdentifier,
                // offerAmount) from OrderParameters to (token, identifier,
                // amount) in SpentItem struct.
                calldatacopy(
                    add(eventConsiderationArrPtr, AdditionalRecipients_size),
                    BasicOrder_offerToken_cdPtr,
                    ThreeWords
                )
            }
        }

        {
            /**
             * Once consideration items and offer items have been handled,
             * derive the final order hash. Memory Layout:
             *  0x80-0x1c0: EIP712 data for order
             *   - 0x80:   Order EIP-712 typehash (constant)
             *   - 0xa0:   orderParameters.offerer
             *   - 0xc0:   orderParameters.zone
             *   - 0xe0:   keccak256(abi.encodePacked(offerHashes))
             *   - 0x100:  keccak256(abi.encodePacked(considerationHashes))
             *   - 0x120:  orderParameters.basicOrderType (% 4 = orderType)
             *   - 0x140:  orderParameters.startTime
             *   - 0x160:  orderParameters.endTime
             *   - 0x180:  orderParameters.zoneHash
             *   - 0x1a0:  orderParameters.salt
             *   - 0x1c0:  orderParameters.conduitKey
             *   - 0x1e0:  _counters[orderParameters.offerer] (from storage)
             */

            // Read the offerer from calldata and place on the stack.
            address offerer;
            assembly {
                offerer := calldataload(BasicOrder_offerer_cdPtr)
            }

            // Read offerer's current counter from storage and place on stack.
            uint256 counter = _getCounter(offerer);

            // Load order typehash from runtime code and place on stack.
            bytes32 typeHash = _ORDER_TYPEHASH;

            assembly {
                // Set the OrderItem typeHash in memory.
                mstore(BasicOrder_order_typeHash_ptr, typeHash)

                // Copy offerer and zone from OrderParameters in calldata to the
                // Order struct.
                calldatacopy(
                    BasicOrder_order_offerer_ptr,
                    BasicOrder_offerer_cdPtr,
                    TwoWords
                )

                // Copy receivedItemsHash from zero slot to the Order struct.
                mstore(
                    BasicOrder_order_considerationHashes_ptr,
                    mload(receivedItemsHash_ptr)
                )

                // Write the supplied orderType to the Order struct.
                mstore(BasicOrder_order_orderType_ptr, orderType)

                // Copy startTime, endTime, zoneHash, salt & conduit from
                // calldata to the Order struct.
                calldatacopy(
                    BasicOrder_order_startTime_ptr,
                    BasicOrder_startTime_cdPtr,
                    FiveWords
                )

                // Write offerer's counter, retrieved from storage, to struct.
                mstore(BasicOrder_order_counter_ptr, counter)

                // Compute the EIP712 Order hash.
                orderHash := keccak256(
                    BasicOrder_order_typeHash_ptr,
                    EIP712_Order_size
                )
            }
        }

        assembly {
            /**
             * After the order hash has been derived, emit OrderFulfilled event:
             *   event OrderFulfilled(
             *     bytes32 orderHash,
             *     address indexed offerer,
             *     address indexed zone,
             *     address fulfiller,
             *     SpentItem[] offer,
             *       > (itemType, token, id, amount)
             *     ReceivedItem[] consideration
             *       > (itemType, token, id, amount, recipient)
             *   )
             * topic0 - OrderFulfilled event signature
             * topic1 - offerer
             * topic2 - zone
             * data:
             *  - 0x00: orderHash
             *  - 0x20: fulfiller
             *  - 0x40: offer arr ptr (0x80)
             *  - 0x60: consideration arr ptr (0x120)
             *  - 0x80: offer arr len (1)
             *  - 0xa0: offer.itemType
             *  - 0xc0: offer.token
             *  - 0xe0: offer.identifier
             *  - 0x100: offer.amount
             *  - 0x120: 1 + recipients.length
             *  - 0x140: recipient 0
             */

            // Derive pointer to start of OrderFulfilled event data
            let eventDataPtr := add(
                OrderFulfilled_baseOffset,
                mul(
                    calldataload(BasicOrder_additionalRecipients_length_cdPtr),
                    OneWord
                )
            )

            // Write the order hash to the head of the event's data region.
            mstore(eventDataPtr, orderHash)

            // Write the fulfiller (i.e. the caller) next for receiver argument.
            mstore(add(eventDataPtr, OrderFulfilled_fulfiller_offset), caller())

            // Write the SpentItem and ReceivedItem array offsets (constants).
            mstore(
                // SpentItem array offset
                add(eventDataPtr, OrderFulfilled_offer_head_offset),
                OrderFulfilled_offer_body_offset
            )
            mstore(
                // ReceivedItem array offset
                add(eventDataPtr, OrderFulfilled_consideration_head_offset),
                OrderFulfilled_consideration_body_offset
            )

            // Derive total data size including SpentItem and ReceivedItem data.
            // SpentItem portion is already included in the baseSize constant,
            // as there can only be one element in the array.
            let dataSize := add(
                OrderFulfilled_baseSize,
                mul(
                    calldataload(BasicOrder_additionalRecipients_length_cdPtr),
                    ReceivedItem_size
                )
            )

            // Emit OrderFulfilled log with three topics (the event signature
            // as well as the two indexed arguments, the offerer and the zone).
            log3(
                // Supply the pointer for event data in memory.
                eventDataPtr,
                // Supply the size of event data in memory.
                dataSize,
                // Supply the OrderFulfilled event signature.
                OrderFulfilled_selector,
                // Supply the first topic (the offerer).
                calldataload(BasicOrder_offerer_cdPtr),
                // Supply the second topic (the zone).
                calldataload(BasicOrder_zone_cdPtr)
            )

            // Restore the zero slot.
            mstore(ZeroSlot, 0)
        }

        // Determine whether order is restricted and, if so, that it is valid.
        _assertRestrictedBasicOrderValidity(
            orderHash,
            parameters.zoneHash,
            orderType,
            parameters.offerer,
            parameters.zone
        );

        // Verify and update the status of the derived order.
        _validateBasicOrderAndUpdateStatus(
            orderHash,
            parameters.offerer,
            parameters.signature
        );
    }

    /**
     * @dev Internal function to transfer Ether (or other native tokens) to a
     *      given recipient as part of basic order fulfillment. Note that
     *      conduits are not utilized for native tokens as the transferred
     *      amount must be provided as msg.value.
     *
     * @param amount               The amount to transfer.
     * @param to                   The recipient of the native token transfer.
     * @param additionalRecipients The additional recipients of the order.
     */
    function _transferEthAndFinalize(
        uint256 amount,
        address payable to,
        AdditionalRecipient[] calldata additionalRecipients
    ) internal {
        // Put ether value supplied by the caller on the stack.
        uint256 etherRemaining = msg.value;

        // Retrieve total number of additional recipients and place on stack.
        uint256 totalAdditionalRecipients = additionalRecipients.length;

        // Skip overflow check as for loop is indexed starting at zero.
        unchecked {
            // Iterate over each additional recipient.
            for (uint256 i = 0; i < totalAdditionalRecipients; ++i) {
                // Retrieve the additional recipient.
                AdditionalRecipient calldata additionalRecipient = (
                    additionalRecipients[i]
                );

                // Read ether amount to transfer to recipient & place on stack.
                uint256 additionalRecipientAmount = additionalRecipient.amount;

                // Ensure that sufficient Ether is available.
                if (additionalRecipientAmount > etherRemaining) {
                    revert InsufficientEtherSupplied();
                }

                // Transfer Ether to the additional recipient.
                _transferEth(
                    additionalRecipient.recipient,
                    additionalRecipientAmount
                );

                // Reduce ether value available. Skip underflow check as
                // subtracted value is confirmed above as less than remaining.
                etherRemaining -= additionalRecipientAmount;
            }
        }

        // Ensure that sufficient Ether is still available.
        if (amount > etherRemaining) {
            revert InsufficientEtherSupplied();
        }

        // Transfer Ether to the offerer.
        _transferEth(to, amount);

        // If any Ether remains after transfers, return it to the caller.
        if (etherRemaining > amount) {
            // Skip underflow check as etherRemaining > amount.
            unchecked {
                // Transfer remaining Ether to the caller.
                // 返回給 fulfill 這個 order 的人, 即 msg.sender
                _transferEth(payable(msg.sender), etherRemaining - amount);
            }
        }
    }

    /**
     * @dev Internal function to transfer ERC20 tokens to a given recipient as
     *      part of basic order fulfillment.
     *
     * @param offerer     The offerer of the fulfiller order.
     * @param parameters  The basic order parameters.
     * @param fromOfferer A boolean indicating whether to decrement amount from
     *                    the offered amount.
     * @param accumulator An open-ended array that collects transfers to execute
     *                    against a given conduit in a single call.
     */
    //  _transferERC20AndFinalize(
    //      parameters.offerer,
    //      parameters,
    //      offerTypeIsAdditionalRecipientsType,
    //      accumulator
    //  );
    function _transferERC20AndFinalize(
        address offerer,
        BasicOrderParameters calldata parameters,
        bool fromOfferer,
        bytes memory accumulator
    ) internal {
        // Declare from and to variables determined by fromOfferer value.
        address from;
        address to;

        // Declare token and amount variables determined by fromOfferer value.
        address token;
        uint256 amount;

        // Declare and check identifier variable within an isolated scope.
        {
            // Declare identifier variable determined by fromOfferer value.
            uint256 identifier;

            // Set ERC20 token transfer variables based on fromOfferer boolean.
            if (fromOfferer) {

                // 如果是下面這幾種類型, fromOfferer 為 true

                // ERC721_TO_ERC20_FULL_OPEN,         
                // ERC721_TO_ERC20_PARTIAL_OPEN,      
                // ERC721_TO_ERC20_FULL_RESTRICTED,   
                // ERC721_TO_ERC20_PARTIAL_RESTRICTED,
                                                
                // ERC1155_TO_ERC20_FULL_OPEN,        
                // ERC1155_TO_ERC20_PARTIAL_OPEN,     
                // ERC1155_TO_ERC20_FULL_RESTRICTED,  
                // ERC1155_TO_ERC20_PARTIAL_RESTRICTED

                // 上面代表賣家提供ERC20要換ERC721/ERC1155
                // 所以 offerToken,offerIdentifier,offerAmount 就會是 erc20 相關 info
                // consideration部分就是erc721/erc1155 相關 info

                // 因為這邊是要transfer ERC20 所以, 都是拿 offerXXX 部分

                // Use offerer as from value and msg.sender as to value.
                from = offerer;
                to = msg.sender;

                // Use offer token and related values if token is from offerer.
                token = parameters.offerToken;
                identifier = parameters.offerIdentifier;
                amount = parameters.offerAmount;
            } else {
                // Use msg.sender as from value and offerer as to value.
                                                
                // ERC20_TO_ERC721_FULL_OPEN,         
                // ERC20_TO_ERC721_PARTIAL_OPEN,      
                // ERC20_TO_ERC721_FULL_RESTRICTED,   
                // ERC20_TO_ERC721_PARTIAL_RESTRICTED,
                                                
                // ERC20_TO_ERC1155_FULL_OPEN,        
                // ERC20_TO_ERC1155_PARTIAL_OPEN,     
                // ERC20_TO_ERC1155_FULL_RESTRICTED,  
                // ERC20_TO_ERC1155_PARTIAL_RESTRICTED

                from = msg.sender;
                to = offerer;

                // Otherwise, use consideration token and related values.
                token = parameters.considerationToken;
                identifier = parameters.considerationIdentifier;
                amount = parameters.considerationAmount;
            }

            // Ensure that no identifier is supplied.
            if (identifier != 0) {
                revert UnusedItemParameters();
            }
        }

        // Determine the appropriate conduit to utilize.
        bytes32 conduitKey;

        // Utilize assembly to derive conduit (if relevant) based on route.
        // fromOfferer 為 0 的情況是 
        // ERC20_TO_ERC721,  
        // ERC20_TO_ERC1155, 

        // fromOfferer 為 1 的情況是
        // ERC721_TO_ERC20,
        // ERC1155_TO_ERC20
        // 當 fromOfferer 為 1 會用 offererConduitKey
        // 當 fromOfferer 為 1 表示 賣家出 ERC20 來買 ERC721/ERC1155

        // 當 fromOfferer 為 0 會用 fulfillerConduitKey
        // 當 fromOfferer 為 0 表示 賣家出 ERC721/ERC1155 來買 ERC20
        assembly {
            // Use offerer conduit if fromOfferer, fulfiller conduit otherwise.
            // bytes32 offererConduitKey;                  // 0x1c4                                         
            // bytes32 fulfillerConduitKey;                // 0x1e4
            conduitKey := calldataload(
                sub(
                    BasicOrder_fulfillerConduit_cdPtr, // BasicOrder_fulfillerConduit_cdPtr = 0x1e4;
                    mul(
                        fromOfferer, 
                        OneWord
                    )
                )
            )
        }

        // Retrieve total number of additional recipients and place on stack.
        uint256 totalAdditionalRecipients = (
            parameters.additionalRecipients.length
        );

        // Iterate over each additional recipient.
        for (uint256 i = 0; i < totalAdditionalRecipients; ) {
            // Retrieve the additional recipient.
            AdditionalRecipient calldata additionalRecipient = (
                parameters.additionalRecipients[i]
            );

            uint256 additionalRecipientAmount = additionalRecipient.amount;

            // Decrement the amount to transfer to fulfiller if indicated.
            if (fromOfferer) {
                amount -= additionalRecipientAmount;
            }

            // Transfer ERC20 tokens to additional recipient given approval.
            _transferERC20(
                token,
                from,
                additionalRecipient.recipient,
                additionalRecipientAmount,
                conduitKey,
                accumulator
            );

            // Skip overflow check as for loop is indexed starting at zero.
            unchecked {
                ++i;
            }
        }

        // Transfer ERC20 token amount (from account must have proper approval).
        _transferERC20(token, from, to, amount, conduitKey, accumulator);
    }
}
