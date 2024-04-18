// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;


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

    struct User {
        uint256 deposited;
        uint256 rewards;
        uint256 redeemed;
        uint256 lossed; // 暂时没用
        uint256 timestamp;
    }
    mapping (address => User) public users;
    address[] private keys; // 保存users的key,方便遍历users

    struct Pool {
        uint256 totalDeposited; // 总共充值了多少
        uint256 totalRedeemed; // 总共赎回了多少
        uint256 depositedValidators; // 充值的验证者数量
        uint256 totalRewards; // 总收益
        uint256 totalLossed;
        uint256 availableFunds; // 可用资金
        uint256 lastRewardTime; // 上一次获取收益的时间
    }
    Pool public pool; // 池子

    uint256 private constant DEPOSIT_SIZE = 32 ether;

    // MainNet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    // Holesky: 0x4242424242424242424242424242424242424242
    address public constant DEPOSIT_CONTRACT_ADDRESS = 0x4242424242424242424242424242424242424242;
    IDepositContract DEPOSIT_CONTRACT = IDepositContract(DEPOSIT_CONTRACT_ADDRESS);

    address VAULT_CONTRACT_ADDRESS;

    // The amount of ETH withdrawn from Valut to current contract
    event RewardsReceived(uint256 amount, uint256 timestamp);
    
    event Deposited(address indexed sender, uint256 amount, uint256 timestamp);
    event BeaconChainDepositEvent(
        bytes pubkey,
        bytes withdrawalCredentials,
        bytes signature,
        uint256 amount,
        uint256 timestamp
    );
    event RewardDistributed(
        address indexed sender, 
        uint256 amount, 
        uint256 timestamp
    );
    error NotEnoughEtherToDeposit();

    constructor() {
        owner = msg.sender;
        pool.lastRewardTime = block.timestamp;
    }

    /**
     * @notice 用户向池子发送资金进行质押
     */
    function deposit() external payable returns (uint256)  {
        require(msg.value > 0, "ZERO_DEPOSIT");
        return _deposit(msg.sender, msg.value);
    }
    
    function _deposit(address account, uint256 amount) internal returns (uint256)  {
        _createStatement(account, IOSubType.UserDeposit, amount);
        
        emit Deposited(account, amount, block.timestamp);
        return amount;
    }

    /**
     * @notice 激活验证者
     */
    function activateValidator(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials, 
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable {
        require(msg.sender == owner, "AUTH_DENIED");
        if (pool.availableFunds < 32 * WEI_PER_ETHER) revert NotEnoughEtherToDeposit();
        
       // 充值
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

        pool.depositedValidators += 1; // 增加Validator数量
       _createStatement(address(0), IOSubType.BeaconDeposit, DEPOSIT_SIZE);
    }

    function receiveVaultFunds() external payable {
        require(msg.sender == VAULT_CONTRACT_ADDRESS, "Not Vault");
        emit RewardsReceived(msg.value, block.timestamp);
    }

    function submitReport(address vaultAddress, uint256 amount) external {
        require(msg.sender == owner, "Permission Denied");
        // collect funds from vault
        VAULT_CONTRACT_ADDRESS = vaultAddress;
        IVault VAULT_CONTRACT = IVault(vaultAddress);
        VAULT_CONTRACT.withdrawValut(amount);

        if (amount < 16 * WEI_PER_ETHER) { // rewards
            _createStatement(address(0), IOSubType.Reward, amount);
            distributeRewards(amount);
        } else if (amount >= 32 * WEI_PER_ETHER) { // rewards + refund
            _createStatement(address(0), IOSubType.Reward, amount - 32 * WEI_PER_ETHER);
            distributeRewards(amount - 32 * WEI_PER_ETHER);
            _createStatement(address(0), IOSubType.Refund, 32 * WEI_PER_ETHER);
        } else{ // refund
            _createStatement(address(0),  IOSubType.Refund, amount);
        }

        uint256 ethToLock = _finalize();
        _createStatement(address(0), IOSubType.Redeeming, ethToLock);
    }

    /**
    * 给用户单独记账手续费太高
    */
    function distributeRewards(uint256 rewards) internal {
        for(uint i = 0; i < keys.length; i++) {
            address account = keys[i];
            uint256 amount = ((users[account].deposited - users[account].redeemed) * rewards) / (pool.totalDeposited - pool.totalRedeemed); 
            users[account].rewards += amount;
            emit RewardDistributed(account, amount, block.timestamp);
        }
    }

    function getUserDeposits() external view returns (uint256) {
        return users[msg.sender].deposited;
    }

    function getContractBalance() external  view returns (uint256) {
        return address(this).balance;
    }

    function _getUserBalance() internal view returns (uint256) {
        return users[msg.sender].deposited + users[msg.sender].rewards - users[msg.sender].redeemed;
    }

    function getUserBalance() external view returns (uint256) {
        return _getUserBalance();
    }

    enum IOSubType {
        UserDeposit,
        UserRedeeming,
        BeaconDeposit,
        Refund,
        Reward,
        Redeeming
    }
    function _createStatement(address account, IOSubType subType, uint256 amount) internal {
        if (subType == IOSubType.UserDeposit) {
            if (users[account].timestamp == 0) {
                keys.push(account);
                users[account].timestamp = block.timestamp;
            }
            users[account].deposited += amount;
            pool.totalDeposited += amount;
            pool.availableFunds += amount;
        }
        if (subType == IOSubType.Refund) {
            // TODO:
            pool.availableFunds += amount;
        }
        if (subType == IOSubType.Reward) {
            pool.totalRewards += amount;
            pool.availableFunds += amount;
            pool.lastRewardTime = block.timestamp;
        }
        if (subType == IOSubType.BeaconDeposit) {
            pool.availableFunds -= amount;
        }
        if (subType == IOSubType.UserRedeeming) {
            users[account].redeemed += amount;
        }
        if (subType == IOSubType.Redeeming) {
            pool.totalRedeemed += amount;
            pool.availableFunds -= amount;
        }
    }

    /******** WithdrawQueue ********/
    /// @dev queue for withdrawal requests, indexes (requestId) start from 1
    bytes32 internal constant QUEUE_POSITION = keccak256("WithdrawalQueue.queue");
    /// @dev last index in request queue
    uint256 private LAST_REQUEST_ID_POSITION;
    /// @dev last index of finalized request in the queue
    uint256 private LAST_FINALIZED_REQUEST_ID_POSITION;

    uint256 public constant WEI_PER_ETHER = 1e18;

    error NotEnoughEther();
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

    function _getQueue() internal pure returns (mapping(uint256 => WithdrawalRequest) storage queue) {
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

    function _getStatus(uint256 _requestId) internal view returns (WithdrawalRequestStatus memory status) {
        if (_requestId == 0 || _requestId > getLastRequestId()) revert InvalidRequestId(_requestId);
        WithdrawalRequest memory request = _getQueue()[_requestId];
        status = WithdrawalRequestStatus(
            request.amount,
            request.owner,
            request.timestamp,
            _requestId <= getLastFinalizedRequestId(),
            request.claimed
        );
    }

    function _finalize() internal returns (uint256 ethToLock){
        uint256 _batches = 100; // 每次最大处理100笔提款
        uint256 currentBatchIndex = 1;
        uint256 lastFinalizedRequestId = getLastFinalizedRequestId();
        while (currentBatchIndex < _batches + 1) {
            uint256 requestId = lastFinalizedRequestId + currentBatchIndex;
            if (requestId > getLastRequestId()) {
                break;
            }
            WithdrawalRequest memory request = _getQueue()[requestId];
            // if (request.timestamp < block.timestamp + 24 * 60 * 60) { // 发起提款24h后的请求才能被确认
            //     break;
            // }
            if (ethToLock + request.amount > pool.availableFunds) {
                emit NotEnoughEtherToRedeem(requestId, request.owner, request.amount, block.timestamp);
                break;
            }
            ethToLock += request.amount;
            _setLastFinalizedRequestId(requestId);
            emit WithdrawalsFinalized(requestId - 1, requestId, request.amount, block.timestamp);

            unchecked{ ++currentBatchIndex; }
        }
    }

    function _enqueue(uint256 amount, address _owner) internal returns (uint256 requestId) {
        uint256 lastRequestId = getLastRequestId();
        requestId = lastRequestId + 1;
        _setLastRequestId(requestId);

        WithdrawalRequest memory newRequest =  WithdrawalRequest(
            amount,
            _owner,
            uint40(block.timestamp),
            false
        );

        _getQueue()[requestId] = newRequest;
        emit WithdrawalRequested(requestId, _owner, amount);

        _createStatement(_owner, IOSubType.UserRedeeming, amount);
        return requestId;
    }

    function getClaimableEther(uint256 _requestId) external {
        if (_requestId == 0 || _requestId > getLastRequestId()) revert InvalidRequestId(_requestId);

        if (_requestId > getLastFinalizedRequestId()) revert RequestNotFoundOrNotFinalized(_requestId);

        WithdrawalRequest storage request = _getQueue()[_requestId];
        if (request.owner != msg.sender) revert NotOwner(msg.sender, request.owner);
        if (request.claimed) revert RequestAlreadyClaimed(_requestId);

        request.claimed = true;
        _sendValue(_requestId, request.owner, request.amount);
    }

    /*
     * 打钱给提款人
     **/
    function _sendValue(uint256 _requestId, address recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert NotEnoughEther();

        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert CantSendValueRecipientMayHaveReverted();
        emit WithdrawalClaimed(_requestId, recipient, amount);
    }

    function requestWithdrawal(uint256 amount) external payable returns (uint256 requestId) {
        if (amount > _getUserBalance()) {
             revert NotEnoughEther();
        }

        if (pool.availableFunds >= amount) { // 钱足够直接打给取款人，钱不够则放到提款队列中
            _sendValue(0, msg.sender, amount);
            _createStatement(address(0), IOSubType.Redeeming, amount);
            _createStatement(msg.sender, IOSubType.UserRedeeming, amount);
            return 0;
        }                                                                                 

        requestId = _enqueue(amount, msg.sender);
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

    function _setLastFinalizedRequestId(uint256 _lastFinalizedRequestId) internal {
        LAST_FINALIZED_REQUEST_ID_POSITION = _lastFinalizedRequestId;
    }
}