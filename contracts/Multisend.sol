// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RaccoonToken.sol";

contract Multisend is Ownable {
    bytes32 public name = "Multisend";
    using SafeMath for uint256;
    using SafeERC20 for RaccoonToken;

    RaccoonToken public rac;

    constructor(RaccoonToken _rac) public {
        rac = _rac;
    }

    function multisend(address[] memory _addresses, uint256[] memory _amount) public onlyOwner {
        require(_addresses.length == _amount.length, "multisend: BAD ARRAY");
        for (uint256 i = 0; i < _addresses.length; i++) {
            rac.safeTransfer(_addresses[i], _amount[i].mul(1e18));
        }
    }

    receive() external payable {}
}