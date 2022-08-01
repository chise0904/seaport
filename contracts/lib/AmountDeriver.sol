// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {
    AmountDerivationErrors
} from "../interfaces/AmountDerivationErrors.sol";

import "./ConsiderationConstants.sol";

/**
 * @title AmountDeriver
 * @author 0age
 * @notice AmountDeriver contains view and pure functions related to deriving
 *         item amounts based on partial fill quantity and on linear
 *         interpolation based on current time when the start amount and end
 *         amount differ.
 */
contract AmountDeriver is AmountDerivationErrors {
    /**
     * @dev Internal view function to derive the current amount of a given item
     *      based on the current price, the starting price, and the ending
     *      price. If the start and end prices differ, the current price will be
     *      interpolated on a linear basis. Note that this function expects that
     *      the startTime parameter of orderParameters is not greater than the
     *      current block timestamp and that the endTime parameter is greater
     *      than the current block timestamp. If this condition is not upheld,
     *      duration / elapsed / remaining variables will underflow.
     *
     * @param startAmount The starting amount of the item.
     * @param endAmount   The ending amount of the item.
     * @param startTime   The starting time of the order.
     * @param endTime     The end time of the order.
     * @param roundUp     A boolean indicating whether the resultant amount
     *                    should be rounded up or down.
     *
     * @return amount The current amount.
     */
     // 因為 startAmount 和 endAmount 不同, 所以得根據 已經經過多少時間 來求目前是多少amount
     // 根據線性來求解
     // 
    function _locateCurrentAmount(
        uint256 startAmount,
        uint256 endAmount,
        uint256 startTime,
        uint256 endTime,
        bool roundUp
    ) internal view returns (uint256 amount) {
        // Only modify end amount if it doesn't already equal start amount.
        if (startAmount != endAmount) {
            // Declare variables to derive in the subsequent unchecked scope.
            uint256 duration;
            uint256 elapsed;
            uint256 remaining;

            // Skip underflow checks as startTime <= block.timestamp < endTime.
            unchecked {
                // Derive the duration for the order and place it on the stack.
                duration = endTime - startTime;

                // Derive time elapsed since the order started & place on stack.
                elapsed = block.timestamp - startTime;

                // Derive time remaining until order expires and place on stack.
                remaining = duration - elapsed;
            }

            //    startTime                                   endTime
            //    |<-            duration                   ->|
            //    |                blockTime                  |
            //    |<- elapsed    ->|<-     remaining        ->|           
            //    +----------------+--------------------------+
            //    |                |                          |
            //    startAmount      currentAmount              endAmount
            //
            //                                     elapsed
            //    currentAmount = startAmount + -------------- * (endAmount - startAmount)
            //                                     duration
            //                                     elapsed                      elapsed
            //                  = startAmount + -------------- * endAmount - -------------- * startAmount
            //                                     duration                     duration
            //
            //                                     elapsed                        elapsed
            //                  = startAmount - -------------- * startAmount + -------------- * endAmount
            //                                     duration                       duration
            //
            //                       duration         elapsed                        elapsed
            //                  = -------------- - -------------- * startAmount + -------------- * endAmount
            //                       duration         duration                       duration
            //
            //                       duration         elapsed                        elapsed
            //                  = -------------- - -------------- * startAmount + -------------- * endAmount
            //                       duration         duration                       duration
            //
            //                       remaining                      elapsed
            //                  = -------------- * startAmount + -------------- * endAmount
            //                       duration                       duration
            //
            // Aggregate new amounts weighted by time with rounding factor.
            uint256 totalBeforeDivision = ((startAmount * remaining) +
                (endAmount * elapsed));

            // Use assembly to combine operations and skip divide-by-zero check.
            assembly {
                // Multiply by iszero(iszero(totalBeforeDivision)) to ensure
                // amount is set to zero if totalBeforeDivision is zero,
                // as intermediate overflow can occur if it is zero.
                amount := mul(
                    // 如果 totalBeforeDivision == 0
                    // iszero(totalBeforeDivision) = 1
                    // iszero(iszero(totalBeforeDivision)) = 0
                    //
                    // 如果 totalBeforeDivision != 0
                    // iszero(totalBeforeDivision) = 0
                    // iszero(iszero(totalBeforeDivision)) = 1
                    iszero(iszero(totalBeforeDivision)),
                    // Subtract 1 from the numerator and add 1 to the result if
                    // roundUp is true to get the proper rounding direction.
                    // Division is performed with no zero check as duration
                    // cannot be zero as long as startTime < endTime.

                    // #define DIV_ROUND_UP(n,d) (((n) + (d) - 1) / (d))
                    //
                    //    totalBeforeDivision - 1
                    // ----------------------------- + 1
                    //           duration
                    add(
                        div(sub(totalBeforeDivision, roundUp), duration),
                        roundUp
                    )
                )
            }

            // Return the current amount.
            return amount;
        }

        // Return the original amount as startAmount == endAmount.
        return endAmount;
    }

    /**
     * @dev Internal pure function to return a fraction of a given value and to
     *      ensure the resultant value does not have any fractional component.
     *      Note that this function assumes that zero will never be supplied as
     *      the denominator parameter; invalid / undefined behavior will result
     *      should a denominator of zero be provided.
     *
     * @param numerator   A value indicating the portion of the order that
     *                    should be filled.
     * @param denominator A value indicating the total size of the order. Note
     *                    that this value cannot be equal to zero.
     * @param value       The value for which to compute the fraction.
     *
     * @return newValue The value after applying the fraction.
     */
     // _getFraction(numerator, denominator, endAmount);
     // 其實只是在求
     //               numerator
     // newValue = --------------- * value
     //               denominator
    function _getFraction(
        uint256 numerator,
        uint256 denominator,
        uint256 value
    ) internal pure returns (uint256 newValue) {
        // Return value early in cases where the fraction resolves to 1.
        if (numerator == denominator) {
            return value;
        }

        // Ensure fraction can be applied to the value with no remainder. Note
        // that the denominator cannot be zero.
        // 檢查能不能整除, 也就是有沒有餘數
        assembly {
            // Ensure new value contains no remainder via mulmod operator.
            // Credit to @hrkrshnn + @axic for proposing this optimal solution.
            // 因為等等要依照 numerator/denominator 的比例從 value 取除最後的 newValue
            //     numerator
            // ---------------- * value
            //    denominator
            // 並且要確保能整除
            // mulmod(uint x, uint y, uint k) returns (uint): 等於計算 (x * y) % k
            // Some examples:
            // mulmod(3, 4, 5) is equal to 2.
            // mulmod(2**256 - 1, 1, type(uint256).max) is equal to 0.
            // mulmod(2**255, 2**255, type(uint256).max) is equal to 1.
            if mulmod(value, numerator, denominator) {
                // 如果有餘數的話, 就會進到這裡來
                mstore(0, InexactFraction_error_signature)
                revert(0, InexactFraction_error_len)
            }
        }

        // 下面其實就是依照比例得出最後的value而已
        //     numerator
        // ---------------- * value
        //    denominator

        // Multiply the numerator by the value and ensure no overflow occurs.
        uint256 valueTimesNumerator = value * numerator;

        // Divide and check for remainder. Note that denominator cannot be zero.
        assembly {
            // Perform division without zero check.
            newValue := div(valueTimesNumerator, denominator)
        }
    }

    /**
     * @dev Internal view function to apply a fraction to a consideration
     * or offer item.
     *
     * @param startAmount     The starting amount of the item.
     * @param endAmount       The ending amount of the item.
     * @param numerator       A value indicating the portion of the order that
     *                        should be filled.
     * @param denominator     A value indicating the total size of the order.
     * @param startTime       The starting time of the order.
     * @param endTime         The end time of the order.
     * @param roundUp         A boolean indicating whether the resultant
     *                        amount should be rounded up or down.
     *
     * @return amount The received item to transfer with the final amount.
     */
    //  uint256 amount = _applyFraction(
    //                     offerItem.startAmount,
    //                     offerItem.endAmount,
    //                     numerator,
    //                     denominator,
    //                     startTime,
    //                     endTime,
    //                     false
    //                 );
    function _applyFraction(
        uint256 startAmount,
        uint256 endAmount,
        uint256 numerator,
        uint256 denominator,
        uint256 startTime,
        uint256 endTime,
        bool roundUp
    ) internal view returns (uint256 amount) {
        // If start amount equals end amount, apply fraction to end amount.
        if (startAmount == endAmount) {
            // Apply fraction to end amount.
            amount = _getFraction(numerator, denominator, endAmount);
        } else {
            // Otherwise, apply fraction to both and interpolated final amount.
            amount = _locateCurrentAmount(
                _getFraction(numerator, denominator, startAmount),
                _getFraction(numerator, denominator, endAmount),
                startTime,
                endTime,
                roundUp
            );
        }
    }
}
