// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDSAAccount {
    function cast(
        string[] calldata _targetNames,
        bytes[] calldata _datas,
        address _origin
    ) external;
}
