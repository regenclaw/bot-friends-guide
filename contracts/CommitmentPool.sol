// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Clawmmons Commitment Pool
 * @notice Agents stake ETH on deliverables. Deliver → refund. Miss deadline → stake to treasury.
 * @dev Verification supports both single-verifier and N-of-M agent voting modes.
 */
contract CommitmentPool is ReentrancyGuard, Ownable, Pausable {

    enum Status { Active, Verified, Slashed }

    struct Commitment {
        address staker;
        uint256 amount;
        string deliverable;
        uint256 deadline;
        address verifier;       // Single verifier (address(0) = use agent voting)
        Status status;
        uint256 createdAt;
        uint256 verifyCount;    // Number of agent votes received
    }

    // --- State ---
    address public treasury;
    uint256 public nextId;
    uint256 public totalStaked;
    uint256 public totalSlashed;
    uint256 public totalRefunded;

    // Agent voting config
    address[] public agents;
    mapping(address => bool) public isAgent;
    uint256 public quorum;  // How many agents needed to verify (e.g., 3 of 5)

    mapping(uint256 => Commitment) public commitments;
    mapping(uint256 => mapping(address => bool)) public hasVoted; // commitmentId => agent => voted

    // --- Events ---
    event CommitmentCreated(uint256 indexed id, address indexed staker, uint256 amount, string deliverable, uint256 deadline, address verifier);
    event CommitmentVerified(uint256 indexed id, address indexed staker, uint256 amount);
    event CommitmentSlashed(uint256 indexed id, address indexed staker, uint256 amount, address treasury);
    event CommitmentExtended(uint256 indexed id, uint256 oldDeadline, uint256 newDeadline);
    event VoteCast(uint256 indexed id, address indexed agent, uint256 currentVotes, uint256 quorum);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    constructor(address _treasury, address[] memory _agents, uint256 _quorum) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        require(_quorum > 0 && _quorum <= _agents.length, "Invalid quorum");

        treasury = _treasury;
        quorum = _quorum;

        for (uint256 i = 0; i < _agents.length; i++) {
            require(_agents[i] != address(0), "Invalid agent");
            require(!isAgent[_agents[i]], "Duplicate agent");
            agents.push(_agents[i]);
            isAgent[_agents[i]] = true;
        }
    }

    // --- Core ---

    /**
     * @notice Stake ETH on a deliverable
     * @param deliverable Description of what you'll deliver
     * @param deadline Unix timestamp — must deliver by this time
     * @param verifier Single verifier address, or address(0) to use agent voting
     */
    function commit(
        string calldata deliverable,
        uint256 deadline,
        address verifier
    ) external payable whenNotPaused returns (uint256) {
        require(msg.value > 0, "Must stake ETH");
        require(deadline > block.timestamp, "Deadline must be future");
        require(verifier != msg.sender, "Cannot self-verify");

        uint256 id = nextId++;
        commitments[id] = Commitment({
            staker: msg.sender,
            amount: msg.value,
            deliverable: deliverable,
            deadline: deadline,
            verifier: verifier,
            status: Status.Active,
            createdAt: block.timestamp,
            verifyCount: 0
        });

        totalStaked += msg.value;

        emit CommitmentCreated(id, msg.sender, msg.value, deliverable, deadline, verifier);
        return id;
    }

    /**
     * @notice Verify delivery (single verifier mode)
     * @dev Only callable by the commitment's designated verifier
     */
    function verify(uint256 id) external nonReentrant {
        Commitment storage c = commitments[id];
        require(c.status == Status.Active, "Not active");
        require(c.verifier != address(0), "Use voteVerify for agent voting");
        require(msg.sender == c.verifier, "Not verifier");

        _refund(id);
    }

    /**
     * @notice Vote to verify delivery (agent voting mode)
     * @dev Any registered agent can vote. Refunds when quorum is reached.
     */
    function voteVerify(uint256 id) external nonReentrant {
        Commitment storage c = commitments[id];
        require(c.status == Status.Active, "Not active");
        require(c.verifier == address(0), "Use verify for single verifier");
        require(isAgent[msg.sender], "Not an agent");
        require(!hasVoted[id][msg.sender], "Already voted");

        hasVoted[id][msg.sender] = true;
        c.verifyCount++;

        emit VoteCast(id, msg.sender, c.verifyCount, quorum);

        if (c.verifyCount >= quorum) {
            _refund(id);
        }
    }

    /**
     * @notice Slash a commitment after deadline — permissionless
     * @dev Anyone can call this after the deadline has passed
     */
    function slash(uint256 id) external nonReentrant {
        Commitment storage c = commitments[id];
        require(c.status == Status.Active, "Not active");
        require(block.timestamp > c.deadline, "Deadline not passed");

        c.status = Status.Slashed;
        totalSlashed += c.amount;

        (bool sent,) = treasury.call{value: c.amount}("");
        require(sent, "Transfer failed");

        emit CommitmentSlashed(id, c.staker, c.amount, treasury);
    }

    /**
     * @notice Extend deadline — only by verifier or owner
     */
    function extend(uint256 id, uint256 newDeadline) external {
        Commitment storage c = commitments[id];
        require(c.status == Status.Active, "Not active");
        require(newDeadline > c.deadline, "Must extend forward");
        require(
            msg.sender == c.verifier || msg.sender == owner(),
            "Not authorized"
        );

        uint256 oldDeadline = c.deadline;
        c.deadline = newDeadline;

        emit CommitmentExtended(id, oldDeadline, newDeadline);
    }

    // --- Internal ---

    function _refund(uint256 id) internal {
        Commitment storage c = commitments[id];
        c.status = Status.Verified;
        totalRefunded += c.amount;

        (bool sent,) = c.staker.call{value: c.amount}("");
        require(sent, "Refund failed");

        emit CommitmentVerified(id, c.staker, c.amount);
    }

    // --- Admin (Owner = Clawmmons Safe) ---

    function addAgent(address agent) external onlyOwner {
        require(agent != address(0), "Invalid agent");
        require(!isAgent[agent], "Already agent");
        agents.push(agent);
        isAgent[agent] = true;
        emit AgentAdded(agent);
    }

    function removeAgent(address agent) external onlyOwner {
        require(isAgent[agent], "Not agent");
        isAgent[agent] = false;
        // Remove from array
        for (uint256 i = 0; i < agents.length; i++) {
            if (agents[i] == agent) {
                agents[i] = agents[agents.length - 1];
                agents.pop();
                break;
            }
        }
        // Adjust quorum if needed
        if (quorum > agents.length) {
            quorum = agents.length;
        }
        emit AgentRemoved(agent);
    }

    function setQuorum(uint256 _quorum) external onlyOwner {
        require(_quorum > 0 && _quorum <= agents.length, "Invalid quorum");
        uint256 old = quorum;
        quorum = _quorum;
        emit QuorumUpdated(old, _quorum);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // --- Views ---

    function getCommitment(uint256 id) external view returns (Commitment memory) {
        return commitments[id];
    }

    function getAgents() external view returns (address[] memory) {
        return agents;
    }

    function agentCount() external view returns (uint256) {
        return agents.length;
    }
}
