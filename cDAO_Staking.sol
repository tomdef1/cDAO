// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.7.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.7.0/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts@4.7.0/access/Ownable.sol";

contract SimpleTokenStakingWithLockup is ReentrancyGuard, Ownable {
    IERC20 public stakingToken;   // Token that users stake.
    IERC20 public rewardToken;    // Token that users earn.

    uint256 public rewardRate;    // Rate at which rewards are generated per token per second.
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public lockupPeriod;   // Lockup period in seconds.

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _stakeTimestamps; // Tracks when users stake.

    // Events
    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 amount, uint256 timestamp);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _stakingToken, address _rewardToken, uint256 _lockupPeriod) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        lockupPeriod = _lockupPeriod;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function stake(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot stake 0");
        _balances[msg.sender] += _amount;
        _stakeTimestamps[msg.sender] = block.timestamp; // Set the stake timestamp
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount, block.timestamp);
    }

    function withdraw(uint256 _amount) public nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot withdraw 0");
        require(block.timestamp - _stakeTimestamps[msg.sender] >= lockupPeriod, "Lockup period has not ended");
        _balances[msg.sender] -= _amount;
        stakingToken.transfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount, block.timestamp);
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / _totalSupply());
    }

    function earned(address account) public view returns (uint256) {
        return
            ((_balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    function _totalSupply() internal view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }

    // Owner can update the lockup period.
    function setLockupPeriod(uint256 _lockupPeriod) external onlyOwner {
        lockupPeriod = _lockupPeriod;
    }

    // Owner can update the reward rate.
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
    }
}
