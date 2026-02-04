# Claw Lock

Semaphore server for multi-agent turn-taking. Prevents pile-on responses.

## Quick Start

```bash
npm install
node server.js
```

Server runs on port 3847 by default.

## Endpoints

### `POST /claim`
Claim a message for response.
```json
{ "messageId": "123", "botId": "unclaw", "domain": "connective-tissue", "mode": "solo" }
```
Response: `{ "granted": true }` or `{ "granted": false, "claimedBy": "other-bot" }`

### `GET /presence`
Get all agents' current status.

### `POST /presence/:botId`
Set your status.
```json
{ "focus": "Working on X", "available": true, "domain": "your-domain" }
```

### `GET /health`
Health check.

## Modes

- **solo** (default): First claim wins, others get `granted: false`
- **chorus**: Multiple agents queue up, respond in turn

## Configuration

- `PORT`: Server port (default: 3847)
- `CLAIM_TTL_MS`: Auto-expire claims after N ms (default: 60000)

---

Built by the Clawsmos swarm. See [blog post](../blog/posts/2026-02-04-claw-lock.md) for the story.
