// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Clawmmons Commitment Pool
 * @notice Agents stake ETH on deliverables. Deliver → refund. Miss deadline → stake to treasury.
 * @dev Simplified v2: single resolve() function with majority voting, permissionless claim() after deadline.
 */
contract CommitmentPool is ReentrancyGuard, Ownable, Pausable {
    enum Status { Active, Resolved }

    struct Commitment {
        address staker;
        uint256 amount;
        string deliverable;
        uint256 deadline;
        Status status;
        bool outcome;
        uint256 createdAt;
        uint256 resolvedAt;
        uint256 votesFor;
        uint256 votesAgainst;
    }

    address public treasury;
    uint256 public nextId;
    uint256 public totalStaked;
    uint256 public totalSlashed;
    uint256 public totalRefunded;

    address[] public validators;
    mapping(address => bool) public isValidator;
    mapping(uint256 => Commitment) public commitments;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event CommitmentCreated(uint256 indexed id, address indexed staker, uint256 amount, string deliverable, uint256 deadline);
    event Voted(uint256 indexed id, address indexed validator, bool delivered, uint256 votesFor, uint256 votesAgainst);
    event Resolved(uint256 indexed id, address indexed staker, uint256 amount, bool delivered);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    constructor(address _treasury, address[] memory _validators) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        require(_validators.length >= 3, "Need at least 3 validators");
        treasury = _treasury;
        for (uint256 i = 0; i < _validators.length; i++) {
            require(_validators[i] != address(0), "Invalid validator");
            require(!isValidator[_validators[i]], "Duplicate validator");
            validators.push(_validators[i]);
            isValidator[_validators[i]] = true;
        }
    }

    /**
     * @notice Stake ETH on a deliverable
     * @param deliverable Description of what you'll deliver
     * @param deadline Unix timestamp — must deliver by this time
     */
    function commit(string calldata deliverable, uint256 deadline) external payable whenNotPaused returns (uint256) {
        require(msg.value > 0, "Must stake ETH");
        require(deadline > block.timestamp, "Deadline must be future");
        uint256 id = nextId++;
        commitments[id] = Commitment({
            staker: msg.sender,
            amount: msg.value,
            deliverable: deliverable,
            deadline: deadline,
            status: Status.Active,
            outcome: false,
            createdAt: block.timestamp,
            resolvedAt: 0,
            votesFor: 0,
            votesAgainst: 0
        });
        totalStaked += msg.value;
        emit CommitmentCreated(id, msg.sender, msg.value, deliverable, deadline);
        return id;
    }

    /**
     * @notice Vote on whether a commitment was delivered
     * @param id Commitment ID
     * @param delivered true = delivered, false = not delivered
     * @dev Auto-resolves when majority is reached
     */
    function resolve(uint256 id, bool delivered) external nonReentrant {
        Commitment storage c = commitments[id];
        require(c.status == Status.Active, "Already resolved");
        require(isValidator[msg.sender], "Not a validator");
        require(!hasVoted[id][msg.sender], "Already voted");
        require(msg.sender != c.staker, "Staker cannot vote on own commitment");
        
        hasVoted[id][msg.sender] = true;
        if (delivered) { c.votesFor++; } else { c.votesAgainst++; }
        emit Voted(id, msg.sender, delivered, c.votesFor, c.votesAgainst);
        
        uint256 maj = (validators.length / 2) + 1;
        if (c.votesFor >= maj) {
            c.status = Status.Resolved;
            c.outcome = true;
            c.resolvedAt = block.timestamp;
            totalRefunded += c.amount;
            (bool sent,) = c.staker.call{value: c.amount}("");
            require(sent, "Refund failed");
            emit Resolved(id, c.staker, c.amount, true);
        } else if (c.votesAgainst >= maj) {
            c.status = Status.Resolved;
            c.outcome = false;
            c.resolvedAt = block.timestamp;
            totalSlashed += c.amount;
            (bool sent,) = treasury.call{value: c.amount}("");
            require(sent, "Transfer failed");
            emit Resolved(id, c.staker, c.amount, false);
        }
    }

    /**
     * @notice Claim unresolved commitment after deadline — permissionless
     * @dev Anyone can call this to sweep stake to treasury if validators haven't resolved
     */
    function claim(uint256 id) external nonReentrant {
        Commitment storage c = commitments[id];
        require(c.status == Status.Active, "Already resolved");
        require(block.timestamp > c.deadline, "Deadline not passed");
        c.status = Status.Resolved;
        c.outcome = false;
        c.resolvedAt = block.timestamp;
        totalSlashed += c.amount;
        (bool sent,) = treasury.call{value: c.amount}("");
        require(sent, "Transfer failed");
        emit Resolved(id, c.staker, c.amount, false);
    }

    // --- Admin (Owner = Clawmmons Safe) ---

    function addValidator(address validator) external onlyOwner {
        require(validator != address(0), "Invalid validator");
        require(!isValidator[validator], "Already validator");
        validators.push(validator);
        isValidator[validator] = true;
        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator) external onlyOwner {
        require(isValidator[validator], "Not validator");
        require(validators.length > 3, "Need at least 3 validators");
        isValidator[validator] = false;
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == validator) {
                validators[i] = validators[validators.length - 1];
                validators.pop();
                break;
            }
        }
        emit ValidatorRemoved(validator);
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

    function getValidators() external view returns (address[] memory) {
        return validators;
    }

    function validatorCount() external view returns (uint256) {
        return validators.length;
    }

    function majority() external view returns (uint256) {
        return (validators.length / 2) + 1;
    }
}
