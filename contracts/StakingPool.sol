// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

interface IVault {
    function withdrawValut(uint256 amount) external;
}

interface IDepositContract {
    function deposit(
        bytes calldata pubkey, // 48 bytes
        bytes calldata withdrawal_credentials, // 32 bytes
        bytes calldata signature, // 96 bytes
        bytes32 deposit_data_root
    ) external payable;
}

contract StakingPool {
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not Owner");
        _;
    }
    // shares
    mapping(address => uint256) private shares; // 用户的share份额
    uint256 private totalShares; // 总的share份额

    // pool
    struct Pool {
        uint256 totalDeposited; // 总共充值了多少
        uint256 totalRedeemed; // 总共赎回了多少
        uint256 totalRewards; // 总收益
        uint256 totalLossed; // 总工损失了多少
        uint256 ethToLock; // 锁定在信标链上的资金
        uint256 ethToMeetWithdraw; // 被锁定的用来满足提款的资金
        uint256 lastRewardTime; // 上一次获取收益的时间
    }
    Pool public pool; // 池子

    // whitelist
    bool private whitelistEnabled; // 是否开启白名单
    mapping(address => bool) private whitelists; // 仅白名单中的用户可以直接向合约转账

    bool private depositPaused; // 是否暂停充值

    // deposit size
    uint256 private constant DEPOSIT_SIZE = 32 ether;

    // MainNet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    // Holesky: 0x4242424242424242424242424242424242424242
    address DEPOSIT_CONTRACT_ADDRESS;
    address VAULT_CONTRACT_ADDRESS;

    // The amount of ETH withdrawn from Valut to current contract
    event RewardsReceived(uint256 amount, uint256 timestamp);

    event Deposited(
        address indexed sender,
        uint256 amountOfETH,
        uint256 amountOfShares,
        uint256 timestamp
    );
    event BeaconChainDepositEvent(
        bytes pubkey,
        bytes withdrawalCredentials,
        bytes signature,
        uint256 amount,
        uint256 timestamp
    );
    error NotEnoughEtherToDeposit();
    error AccountNotInWhitelist();

    function initializer(address depositContractAddress) public {
        owner = msg.sender;
        DEPOSIT_CONTRACT_ADDRESS = depositContractAddress;
    }

    /**
     * @notice 用户向池子发送资金进行质押
     */
    function deposit() external payable returns (uint256) {
        require(msg.value > 0, "ZERO_DEPOSIT");
        return _deposit(msg.sender, msg.value);
    }

    function _deposit(address account, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 amountOfShares = _getSharesByETHAmount(amount);
        shares[account] += amountOfShares;
        totalShares += amountOfShares;
        pool.totalDeposited += amount;

        emit Deposited(account, amount, amountOfShares, block.timestamp);
        return amountOfShares;
    }

    /**
     * @notice 激活验证者
     */
    function activateValidator(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable onlyOwner {
        if (_getPoolAvailableFunds() < DEPOSIT_SIZE)
            revert NotEnoughEtherToDeposit();

        pool.ethToLock += DEPOSIT_SIZE;

        // 充值
        IDepositContract DEPOSIT_CONTRACT = IDepositContract(
            DEPOSIT_CONTRACT_ADDRESS
        );
        DEPOSIT_CONTRACT.deposit{value: DEPOSIT_SIZE}(
            pubkey,
            withdrawalCredentials,
            signature,
            depositDataRoot
        );

        emit BeaconChainDepositEvent(
            pubkey,
            withdrawalCredentials,
            signature,
            DEPOSIT_SIZE,
            block.timestamp
        );
    }

    function receiveVaultFunds() external payable {
        require(msg.sender == VAULT_CONTRACT_ADDRESS, "Not Vault");
        emit RewardsReceived(msg.value, block.timestamp);
    }

    function submitReport(
        address vaultAddress,
        uint256 rewards,
        uint256 refunds
    ) external onlyOwner {
        // collect funds from vault
        VAULT_CONTRACT_ADDRESS = vaultAddress;
        IVault VAULT_CONTRACT = IVault(vaultAddress);

        if (rewards + refunds > 0) {
            VAULT_CONTRACT.withdrawValut(rewards + refunds); // 提取资金
            pool.lastRewardTime = block.timestamp;
            pool.totalRewards += rewards; // 增加奖励

            if (refunds >= DEPOSIT_SIZE) {
                // refunds + rewards
                uint256 exitedValidators = refunds / DEPOSIT_SIZE;
                uint256 rewardFromRefunds = refunds -
                    exitedValidators *
                    DEPOSIT_SIZE;
                pool.totalRewards += rewardFromRefunds;
                pool.ethToLock -= exitedValidators * DEPOSIT_SIZE; // 减少锁定的ETH数量
            }
            if (refunds > 0 && refunds < DEPOSIT_SIZE) {
                // penalty
                uint256 penalty = DEPOSIT_SIZE - refunds;
                pool.totalLossed += penalty; // 增加损失
                pool.ethToLock -= DEPOSIT_SIZE; // 减少锁定的ETH数量
            }
        }

        // 满足提现请求
        uint256 ethToMeetWithdraw = _finalize();
        pool.ethToMeetWithdraw += ethToMeetWithdraw;
    }

    // Calculate the amount of shares backed by an amount of ETH
    function _getSharesByETHAmount(uint256 ethAmount)
        internal
        view
        returns (uint256)
    {
        // Use 1:1 ratio if no shares
        if (pool.totalDeposited == 0) {
            return ethAmount;
        }
        require(
            _getTotalETHBalance() > 0,
            "Cannot calculate shares amount while total deposited balance is zero"
        );
        // Calculate and return
        return (ethAmount * totalShares) / _getTotalETHBalance();
    }

    // Calculate the amount of eth backed by shares
    function _getETHAmountByShares(uint256 amountOfShares)
        internal
        view
        returns (uint256)
    {
        return (amountOfShares * _getTotalETHBalance()) / totalShares;
    }

    function _getUserBalance(address account) internal view returns (uint256) {
        return (shares[account] * _getTotalETHBalance()) / totalShares;
    }

    function _getPoolAvailableFunds() internal view returns (uint256) {
        return _getTotalETHBalance() - pool.ethToLock - pool.ethToMeetWithdraw;
    }

    function _getTotalETHBalance() internal view returns (uint256) {
        return
            pool.totalDeposited +
            pool.totalRewards -
            pool.totalRedeemed -
            pool.totalLossed;
    }

    function getUserBalance(address account) external view returns (uint256) {
        return _getUserBalance(account);
    }

    function getUserShares(address account) external view returns (uint256) {
        return shares[account];
    }

    function getTotalShares() external view returns (uint256) {
        return totalShares;
    }

    function enableWhitelist(bool status) external onlyOwner returns (bool) {
        whitelistEnabled = status;
        return whitelistEnabled;
    }

    function addWhitelist(address account) external onlyOwner {
        whitelists[account] = true;
    }

    function deleteWhitelist(address account) external onlyOwner {
        whitelists[account] = false;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid Owner");
        owner = newOwner;
    }

    receive() external payable {
        if (whitelistEnabled && !whitelists[msg.sender]) {
            revert AccountNotInWhitelist();
        }
        _deposit(msg.sender, msg.value);
    }

    /******** WithdrawQueue ********/
    /// @dev queue for withdrawal requests, indexes (requestId) start from 1
    bytes32 internal constant QUEUE_POSITION =
        keccak256("WithdrawalQueue.queue");
    /// @dev last index in request queue
    uint256 private LAST_REQUEST_ID_POSITION;
    /// @dev last index of finalized request in the queue
    uint256 private LAST_FINALIZED_REQUEST_ID_POSITION;
    uint256 public constant WEI_PER_ETHER = 1e18;

    error NotEnoughEther();
    error NotEnoughShares();
    error InvalidRequestId(uint256 _requestId);
    error CantSendValueRecipientMayHaveReverted();
    error NotOwner(address _sender, address _owner);
    error RequestAlreadyClaimed(uint256 _requestId);
    error RequestNotFoundOrNotFinalized(uint256 _requestId);

    event WithdrawalRequested(
        uint256 indexed requestId,
        address indexed owner,
        uint256 amount
    );

    event WithdrawalsFinalized(
        uint256 indexed from,
        uint256 indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event WithdrawalClaimed(
        uint256 indexed requestId,
        address indexed owner,
        uint256 amount
    );

    event NotEnoughEtherToRedeem(
        uint256 indexed requestId,
        address indexed owner,
        uint256 amount,
        uint256 timestamp
    );

    struct WithdrawalRequest {
        uint256 amount;
        address owner;
        uint40 timestamp;
        bool claimed;
    }

    struct WithdrawalRequestStatus {
        uint256 amount;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function _getQueue()
        internal
        pure
        returns (mapping(uint256 => WithdrawalRequest) storage queue)
    {
        bytes32 position = QUEUE_POSITION;
        assembly {
            queue.slot := position
        }
    }

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new WithdrawalRequestStatus[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            statuses[i] = _getStatus(_requestIds[i]);
        }
    }

    function _getStatus(uint256 _requestId)
        internal
        view
        returns (WithdrawalRequestStatus memory status)
    {
        if (_requestId == 0 || _requestId > getLastRequestId())
            revert InvalidRequestId(_requestId);
        WithdrawalRequest memory request = _getQueue()[_requestId];
        status = WithdrawalRequestStatus(
            request.amount,
            request.owner,
            request.timestamp,
            _requestId <= getLastFinalizedRequestId(),
            request.claimed
        );
    }

    function _finalize() internal returns (uint256 ethToMeetWithdraw) {
        uint256 currentBatchIndex = 1;
        uint256 lastFinalizedRequestId = getLastFinalizedRequestId();
        while (ethToMeetWithdraw <= _getPoolAvailableFunds()) {
            uint256 requestId = lastFinalizedRequestId + currentBatchIndex;
            if (requestId > getLastRequestId()) {
                break;
            }
            WithdrawalRequest memory request = _getQueue()[requestId];
            // if (request.timestamp < block.timestamp + 24 * 60 * 60) { // 发起提款24h后的请求才能被确认
            //     break;
            // }
            if (ethToMeetWithdraw + request.amount > _getPoolAvailableFunds()) {
                emit NotEnoughEtherToRedeem(
                    requestId,
                    request.owner,
                    request.amount,
                    block.timestamp
                );
                break;
            }
            ethToMeetWithdraw += request.amount;
            _setLastFinalizedRequestId(requestId);
            emit WithdrawalsFinalized(
                requestId - 1,
                requestId,
                request.amount,
                block.timestamp
            );

            unchecked {
                ++currentBatchIndex;
            }
        }
    }

    function _enqueue(uint256 amountOfETH, address _owner)
        internal
        returns (uint256 requestId)
    {
        uint256 lastRequestId = getLastRequestId();
        requestId = lastRequestId + 1;
        _setLastRequestId(requestId);

        WithdrawalRequest memory newRequest = WithdrawalRequest(
            amountOfETH,
            _owner,
            uint40(block.timestamp),
            false
        );

        _getQueue()[requestId] = newRequest;
        emit WithdrawalRequested(requestId, _owner, amountOfETH);
        return requestId;
    }

    function getClaimableEther(uint256 _requestId) external {
        if (_requestId == 0 || _requestId > getLastRequestId())
            revert InvalidRequestId(_requestId);

        if (_requestId > getLastFinalizedRequestId())
            revert RequestNotFoundOrNotFinalized(_requestId);

        WithdrawalRequest storage request = _getQueue()[_requestId];
        if (request.owner != msg.sender)
            revert NotOwner(msg.sender, request.owner);
        if (request.claimed) revert RequestAlreadyClaimed(_requestId);

        request.claimed = true;
        pool.ethToMeetWithdraw -= request.amount;
        _sendValue(_requestId, request.owner, request.amount);
    }

    /*
     * 打钱给提款人
     **/
    function _sendValue(
        uint256 _requestId,
        address recipient,
        uint256 amountOfETH
    ) internal {
        (bool success, ) = recipient.call{value: amountOfETH}("");
        if (!success) revert CantSendValueRecipientMayHaveReverted();
        emit WithdrawalClaimed(_requestId, recipient, amountOfETH);
    }

    function requestWithdrawal(uint256 amountOfETH)
        external
        payable
        returns (uint256 requestId)
    {
        if (amountOfETH > _getUserBalance(msg.sender)) {
            revert NotEnoughEther();
        }

        uint256 amountOfShares = _getSharesByETHAmount(amountOfETH);
        shares[msg.sender] -= amountOfShares;
        totalShares -= amountOfShares;
        pool.totalRedeemed += amountOfETH;

        if (_getPoolAvailableFunds() >= amountOfETH) {
            // 钱足够直接打给取款人,钱不够则放到提款队列中
            // 打款(一定要先减掉用户份额后再打款)
            _sendValue(0, msg.sender, amountOfETH);
            return 0;
        }

        requestId = _enqueue(amountOfETH, msg.sender);
        return requestId;
    }

    function getLastRequestId() public view returns (uint256) {
        return LAST_REQUEST_ID_POSITION;
    }

    function _setLastRequestId(uint256 _lastRequestId) internal {
        LAST_REQUEST_ID_POSITION = _lastRequestId;
    }

    function getLastFinalizedRequestId() public view returns (uint256) {
        return LAST_FINALIZED_REQUEST_ID_POSITION;
    }

    function _setLastFinalizedRequestId(uint256 _lastFinalizedRequestId)
        internal
    {
        LAST_FINALIZED_REQUEST_ID_POSITION = _lastFinalizedRequestId;
    }
}
