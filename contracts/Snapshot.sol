// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract Snapshot {
    address public owner;

    // shares
    mapping (address => uint256) private shares; // 用户的share份额
    uint256 public totalShares;  // 总的share份额

    // snapshot 
    struct Checkpoint {
        uint128 fromBlock;
        uint128 value;
    }
    mapping (address => Checkpoint[]) shareSnapshot;
    Checkpoint[] totalShareHistory;

    // pool
    struct Pool {
        uint256 totalDeposited; // 总共充值了多少
        uint256 totalRedeemed; // 总共赎回了多少
        uint256 totalRewards; // 总收益
        uint256 availableFunds; // 可用资金
        uint256 ethToLock; // 被锁定的用来满足提款的资金
        uint256 lastRewardTime; // 上一次获取收益的时间
        uint256 depositedValidators; // 充值的验证者数量
    }
    Pool public pool; // 池子

    event Deposited(address indexed sender, uint256 amountOfETH, uint256 amountOfShares, uint256 timestamp);

    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice 用户向池子发送资金进行质押
     */
    function deposit() external payable returns (uint256)  {
        require(msg.value > 0, "ZERO_DEPOSIT");
        return _deposit(msg.sender, msg.value);
    }

    function _deposit(address account, uint256 amount) internal returns (uint256)  {
        uint256 amountOfShares = _getSharesByETHAmount(amount);
        shares[account] += amountOfShares;
        totalShares += amountOfShares;
        pool.totalDeposited += amount;
        pool.availableFunds += amount;

        // create snapshot
        _createShareSnapshot(account, amountOfShares);
        emit Deposited(account, amount, amountOfShares, block.timestamp);
        return amountOfShares;
    }

    function _createShareSnapshot(address account, uint256 amountOfShares) internal {
        uint curTotalSupply = totalShareSupply();
        require(curTotalSupply + amountOfShares >= curTotalSupply, "overflow"); // Check for overflow
        uint previousshareTo = _shareOf(account);
        require(previousshareTo + amountOfShares >= previousshareTo, "overflow"); // Check for overflow
        updateValueAtNow(totalShareHistory, curTotalSupply + amountOfShares);
        updateValueAtNow(shareSnapshot[account], previousshareTo + amountOfShares);
    }

    function _shareOf(address _owner) internal view returns (uint256 share) {
        return shareOfAt(_owner, block.number);
    }

    function shareOf() external view  returns (uint256 share) {
        return shareOfAt(msg.sender, block.number);
    }

    function updateValueAtNow(Checkpoint[] storage checkpoints, uint _value) internal {
        if ((checkpoints.length == 0) || (checkpoints[checkpoints.length - 1].fromBlock < block.number)) {
            checkpoints.push(Checkpoint(uint128(block.number), uint128(_value)));
        } else {
           checkpoints[checkpoints.length - 1].value = uint128(_value);
        }
    }

    function shareOfAt(address _owner, uint _blockNumber) public view returns (uint) {
        if ((shareSnapshot[_owner].length == 0) || (shareSnapshot[_owner][0].fromBlock > _blockNumber)) {
            return 0;
        } else {
            return getValueAt(shareSnapshot[_owner], _blockNumber);
        }
    }

    function getValueAt(Checkpoint[] storage checkpoints, uint _block) view internal returns (uint) {
        if (checkpoints.length == 0)
            return 0;
        // Shortcut for the actual value
        if (_block >= checkpoints[checkpoints.length-1].fromBlock)
            return checkpoints[checkpoints.length-1].value;
        if (_block < checkpoints[0].fromBlock)
            return 0;

        // Binary search of the value in the array
        uint _min = 0;
        uint max = checkpoints.length-1;
        while (max > _min) {
            uint mid = (max + _min + 1) / 2;
            if (checkpoints[mid].fromBlock<=_block) {
                _min = mid;
            } else {
                max = mid-1;
            }
        }
        return checkpoints[_min].value;
    }

    function totalShareSupply() public view returns (uint) {
        return totalShareSupplyAt(block.number);
    }

    function totalShareSupplyAt(uint _blockNumber) public view returns(uint) {
        if ((totalShareHistory.length == 0) || (totalShareHistory[0].fromBlock > _blockNumber)) {
            return 0;
        } else {
            return getValueAt(totalShareHistory, _blockNumber);
        }
    }

    // Calculate the amount of shares backed by an amount of ETH
    function _getSharesByETHAmount(uint256 ethAmount) internal view returns (uint256) {
        // Use 1:1 ratio if no shares
        if (pool.totalDeposited == 0) { 
            return ethAmount; 
        }
        require(_getTotalETHBalance() > 0, "Cannot calculate shares amount while total deposited balance is zero");
        // Calculate and return
        return ethAmount * totalShares / _getTotalETHBalance();
    }

    function _getTotalETHBalance() internal view returns (uint256) {
        return pool.totalDeposited + pool.totalRewards - pool.totalRedeemed - pool.ethToLock;
    }
}
