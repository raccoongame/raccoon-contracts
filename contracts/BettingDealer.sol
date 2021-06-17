// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RaccoonToken.sol";

contract BettingDealer is Ownable {
    string public name = "Raccoon: BettingDealer";
    using SafeMath for uint256;
    using SafeERC20 for RaccoonToken;

    struct UserInfo {
        uint256 amount;
        uint256 team;
    }

    struct MatchInfo {
        uint256 teamA;
        uint256 teamB;
        uint256 initScoreA;
        uint256 initScoreB;
        uint256 scoreA;
        uint256 scoreB;
        uint256 winner;
        uint256 amountA;
        uint256 amountB;
        uint256 closeTime;
        bool isEnd;
        uint256 totalPlayer;
    }

    RaccoonToken public rac;
    address public stakingMachine;
    address public devAddress;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public stakerPercent;
    uint256 public devPercent;
    uint256 public burnPercent;
    MatchInfo[] public matchInfo;

    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (address => uint256) public claimedReward;

    event ChangeTeam(uint256 indexed mid, address indexed user, uint256 team);
    event AppendBetting(uint256 indexed mid, address indexed user, uint256 amount);
    event CutBetting(uint256 indexed mid, address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 amount);

    constructor(
        RaccoonToken _rac,
        address _stakingMachine,
        address _devAddress,
        uint256 _stakerPercent,
        uint256 _devPercent,
        uint256 _burnPercent
    ) public {
        rac = _rac;
        stakingMachine = _stakingMachine;
        devAddress = _devAddress;
        stakerPercent = _stakerPercent;
        devPercent = _devPercent;
        burnPercent = _burnPercent;
    }

    function updateAddresses(address _stakingMachine, address _devAddress) public onlyOwner {
        stakingMachine = _stakingMachine;
        devAddress = _devAddress;
    }

    function updatePercents(uint256 _stakerPercent, uint256 _devPercent, uint256 _burnPercent) public onlyOwner {
        require(_stakerPercent.add(_devPercent).add(burnPercent) < 100, "updatePercents: BAD PERCENT");
        stakerPercent = _stakerPercent;
        devPercent = _devPercent;
        burnPercent = _burnPercent;
    }

    function matchLength() external view returns (uint256) {
        return matchInfo.length;
    }

    function addMatch(uint256 _teamA, uint256 _teamB, uint256 _initScoreA, uint256 _initScoreB, uint256 _closeTime) public onlyOwner {
        matchInfo.push(MatchInfo({
            teamA: _teamA,
            teamB: _teamB,
            initScoreA: _initScoreA,
            initScoreB: _initScoreB,
            scoreA: 0,
            scoreB: 0,
            winner: 0,
            amountA: 0,
            amountB: 0,
            closeTime: _closeTime,
            isEnd: false,
            totalPlayer: 0
        }));
    }

    function setMatch(uint256 _mid, uint256 _teamA, uint256 _teamB, uint256 _initScoreA, uint256 _initScoreB, uint256 _closeTime) public onlyOwner {
        if (_mid < matchInfo.length) {
            MatchInfo storage matchObj = matchInfo[_mid];
            matchObj.teamA = _teamA;
            matchObj.teamB = _teamB;
            matchObj.initScoreA = _initScoreA;
            matchObj.initScoreB = _initScoreB;
            matchObj.closeTime = _closeTime;
        }
    }

    function setScore(uint256 _mid, uint256 _scoreA, uint256 _scoreB) public onlyOwner {
        if (_mid < matchInfo.length) {
            MatchInfo storage matchObj = matchInfo[_mid];
            matchObj.scoreA = _scoreA;
            matchObj.scoreB = _scoreB;
            uint256 realScoreA = matchObj.scoreA.add(matchObj.initScoreA);
            uint256 realScoreB = matchObj.scoreB.add(matchObj.initScoreB);
            if (realScoreA == realScoreB) { // draw
                matchObj.winner = 0;
            }
            else { // has a winner
                matchObj.winner = realScoreA > realScoreB ? matchObj.teamA : matchObj.teamB;
            }

            (uint256 forStaker, uint256 forDev, uint256 forBurn,) = calculateReward(matchObj.amountA.add(matchObj.amountB));
            if (forStaker > 0) {
                rac.safeTransfer(stakingMachine, forStaker);
            }
            if (forDev > 0) {
                rac.safeTransfer(devAddress, forDev);
            }
            if (forBurn > 0) {
                rac.safeTransfer(burnAddress, forBurn);
            }

            matchObj.isEnd = true;
        }
    }

    function calculateReward(uint256 totalAmount) public view returns (uint256 forStaker, uint256 forDev, uint256 forBurn, uint256 forPlayer) {
        forStaker = totalAmount.mul(stakerPercent).div(100);
        forDev = totalAmount.mul(devPercent).div(100);
        forBurn = totalAmount.mul(burnPercent).div(100);
        if (totalAmount > forStaker.add(forDev).add(forBurn)) {
            forPlayer = totalAmount.sub(forStaker.add(forDev).add(forBurn));
        }
    }

    function pendingRac(address _user) public view returns (uint256) {
        uint256 reward = 0;
        uint256 claimed = claimedReward[_user];
        for (uint256 i = 0; i < matchInfo.length; i++) {
            MatchInfo storage matchObj = matchInfo[i];
            if (matchObj.isEnd) {
                UserInfo storage user = userInfo[i][_user];
                if (user.amount > 0) {
                    if (matchObj.winner == 0) { //draw
                        (,,,uint256 forPlayer) = calculateReward(user.amount);
                        reward = reward.add(forPlayer);
                    }
                    else { // has a winner
                        if (user.team == matchObj.winner) {
                            uint256 amountWinner = matchObj.winner == matchObj.teamA ? matchObj.amountA : matchObj.amountB;
                            (,,,uint256 forPlayer) = calculateReward(matchObj.amountA.add(matchObj.amountB));
                            reward = reward.add(forPlayer.mul(user.amount).div(amountWinner));
                        }
                    }
                }
            }
        }

        if (claimed > 0 && reward >= claimed) {
            reward = reward.sub(claimed);
        }

        return reward;
    }

    function matchCount(address _user) public view returns (uint256 win, uint256 draw, uint256 lose) {
        for (uint256 i = 0; i < matchInfo.length; i++) {
            MatchInfo storage matchObj = matchInfo[i];
            if (matchObj.isEnd) {
                UserInfo storage user = userInfo[i][_user];
                if (user.amount > 0) {
                    if (matchObj.winner == 0) { //draw
                        draw = draw.add(1);
                    }
                    else { // has a winner
                        if (user.team == matchObj.winner) {
                            win = win.add(1);
                        }
                        else {
                            lose = lose.add(1);
                        }
                    }
                }
            }
        }
    }

    function firstBetting(uint256 _mid, uint256 _team, uint256 _amount) public {
        changeTeam(_mid, _team);
        appendBetting(_mid, _amount);
    }

    function changeTeam(uint256 _mid, uint256 _team) public {
        if (_mid < matchInfo.length) {
            MatchInfo storage matchObj = matchInfo[_mid];
            require(matchObj.closeTime > now, "changeTeam: BAD TIMESTAMP");
            require(!matchObj.isEnd, "changeTeam: MATCH ENDED");
            require(_team == matchObj.teamA || _team == matchObj.teamB, "changeTeam: BAD TEAM");
            UserInfo storage user = userInfo[_mid][msg.sender];

            if (_team != user.team) {
                if (user.team == matchObj.teamA) {
                    matchObj.amountA = matchObj.amountA.sub(user.amount);
                    matchObj.amountB = matchObj.amountB.add(user.amount);
                }
                if (user.team == matchObj.teamB) {
                    matchObj.amountB = matchObj.amountB.sub(user.amount);
                    matchObj.amountA = matchObj.amountA.add(user.amount);
                }

                user.team = _team;
            }
            
            emit ChangeTeam(_mid, msg.sender, _team);
        }
    }

    function appendBetting(uint256 _mid, uint256 _amount) public {
        if (_mid < matchInfo.length) {
            MatchInfo storage matchObj = matchInfo[_mid];
            require(matchObj.closeTime > now, "appendBetting: BAD TIMESTAMP");
            require(!matchObj.isEnd, "changeTeam: MATCH ENDED");
            UserInfo storage user = userInfo[_mid][msg.sender];

            if(_amount > 0) {
                rac.safeTransferFrom(address(msg.sender), address(this), _amount);
                
                if (user.amount == 0) {
                    matchObj.totalPlayer = matchObj.totalPlayer.add(1);
                }

                if (user.team == matchObj.teamA) {
                    matchObj.amountA = matchObj.amountA.add(_amount);
                }
                if (user.team == matchObj.teamB) {
                    matchObj.amountB = matchObj.amountB.add(_amount);
                }

                user.amount = user.amount.add(_amount);
            }

            emit AppendBetting(_mid, msg.sender, _amount);
        }
    }

    function cutBetting(uint256 _mid, uint256 _amount) public {
        if (_mid < matchInfo.length) {
            MatchInfo storage matchObj = matchInfo[_mid];
            require(matchObj.closeTime > now, "cutBetting: BAD TIMESTAMP");
            UserInfo storage user = userInfo[_mid][msg.sender];

            if(_amount > 0) {
                if (user.team == matchObj.teamA) {
                    matchObj.amountA = matchObj.amountA.sub(_amount);
                }
                if (user.team == matchObj.teamB) {
                    matchObj.amountB = matchObj.amountB.sub(_amount);
                }

                user.amount = user.amount.sub(_amount);
                if (user.amount == 0) {
                    matchObj.totalPlayer = matchObj.totalPlayer.sub(1);
                }

                rac.safeTransfer(address(msg.sender), _amount);
            }

            emit CutBetting(_mid, msg.sender, _amount);
        }
    }

    function claimReward() public {
        uint256 reward = pendingRac(msg.sender);
        if (reward > 0) {
            claimedReward[msg.sender] = claimedReward[msg.sender].add(reward);
            rac.safeTransfer(address(msg.sender), reward);

            emit ClaimReward(msg.sender, reward);
        }
    }

    receive() external payable {}
}