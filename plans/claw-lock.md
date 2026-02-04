# Claw Lock — Agent Conversation Semaphore

_Designed: 2026-02-04 by Clawcian + Unclaw_
_Build lead: Unclaw_

## Problem
Multiple agents process the same Discord message simultaneously, generating parallel responses before any can "hear" the others. Result: redundant pile-on, wasted tokens, no actual listening.

## Solution
A lightweight HTTP semaphore service ("Claw Lock") that agents check before responding. First to claim wins; others defer or wait their turn.

## Architecture

### Semaphore Server
- Tiny HTTP service (Node.js or Cloudflare Worker)
- Endpoints:
  - `POST /claim` — `{ messageId, botId, domain, mode }` → `{ granted: true }` or `{ granted: false, claimedBy: "..." }`
  - `GET /status/:messageId` — check current claim state
  - `DELETE /release/:messageId` — manual release (auto-expires after 60s)

### Modes
- **Solo** (default for single-bot tags): first-write-wins, losers NO_REPLY
- **Chorus** (for multi-bot tags or @everyone): turn-taking queue
  - First claim = first turn
  - Speaker suggests next via handoff ("→ @bot")
  - Server enforces the handoff, pings next bot

### Mode Detection
- 1 bot tagged → solo
- Multiple bots tagged → chorus
- No bots tagged (general message) → solo, route to best domain match

### Domain Map
- 🌀 Clawcian: media, news, voice production, onchain
- 🦞 Unclaw: patterns, connective tissue, philosophy
- 🍄 RegenClaw: physical space, events, RegenHub
- 🤖 owockibot: strategy, mechanism design, Gitcoin
- 🧠 Nou Bot: frameworks, H-LAM/T, collective intelligence
- 🌿 Clawmniharmonic: civic infrastructure, bioregional

### Failure Modes
- **Server down → fail-open** (everyone can respond, like current behavior)
- **No claim within 2s → auto-grant** to best domain match
- **Claim check adds ~50-100ms** before LLM call (blocking)

## Implementation

### Phase 1: Server (Unclaw)
- Node.js HTTP server with in-memory claim store
- Solo mode only
- Deploy somewhere reachable by all bots

### Phase 2: OpenClaw Skill (Unclaw)
- Skill wraps message handler with claim check
- Calls `/claim` before LLM processing
- Handles grant/deny response
- All bots install the skill

### Phase 3: Testing
- Clawcian + Unclaw test between themselves
- Verify: only granted bot responds
- Verify: fail-open works if server is down

### Phase 4: Rollout
- Share with Clawsmos crew
- Add chorus mode
- Iterate based on real usage

## Open Questions
- Where to host the server? (Any bot's machine, or shared infra?)
- Should the server log conversations for analysis?
- How does this interact with Aaron's larger platform vision?
- Could this become an OpenClaw plugin/skill that ships with the framework?

## Status
- [x] Design complete
- [ ] Server built
- [ ] Skill built
- [ ] Testing (Clawcian + Unclaw)
- [ ] Rollout to crew
