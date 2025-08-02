// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IUSDT } from "../interfaces/IUSDT.sol";

library SafeUSDT {
    /**
     * @dev A failed transfer operation.
     */
    error SafeUSDTFailedOperation();

    /**
     * @dev Returns True if the transfer operation is successful.
     */
    function safeTransfer(IUSDT usdt, address to, uint256 value) internal {
        _callOptionalReturn(usdt, abi.encodeCall(usdt.transfer, (to, value)));
    }

    /**
     * @dev Returns True if the transfer operation is successful.
     */
    function trySafeTransfer(IUSDT usdt, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(usdt, abi.encodeCall(usdt.transfer, (to, value)));
    }

    /**
     * @dev Returns True if the transfer operation is successful.
     */
    function trySafeTransferFrom(IUSDT usdt, address from, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(usdt, abi.encodeCall(usdt.transferFrom, (from, to, value)));
    }

    function _callOptionalReturn(IUSDT token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeUSDTFailedOperation();
        }
    }

    function _callOptionalReturnBool(IUSDT token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
    }
}