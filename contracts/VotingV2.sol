// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IStakingPool {
    function getUserShares(address account) external view returns (uint256);
    function getTotalShares() external view returns (uint256);
}

contract VotingV2 {
    using SafeMath for uint256;
    // using SafeMath64 for uint256;

    bytes32 public constant CREATE_VOTES_ROLE = keccak256("CREATE_VOTES_ROLE");
    bytes32 public constant MODIFY_SUPPORT_ROLE = keccak256("MODIFY_SUPPORT_ROLE");
    bytes32 public constant MODIFY_QUORUM_ROLE = keccak256("MODIFY_QUORUM_ROLE");
    bytes32 public constant UNSAFELY_MODIFY_VOTE_TIME_ROLE = keccak256("UNSAFELY_MODIFY_VOTE_TIME_ROLE");

    uint256 public constant PCT_BASE = 10 ** 18; // 0% = 0; 1% = 10^16; 100% = 10^18

    string private constant ERROR_NO_VOTE = "VOTING_NO_VOTE";
    string private constant ERROR_INIT_PCTS = "VOTING_INIT_PCTS";
    string private constant ERROR_CHANGE_SUPPORT_PCTS = "VOTING_CHANGE_SUPPORT_PCTS";
    string private constant ERROR_CHANGE_QUORUM_PCTS = "VOTING_CHANGE_QUORUM_PCTS";
    string private constant ERROR_INIT_SUPPORT_TOO_BIG = "VOTING_INIT_SUPPORT_TOO_BIG";
    string private constant ERROR_CHANGE_SUPPORT_TOO_BIG = "VOTING_CHANGE_SUPP_TOO_BIG";
    string private constant ERROR_CAN_NOT_VOTE = "VOTING_CAN_NOT_VOTE";
    string private constant ERROR_CAN_NOT_EXECUTE = "VOTING_CAN_NOT_EXECUTE";
    string private constant ERROR_CAN_NOT_FORWARD = "VOTING_CAN_NOT_FORWARD";
    string private constant ERROR_NO_VOTING_POWER = "VOTING_NO_VOTING_POWER";
    string private constant ERROR_CHANGE_VOTE_TIME = "VOTING_VOTE_TIME_TOO_SMALL";
    string private constant ERROR_CHANGE_OBJECTION_TIME = "VOTING_OBJ_TIME_TOO_BIG";
    string private constant ERROR_INIT_OBJ_TIME_TOO_BIG = "VOTING_INIT_OBJ_TIME_TOO_BIG";

    enum VoterState { Absent, Yea, Nay }

    enum VotePhase { Main, Objection, Closed }

    struct Vote {
        bool executed;
        uint256 startDate; // 开始日期
        uint256 snapshotBlock; // 快照区块
        uint256 supportRequiredPct; // 所需支持比例
        uint256 minAcceptQuorumPct; // 最小接受法定人数比例
        uint256 yea; // 赞成票数
        uint256 nay; // 反对票数
        uint256 votingPower; // 投票权利
        bytes executionScript; // 执行脚本
        address shareAddress; // 拿用户份额的地址
        address proxyAddress; // 代理地址
        address proxyAdminAddress; // 代理管理员地址
        address implementationAddress; // 新合约的地址
        mapping (address => VoterState) voters;
    }

    uint256 public supportRequiredPct;
    uint256 public minAcceptQuorumPct;
    uint256 public voteTime;

    // We are mimicing an array, we use a mapping instead to make app upgrade more graceful
    mapping (uint256 => Vote) internal votes;
    uint256 public votesLength;
    uint256 public objectionPhaseTime;

    event StartVote(uint256 indexed voteId, address indexed creator, string metadata);
    event CastVote(uint256 indexed voteId, address indexed voter, bool support, uint256 stake);
    event CastObjection(uint256 indexed voteId, address indexed voter, uint256 stake);
    event ExecuteVote(uint256 indexed voteId);
    event ChangeSupportRequired(uint256 supportRequiredPct);
    event ChangeMinQuorum(uint256 minAcceptQuorumPct);
    event ChangeVoteTime(uint256 voteTime);
    event ChangeObjectionPhaseTime(uint256 objectionPhaseTime);

    modifier voteExists(uint256 _voteId) {
        require(_voteId < votesLength, ERROR_NO_VOTE);
        _;
    }

    /**
    * @notice Initialize Voting app with `_token.symbol(): string` for governance, minimum support of `@formatPct(_supportRequiredPct)`%, minimum acceptance quorum of `@formatPct(_minAcceptQuorumPct)`%, and a voting duration of `@transformTime(_voteTime)`
    * @param _supportRequiredPct Percentage of yeas in casted votes for a vote to succeed (expressed as a percentage of 10^18; eg. 10^16 = 1%, 10^18 = 100%)
    * @param _minAcceptQuorumPct Percentage of yeas in total possible votes for a vote to succeed (expressed as a percentage of 10^18; eg. 10^16 = 1%, 10^18 = 100%)
    * @param _voteTime Total duration of voting in seconds.
    * @param _objectionPhaseTime The duration of the objection vote phase, i.e. seconds that a vote will be open after the main vote phase ends for token holders to object to the outcome. Main phase duration is calculated as `voteTime - objectionPhaseTime`.
    */
    constructor(uint256 _supportRequiredPct, uint256 _minAcceptQuorumPct, uint256 _voteTime, uint256 _objectionPhaseTime) {
        require(_minAcceptQuorumPct <= _supportRequiredPct, ERROR_INIT_PCTS);
        require(_supportRequiredPct < PCT_BASE, ERROR_INIT_SUPPORT_TOO_BIG);
        require(_voteTime > _objectionPhaseTime, ERROR_INIT_OBJ_TIME_TOO_BIG);

        supportRequiredPct = _supportRequiredPct;
        minAcceptQuorumPct = _minAcceptQuorumPct;
        voteTime = _voteTime;
        objectionPhaseTime = _objectionPhaseTime;
    }

    /**
    * @notice Change required support to `@formatPct(_supportRequiredPct)`%
    * @param _supportRequiredPct New required support
    */
    function changeSupportRequiredPct(uint256 _supportRequiredPct)
        external
    {
        require(minAcceptQuorumPct <= _supportRequiredPct, ERROR_CHANGE_SUPPORT_PCTS);
        require(_supportRequiredPct < PCT_BASE, ERROR_CHANGE_SUPPORT_TOO_BIG);
        supportRequiredPct = _supportRequiredPct;

        emit ChangeSupportRequired(_supportRequiredPct);
    }

    /**
    * @notice Change minimum acceptance quorum to `@formatPct(_minAcceptQuorumPct)`%
    * @param _minAcceptQuorumPct New acceptance quorum
    */
    function changeMinAcceptQuorumPct(uint256 _minAcceptQuorumPct)
        external
    {
        require(_minAcceptQuorumPct <= supportRequiredPct, ERROR_CHANGE_QUORUM_PCTS);
        minAcceptQuorumPct = _minAcceptQuorumPct;

        emit ChangeMinQuorum(_minAcceptQuorumPct);
    }

    /**
    * @notice Change vote time to `_voteTime` sec. The change affects all existing unexecuted votes, so be really careful with it
    * @param _voteTime New vote time
    */
    function unsafelyChangeVoteTime(uint256 _voteTime)
        external
    {
        require(_voteTime > objectionPhaseTime, ERROR_CHANGE_VOTE_TIME);
        voteTime = _voteTime;

        emit ChangeVoteTime(_voteTime);
    }

    /**
    * @notice Change the objection phase duration to `_objectionPhaseTime` sec. The change affects all existing unexecuted votes, so be really careful with it
    * @param _objectionPhaseTime New objection time
    */
    function unsafelyChangeObjectionPhaseTime(uint256 _objectionPhaseTime)
        external
    {
        require(voteTime > _objectionPhaseTime, ERROR_CHANGE_OBJECTION_TIME);
        objectionPhaseTime = _objectionPhaseTime;

        emit ChangeObjectionPhaseTime(_objectionPhaseTime);
    }

    /**
    * @notice Create a new vote about "`_metadata`"
    * @param _metadata Vote metadata
    * @return voteId Id for newly created vote
    */
    function newVote(address shareAddress, address proxyAddress, address proxyAdminAddress, address implementationAddress, string memory _metadata) external returns (uint256 voteId) {
        return _newVote(shareAddress, proxyAddress, proxyAdminAddress, implementationAddress, _metadata, true);
    }

    /**
    * @notice Create a new vote about "`_metadata`"
    * @dev  _executesIfDecided was deprecated to introduce a proper lock period between decision and execution.
    * @param _metadata Vote metadata
    * @param _castVote Whether to also cast newly created vote
    * @return voteId id for newly created vote
    */
    function newVote(address shareAddress, address proxyAddress, address proxyAdminAddress, address implementationAddress, string memory _metadata, bool _castVote)
        external
        returns (uint256 voteId)
    {
        return _newVote(shareAddress, proxyAddress, proxyAdminAddress, implementationAddress, _metadata, _castVote);
    }

    /**
    * @notice Vote `_supports ? 'yes' : 'no'` in vote #`_voteId`. During objection phase one can only vote 'no'
    * @dev Initialization check is implicitly provided by `voteExists()` as new votes can only be
    *      created via `newVote(),` which requires initialization
    * @dev  _executesIfDecided was deprecated to introduce a proper lock period between decision and execution.
    * @param _voteId Id for vote
    */
    function vote(uint256 _voteId, bool _support) external voteExists(_voteId) {
        require(_canVote(_voteId, msg.sender), ERROR_CAN_NOT_VOTE);
        require(!_support || _getVotePhase(votes[_voteId]) == VotePhase.Main, ERROR_CAN_NOT_VOTE);
        _vote(_voteId, _support, msg.sender);
    }

    /**
    * @notice Execute vote #`_voteId`
    * @dev Initialization check is implicitly provided by `voteExists()` as new votes can only be
    *      created via `newVote(),` which requires initialization
    * @param _voteId Id for vote
    */
    function executeVote(uint256 _voteId) external voteExists(_voteId) {
        _executeVote(_voteId);
    }

    // Forwarding fns

    /**
    * @notice Tells whether the Voting app is a forwarder or not
    * @dev IForwarder interface conformance
    * @return Always true
    */
    function isForwarder() external pure returns (bool) {
        return true;
    }

    /**
    * @notice Creates a vote to execute the desired action, and casts a support vote if possible
    * @dev IForwarder interface conformance
    * @param _evmScript Start vote with script
    */
    function forward(bytes calldata _evmScript) public view {
        require(canForward(msg.sender, _evmScript), ERROR_CAN_NOT_FORWARD);
        // _newVote(_evmScript, "", true);
    }

    /**
    * @notice Tells whether `_sender` can forward actions or not
    * @dev IForwarder interface conformance
    * @param _sender Address of the account intending to forward an action
    * @return True if the given address can create votes, false otherwise
    */
    function canForward(address _sender, bytes calldata) public pure returns (bool) {
        // Note that `canPerform()` implicitly does an initialization check itself
        return true;
    }

    // Getter fns

    /**
    * @notice Tells whether a vote #`_voteId` can be executed or not
    * @dev Initialization check is implicitly provided by `voteExists()` as new votes can only be
    *      created via `newVote(),` which requires initialization
    * @param _voteId Vote identifier
    * @return True if the given vote can be executed, false otherwise
    */
    function canExecute(uint256 _voteId) public view voteExists(_voteId) returns (bool) {
        return _canExecute(_voteId);
    }

    /**
    * @notice Tells whether `_voter` can participate in the main or objection phase of the vote #`_voteId`
    * @dev Initialization check is implicitly provided by `voteExists()` as new votes can only be
    *      created via `newVote(),` which requires initialization
    * @param _voteId Vote identifier
    * @param _voter address of the voter to check
    * @return True if the given voter can participate in the main phase of a certain vote, false otherwise
    */
    function canVote(uint256 _voteId, address _voter) external view voteExists(_voteId) returns (bool) {
        return _canVote(_voteId, _voter);
    }

    /**
    * @notice Tells the current phase of the vote #`_voteId`
    * @dev Initialization check is implicitly provided by `voteExists()` as new votes can only be
    *      created via `newVote(),` which requires initialization
    * @param _voteId Vote identifier
    * @return VotePhase.Main if one can vote yes or no and VotePhase.Objection if one can vote only no and VotingPhase.Closed if no votes are accepted
    */
    function getVotePhase(uint256 _voteId) external view voteExists(_voteId) returns (VotePhase) {
        return _getVotePhase(votes[_voteId]);
    }

    /**
    * @dev Return all information for a vote by its ID
    * @param _voteId Vote identifier
    */
    function getVote(uint256 _voteId)
        public
        view
        voteExists(_voteId)
        returns (
            bool open,
            bool executed,
            uint256 startDate,
            uint256 snapshotBlock,
            uint256 supportRequired,
            uint256 minAcceptQuorum,
            uint256 yea,
            uint256 nay,
            uint256 votingPower,
            VotePhase phase
        )
    {
        Vote storage vote_ = votes[_voteId];

        open = _isVoteOpen(vote_);
        executed = vote_.executed;
        startDate = vote_.startDate;
        snapshotBlock = vote_.snapshotBlock;
        supportRequired = vote_.supportRequiredPct;
        minAcceptQuorum = vote_.minAcceptQuorumPct;
        yea = vote_.yea;
        nay = vote_.nay;
        votingPower = vote_.votingPower;
        // script = vote_.executionScript;
        phase = _getVotePhase(vote_);
    }

    /**
    * @dev Return the state of a voter for a given vote by its ID
    * @param _voteId Vote identifier
    * @param _voter address of the voter
    * @return VoterState of the requested voter for a certain vote
    */
    function getVoterState(uint256 _voteId, address _voter) public view voteExists(_voteId) returns (VoterState) {
        return votes[_voteId].voters[_voter];
    }

    // Internal fns

    /**
    * @dev Internal function to create a new vote
    * @return voteId id for newly created vote
    */
    function _newVote(address shareAddress, address proxyAddress, address proxyAdminAddress, address implementationAddress, string memory _metadata, bool _castVote) internal returns (uint256 voteId) {
        // TODO: getBlockNumber64()
        // uint256 snapshotBlock = getBlockNumber64() - 1; // avoid double voting in this very block
        uint256 votingPower = IStakingPool(shareAddress).getTotalShares(); // TODO: 这里是怎么知道Token的总供应量的
        require(votingPower > 0, ERROR_NO_VOTING_POWER);

        voteId = votesLength++;

        Vote storage vote_ = votes[voteId];
        vote_.startDate = getTimestamp64();
        // vote_.snapshotBlock = snapshotBlock;
        vote_.supportRequiredPct = supportRequiredPct;
        vote_.minAcceptQuorumPct = minAcceptQuorumPct;
        vote_.votingPower = votingPower;
        // vote_.executionScript = _executionScript;
        vote_.shareAddress = shareAddress;
        vote_.proxyAddress = proxyAddress;
        vote_.proxyAdminAddress = proxyAdminAddress;
        vote_.implementationAddress = implementationAddress;

        emit StartVote(voteId, msg.sender, _metadata);

        if (_castVote && _canVote(voteId, msg.sender)) {
            _vote(voteId, true, msg.sender);
        }
    }

    /**
    * @dev Internal function to cast a vote or object to.
      @dev It assumes that voter can support or object to the vote
    */
    function _vote(uint256 _voteId, bool _supports, address _voter) internal {
        Vote storage vote_ = votes[_voteId];

        // This could re-enter, though we can assume the governance token is not malicious
        uint256 voterStake = IStakingPool(vote_.shareAddress).getUserShares(_voter);
        VoterState state = vote_.voters[_voter];

        // If voter had previously voted, decrease count
        if (state == VoterState.Yea) {
            vote_.yea = vote_.yea.sub(voterStake); 
        } else if (state == VoterState.Nay) {
            vote_.nay = vote_.nay.sub(voterStake);
        }

        if (_supports) {
            vote_.yea = vote_.yea.add(voterStake);
            vote_.voters[_voter] = VoterState.Yea;
        } else {
            vote_.nay = vote_.nay.add(voterStake);
            vote_.voters[_voter] = VoterState.Nay;
        }

        emit CastVote(_voteId, _voter, _supports, voterStake);

        if (_getVotePhase(vote_) == VotePhase.Objection) {
            emit CastObjection(_voteId, _voter, voterStake);
        }
    }

    /**
    * @dev Internal function to execute a vote. It assumes the queried vote exists.
    */
    function _executeVote(uint256 _voteId) internal {
        require(_canExecute(_voteId), ERROR_CAN_NOT_EXECUTE);
        _unsafeExecuteVote(_voteId);
    }

    /**
    * @dev Unsafe version of _executeVote that assumes you have already checked if the vote can be executed and exists
    */
    function _unsafeExecuteVote(uint256 _voteId) internal {
        Vote storage vote_ = votes[_voteId];

        vote_.executed = true;

        // bytes memory input = new bytes(0); // TODO: Consider input for voting scripts
        // runScript(vote_.executionScript, input, new address[](0));

        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(vote_.proxyAddress);

        // Upgrade the proxy to the new implementation
        ProxyAdmin(vote_.proxyAdminAddress).upgradeAndCall(proxy, vote_.implementationAddress, bytes(""));
        emit ExecuteVote(_voteId);
    }

    /**
    * @dev Internal function to check if a vote can be executed. It assumes the queried vote exists.
    * @return True if the given vote can be executed, false otherwise
    */
    function _canExecute(uint256 _voteId) internal view returns (bool) {
        Vote storage vote_ = votes[_voteId];

        if (vote_.executed) {
            return false;
        }

        // Vote ended?
        if (_isVoteOpen(vote_)) {
            return false;
        }

        // Has enough support?
        uint256 voteYea = vote_.yea;
        uint256 totalVotes = voteYea.add(vote_.nay);
        if (!_isValuePct(voteYea, totalVotes, vote_.supportRequiredPct)) { // 投票人数中投赞成票的百分比要大于supportRequiredPct
            return false;
        }
        // Has min quorum?
        if (!_isValuePct(voteYea, vote_.votingPower, vote_.minAcceptQuorumPct)) { // 投赞成票的权重需要大于总权重的百分比
            return false;
        }

        return true;
    }

    /**
    * @dev Internal function to check if a voter can participate on a vote. It assumes the queried vote exists.
    * @return True if the given voter can participate a certain vote, false otherwise
    */
    function _canVote(uint256 _voteId, address _voter) internal view returns (bool) {
        Vote storage vote_ = votes[_voteId];
        return _isVoteOpen(vote_) && IStakingPool(vote_.shareAddress).getUserShares(_voter) > 0;
    }

    /**
    * @dev Internal function to get the current phase of the vote. It assumes the queried vote exists.
    * @return VotePhase.Main if one can vote 'yes' or 'no', VotePhase.Objection if one can vote only 'no' or VotePhase.Closed if no votes are accepted
    */
    function _getVotePhase(Vote storage vote_) internal view returns (VotePhase) {
        uint256 timestamp = getTimestamp64();
        uint256 voteTimeEnd = vote_.startDate.add(voteTime);
        if (timestamp < voteTimeEnd.sub(objectionPhaseTime)) {
            return VotePhase.Main;
        }
        if (timestamp < voteTimeEnd) {
            return VotePhase.Objection;
        }
        return VotePhase.Closed;
    }

    /**
    * @dev Internal function to check if a vote is still open for both support and objection
    * @return True if less than voteTime has passed since the vote start
    */
    function _isVoteOpen(Vote storage vote_) internal view returns (bool) {
        return getTimestamp64() < vote_.startDate.add(voteTime) && !vote_.executed;
    }

    /**
    * @dev Calculates whether `_value` is more than a percentage `_pct` of `_total`
    */
    function _isValuePct(uint256 _value, uint256 _total, uint256 _pct) internal pure returns (bool) {
        if (_total == 0) {
            return false;
        }

        uint256 computedPct = _value.mul(PCT_BASE) / _total;
        return computedPct > _pct;
    }

    function getTimestamp64() internal view returns (uint256) {
        return uint256(block.timestamp);
    }
}
