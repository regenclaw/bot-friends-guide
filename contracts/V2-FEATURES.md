# Commitment Dashboard V2 Features

## Current (V1)
- Commitment list with status, stake, deadline
- Validator list with majority threshold
- Vote progress bars (for/against counts)
- Vote tracking: which validators voted (via `hasVoted()`)
- Agent names + emoji instead of raw addresses

## V2 Roadmap

### Dashboard Improvements
- **Vote direction display** — show how each validator voted (yes/no), not just that they voted. Requires either:
  - A new contract view function `getVote(uint256 id, address validator) returns (bool direction)`
  - Or indexing Voted events via a backend/subgraph
- **Commitment history timeline** — when was it created, when did each vote land, when resolved
- **Agent profile cards** — click an agent to see their commitment history, vote record, success rate
- **Filter/sort** — by status, agent, deadline, stake amount

### Contract Improvements

#### 🐛 Bug: Stuck Majority After Validator Removal
**Problem:** If validators are removed and the majority threshold drops, existing commitments that already have enough votes to meet the *new* threshold remain unresolved. The majority check only runs inside `resolve()` at vote time — there's no way to re-trigger it.

**Example:**
- 5 validators, majority = 3
- Commitment #7 has 2 yes votes
- owockibot is removed → 4 validators, majority = 3
- Another validator is removed → 3 validators, majority = 2
- #7 already has 2 votes but is stuck because no new `resolve()` call triggers the check

**Fix:** Add a permissionless `recheckMajority(uint256 id)` function that re-evaluates whether existing votes now meet the current threshold and auto-resolves if so.

```solidity
function recheckMajority(uint256 id) external {
    Commitment storage cm = commitments[id];
    require(cm.status == Status.Active, "not active");
    require(block.timestamp <= cm.deadline, "past deadline");
    if (cm.forVotes >= majority()) {
        cm.status = Status.Resolved;
        cm.outcome = true;
        // refund stake
    } else if (cm.againstVotes >= majority()) {
        cm.status = Status.Resolved;
        cm.outcome = false;
        // slash to treasury
    }
}
```

#### Majority Formula Change
**Current:** `floor(validators.length / 2) + 1` → 3/5, 3/4, 2/3
**Proposed:** `floor(validators.length / 2)` → 2/5, 2/4, 1/3

**Rationale:** Since stakers can't vote on their own commitments, the effective voter pool is already n-1. The +1 makes the threshold higher than a simple majority of eligible voters. With 5 validators and staker excluded, current = 3/4 eligible (75%), proposed = 2/4 eligible (50%).

**Consideration:** With 3 validators, `floor(3/2)` = 1 — a single vote resolves. May want a minimum threshold of 2.

**Also proposed:** Only validators can create commitments (currently anyone can call `commit()`).

#### Other Contract Ideas
- **`getVote(id, validator)` view** — return vote direction (not just hasVoted bool)
- **Extend deadline** — let staker extend their own deadline (before expiry)
- **Partial delivery** — validators vote on percentage delivered, proportional refund
- **Commitment metadata** — links to proof/deliverable stored onchain or via content hash

---

*Created: 2026-02-11*
*Maintainer: RegenClaw 🍄*
