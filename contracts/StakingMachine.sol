// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RaccoonToken.sol";

contract StakingMachine is Ownable {
    string public name = "Raccoon: StakingMachine";
    using SafeMath for uint256;
    using SafeERC20 for RaccoonToken;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    RaccoonToken public rac;
    uint256 public startBlock;
    uint256 public totalReward;
    uint256 public lastReward;
    uint256 public lastRewardBlock;
    uint256 public totalAmount;
    uint256 public totalStaker;
    uint256 public accRacPerShare;

    mapping (address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        RaccoonToken _rac,
        uint256 _startBlock
    ) public {
        rac = _rac;
        startBlock = _startBlock;
    }

    // It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do.
        require(msg.sender == tx.origin, "StakingMachine: must use EOA");
        _;
    }

    function pendingRac(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRacPerShareNow = accRacPerShare;
        if (block.number > lastRewardBlock && totalAmount != 0) {
            uint256 racReward = 0;
            uint256 balance = rac.balanceOf(address(this));
            if (balance > lastReward.mul(1e18).add(totalAmount)) {
                racReward = balance.sub(lastReward.mul(1e18).add(totalAmount));
            }
            
            accRacPerShareNow = accRacPerShareNow.add(racReward.mul(1e18).div(totalAmount));
        }
        return user.amount.mul(accRacPerShareNow).div(1e18).sub(user.rewardDebt);
    }

    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        if (totalAmount == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 racReward = 0;
        uint256 balance = rac.balanceOf(address(this));
        if (balance > lastReward.mul(1e18).add(totalAmount)) {
            racReward = balance.sub(lastReward.mul(1e18).add(totalAmount));
        }
        
        accRacPerShare = accRacPerShare.add(racReward.mul(1e18).div(totalAmount));
        totalReward = totalReward.add(racReward);
        lastReward = lastReward.add(racReward);
        lastRewardBlock = block.number;
    }

    function harvest(address _user) internal {
        UserInfo storage user = userInfo[_user];

        uint256 amount = user.amount;
        if (amount > 0) {
            uint256 pending = pendingRac(_user);

            if (pending > lastReward) {
                pending = lastReward;
            }

            if (pending > 0) {
                rac.transfer(_user, pending);
            }

            lastReward = lastReward.sub(pending);
            user.rewardDebt = user.amount.mul(accRacPerShare).div(1e18);
        }
    }

    function deposit(uint256 _amount) public onlyEOA {
        UserInfo storage user = userInfo[msg.sender];

        updatePool();
        harvest(msg.sender);

        if (_amount > 0) {
            rac.safeTransferFrom(address(msg.sender), address(this), _amount);
            
            if (user.amount == 0) {
                totalStaker = totalStaker.add(1);
            }

            user.amount = user.amount.add(_amount);
            totalAmount = totalAmount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(accRacPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public onlyEOA {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: BAD AMOUNT");

        updatePool();
        harvest(msg.sender);

        if (_amount > 0 && totalAmount >= _amount) {
            user.amount = user.amount.sub(_amount);
            rac.transfer(address(msg.sender), _amount);
            totalAmount = totalAmount.sub(_amount);

            if (user.amount == 0 && totalStaker >= 1) {
                totalStaker = totalStaker.sub(1);
            }
        }
        user.rewardDebt = user.amount.mul(accRacPerShare).div(1e18);
        emit Withdraw(msg.sender, _amount);
    }

    function racPerBlock() public view returns (uint256) {
        uint256 multiplier = block.number.sub(startBlock);
        if (multiplier > 0) {
            uint256 racReward = 0;
            uint256 balance = rac.balanceOf(address(this));
            if (balance > lastReward.mul(1e18).add(totalAmount)) {
                racReward = balance.sub(lastReward.mul(1e18).add(totalAmount));
            }
            
            uint256 totalRewardNow = totalReward.add(racReward);
            return totalRewardNow.div(multiplier);
        }
    }

    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        rac.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    receive() external payable {}
}