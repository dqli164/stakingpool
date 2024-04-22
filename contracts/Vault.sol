// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

interface IStakingPool {
    /**
     * @notice A payable function supposed to be called only by WithdrawalVault contract
     * @dev We need a dedicated function because funds received by the default payable function
     * are treated as a user deposit
     */
    function receiveVaultFunds() external payable;
}

contract Valut {

    IStakingPool public immutable STAKINGPOOL;

    // Events
    event FundsReceived(
        address indexed owner,
        uint256 amount,
        uint256 timestamp
    );

    // Errors
    error StakingPoolZeroAddress();
    error TreasuryZeroAddress();
    error NotStakingPool();
    error NotEnoughEther(uint256 requested, uint256 balance);
    error ZeroAmount();

    constructor(IStakingPool stakingPool) {
        if (address(stakingPool) == address(0)) {
            revert StakingPoolZeroAddress();
        }
        STAKINGPOOL = stakingPool;
    }

    /**
     * @notice Withdraw `_amount` of accumulated withdrawals to StakingPool contract
     * @dev Can be called only by the StakingPool contract
     * @param _amount amount of ETH to withdraw
     */
    function withdrawValut(uint256 _amount) external {
        if (msg.sender != address(STAKINGPOOL)) {
            revert NotStakingPool();
        }
        if (_amount == 0) {
            revert ZeroAmount();
        }

        uint256 balance = address(this).balance;
        if (_amount > balance) {
            revert NotEnoughEther(_amount, balance);
        }

        STAKINGPOOL.receiveVaultFunds{value: _amount}();
    }

    /**
     * just estimate rewards of beacon chain
     */
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value, block.timestamp);
    }

    function getBalance() external view returns(uint256) {
        return address(this).balance;
    }
}
