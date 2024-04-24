// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface IStakingPool {
    /**
     * @notice A payable function supposed to be called only by WithdrawalVault contract
     * @dev We need a dedicated function because funds received by the default payable function
     * are treated as a user deposit
     */
    function receiveVaultFunds() external payable;
}

contract Vault is Initializable {
    address private STAKING_POOL_PROXY_ADDRESS;

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

    function initialize(address addr) public initializer {
        require(addr != address(0), "INVALID STAKING POOL ADDRESS");
        STAKING_POOL_PROXY_ADDRESS = addr;
    }

    /**
     * @notice Withdraw `_amount` of accumulated withdrawals to StakingPool contract
     * @dev Can be called only by the StakingPool contract
     * @param _amount amount of ETH to withdraw
     */
    function withdrawVault(uint256 _amount) external {
        if (msg.sender != address(STAKING_POOL_PROXY_ADDRESS)) {
            revert NotStakingPool();
        }
        if (_amount == 0) {
            revert ZeroAmount();
        }

        uint256 balance = address(this).balance;
        if (_amount > balance) {
            revert NotEnoughEther(_amount, balance);
        }

        IStakingPool(STAKING_POOL_PROXY_ADDRESS).receiveVaultFunds{value: _amount}();
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

    function getStakingPoolProxyAddress() external view returns(address) {
        return STAKING_POOL_PROXY_ADDRESS;
    }
}
