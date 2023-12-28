// SPDX-License-Identifier: Apache-2.0

//___________________________________________________________
/************************************************************
Contract: Stake ERC20 - Recieve ERC20 with Advanced Functions

Author: https://www.tomdefi.com
X: https://twitter.com/Tom__DeFi
TG: https://t.me/tom_defi

-Abstract:
ERC20 to ERC20 staking contract with advanced customisable functions.
Deployable on L1s that do not yet implement 0xPush by utilising the OpenZeppelin 4.7.0 contract libraries.

-Overview:
This contract allows users to stake an ERC20 token and earn rewards in another ERC20 token over time. 
The owner and designated controllers can update critical parameters like the staking and reward tokens, lockup period, and reward rate. 
Users can stake and unstake tokens, and the contract includes a mechanism to recover any ERC20 tokens accidentally sent to it. 
The contract uses role-based access control to allow multiple accounts to manage its operation securely.

**The reward calculations begin when the first user stakes tokens**

Owner-Level (Admin and Controller) Functions:
-setStakingToken(address): Update the staking token's address.
-setRewardToken(address): Update the reward token's address.
-setLockupPeriod(uint256): Update the lockup period.
-setRewardRate(uint256, uint256): Set the reward rate as the number of tokens distributed over a time period.
-setStakingEndTime(uint256): Set when staking should end.
-recoverERC20(address, uint256): Recover any ERC20 tokens sent to the contract.
-setRewardPool(uint256): Set the total reward pool amount.
-addController(address): Grant a user the controller role.
-removeController(address): Revoke the controller role from a user.

Public Read Functions:
-totalStaked(): View the total amount of tokens staked in the contract.
-stakingActive(): Check if staking is currently active.
-remainingStakingTime(): Get the remaining time in seconds for the staking period.
-totalRewardPoolSize(): View the total size of the reward pool.
-numberOfStakers(): Get the number of addresses that have staked.
-userStake(address): View the amount of tokens staked by a specific user.
-userStakeTimestamp(address): View the timestamp when a user last staked.
-userTotalEarned(address): Get the total amount of rewards a user has earned all-time.
-userEarnedCurrentPeriod(address): Get the amount of rewards a user has earned during the current period.

User Functions:
-stake(uint256): Stake a specified amount of tokens.
-withdraw(uint256): Withdraw a specified amount of staked tokens.
-exit(): Withdraw all staked tokens and get all rewards.
-getReward(): Withdraw just the rewards earned.
_________________________________________________________________________________
********************************************************************************/

pragma solidity 0.8.18;

import "@openzeppelin/contracts@4.7.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.7.0/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts@4.7.0/access/AccessControl.sol";

contract ERC20Staking0818_tomdefi is ReentrancyGuard, AccessControl {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public lockupPeriod;
    uint256 public stakingEndTime;
    uint256 public totalRewardPool;
    uint256 public totalStakers;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _stakeTimestamps;
    mapping(address => bool) private _hasStaked;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event StakingTokenUpdated(address indexed newStakingToken);
    event RewardTokenUpdated(address indexed newRewardToken);
    event LockupPeriodUpdated(uint256 newLockupPeriod);
    event RewardRateUpdated(uint256 newRewardRate);
    event StakingEndTimeUpdated(uint256 newEndTime);
    event ERC20Recovered(address token, uint256 amount);

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _lockupPeriod
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(CONTROLLER_ROLE, msg.sender);
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        lockupPeriod = _lockupPeriod;
        stakingEndTime = type(uint256).max; // Set far in the future
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
        require(block.timestamp < stakingEndTime, "Staking has ended");
        require(_amount > 0, "Cannot stake 0");
        if (!_hasStaked[msg.sender]) {
            totalStakers += 1;
            _hasStaked[msg.sender] = true;
        }
        _balances[msg.sender] += _amount;
        _stakeTimestamps[msg.sender] = block.timestamp;
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot withdraw 0");
        require(_balances[msg.sender] >= _amount, "Insufficient staked amount");
        require(block.timestamp - _stakeTimestamps[msg.sender] >= lockupPeriod || block.timestamp > stakingEndTime, "Lockup period has not ended or staking still active");
        _balances[msg.sender] -= _amount;
        stakingToken.transfer(msg.sender, _amount);
        if (_balances[msg.sender] == 0) {
            totalStakers -= 1;
            _hasStaked[msg.sender] = false;
        }
        emit Withdrawn(msg.sender, _amount);
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
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / _totalSupply());
    }

    function earned(address account) public view returns (uint256) {
        return ((_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    function _totalSupply() internal view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }

    // Owner and Controller level functions

    function setRewardPool(uint256 _rewardAmount) external onlyRole(CONTROLLER_ROLE) {
        require(_rewardAmount > 0, "Reward amount must be greater than 0");
        totalRewardPool = _rewardAmount;
        // Optionally, transfer the tokens from the msg.sender to the contract here if needed
        // rewardToken.transferFrom(msg.sender, address(this), _rewardAmount);
    }

    function setStakingToken(address _newStakingToken) external onlyRole(CONTROLLER_ROLE) {
        require(_newStakingToken != address(0), "New staking token address is the zero address");
        stakingToken = IERC20(_newStakingToken);
        emit StakingTokenUpdated(_newStakingToken);
    }

    function setRewardToken(address _newRewardToken) external onlyRole(CONTROLLER_ROLE) {
        require(_newRewardToken != address(0), "New reward token address is the zero address");
        rewardToken = IERC20(_newRewardToken);
        emit RewardTokenUpdated(_newRewardToken);
    }

    function setLockupPeriod(uint256 _newLockupPeriod) external onlyRole(CONTROLLER_ROLE) {
        lockupPeriod = _newLockupPeriod;
        emit LockupPeriodUpdated(_newLockupPeriod);
    }

    function setRewardRate(uint256 _tokens, uint256 _durationInSeconds) external onlyRole(CONTROLLER_ROLE) {
        require(_durationInSeconds > 0, "Duration must be greater than 0");
        rewardRate = _tokens / _durationInSeconds;
        emit RewardRateUpdated(rewardRate);
    }

    function setStakingEndTime(uint256 _endTime) external onlyRole(CONTROLLER_ROLE) {
        require(_endTime > block.timestamp, "End time must be in the future");
        stakingEndTime = _endTime;
        emit StakingEndTimeUpdated(_endTime);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyRole(CONTROLLER_ROLE) {
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        emit ERC20Recovered(tokenAddress, tokenAmount);
    }

    function addController(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(CONTROLLER_ROLE, account);
    }

    function removeController(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(CONTROLLER_ROLE, account);
    }

    // Read functions

    function totalStaked() public view returns (uint256) {
        return _totalSupply();
    }

    function stakingActive() public view returns (bool) {
        return block.timestamp < stakingEndTime;
    }

    function remainingStakingTime() public view returns (uint256) {
        if (block.timestamp >= stakingEndTime) {
            return 0;
        }
        return stakingEndTime - block.timestamp;
    }

    function totalRewardPoolSize() public view returns (uint256) {
        return totalRewardPool;
    }

    function numberOfStakers() public view returns (uint256) {
        return totalStakers;
    }

    function userStake(address account) public view returns (uint256) {
        return _balances[account];
    }

    function userStakeTimestamp(address account) public view returns (uint256) {
        return _stakeTimestamps[account];
    }

    function userTotalEarned(address account) public view returns (uint256) {
        return rewards[account] + (earned(account) - rewards[account]);
    }

    function userEarnedCurrentPeriod(address account) public view returns (uint256) {
        return earned(account) - rewards[account];
    }
}
