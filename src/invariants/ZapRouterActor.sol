pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";

contract ZapRouterActor {
    address[] public tokens;
    address public zapRouter;
    address public leverageZapRouter;
    address public sender;

    constructor(
        address[] memory _tokens,
        address _zapRouter,
        address _leverageZapRouter,
        address _sender
    ) payable {
        tokens = _tokens;
        zapRouter = _zapRouter;
        leverageZapRouter = _leverageZapRouter;
        sender = _sender;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (zapRouter != address(0)) {
                IERC20(tokens[i]).approve(zapRouter, type(uint256).max);
                hevm.prank(sender);
                IERC20(tokens[i]).approve(zapRouter, type(uint256).max);                
            }
            if (leverageZapRouter != address(0)) {
                IERC20(tokens[i]).approve(leverageZapRouter, type(uint256).max);
                hevm.prank(sender);
                IERC20(tokens[i]).approve(leverageZapRouter, type(uint256).max);
            }
        }
    }

    function proxy(
        address _target,
        bytes memory _calldata,
        bool spoofSender
    ) public returns (bool success, bytes memory returnData) {
        if (spoofSender) {
            hevm.prank(sender);
        }
        (success, returnData) = address(_target).call(_calldata);
    }

    function proxy(
        address _target,
        bytes memory _calldata,
        uint256 value,
        bool spoofSender
    ) public returns (bool success, bytes memory returnData) {
        if (spoofSender) {
            hevm.prank(sender);
        }
        (success, returnData) = address(_target).call{value: value}(_calldata);
    }

    receive() external payable {}
}
