/**
 * Claw Lock — Conversation Semaphore Server
 * 
 * Coordinates turn-taking between bots to prevent pile-on responses.
 * 
 * Endpoints:
 *   POST /claim - Claim a message for response
 *   GET /status/:messageId - Check claim status
 *   DELETE /release/:messageId - Release a claim (optional, auto-expires)
 *   GET /health - Health check
 */

const express = require('express');
const app = express();
app.use(express.json());

// In-memory claim store
// Structure: { messageId: { botId, domain, mode, claimedAt, queue: [] } }
const claims = new Map();

// In-memory presence/status store
// Structure: { botId: { focus, available, domain, updatedAt } }
const presence = new Map();

// Auto-expire claims after 60 seconds
const CLAIM_TTL_MS = 60 * 1000;

// Cleanup expired claims every 30 seconds
setInterval(() => {
  const now = Date.now();
  for (const [messageId, claim] of claims) {
    if (now - claim.claimedAt > CLAIM_TTL_MS) {
      claims.delete(messageId);
    }
  }
}, 30 * 1000);

/**
 * POST /claim
 * 
 * Body: { messageId, botId, domain, mode?: "solo" | "chorus" }
 * 
 * Response:
 *   { granted: true } - You got the claim, proceed with response
 *   { granted: false, claimedBy: "botId", position?: number } - Someone else has it
 */
app.post('/claim', (req, res) => {
  const { messageId, botId, domain, mode = 'solo' } = req.body;
  
  if (!messageId || !botId) {
    return res.status(400).json({ error: 'messageId and botId required' });
  }
  
  const existing = claims.get(messageId);
  
  if (!existing) {
    // First claim - grant it
    claims.set(messageId, {
      botId,
      domain,
      mode,
      claimedAt: Date.now(),
      queue: [botId]
    });
    return res.json({ granted: true, position: 0 });
  }
  
  // Claim exists
  if (mode === 'chorus' || existing.mode === 'chorus') {
    // Chorus mode - add to queue
    if (!existing.queue.includes(botId)) {
      existing.queue.push(botId);
    }
    const position = existing.queue.indexOf(botId);
    const isMyTurn = position === 0 || 
      (existing.currentTurn !== undefined && existing.currentTurn === botId);
    
    return res.json({
      granted: isMyTurn,
      position,
      claimedBy: existing.botId,
      queue: existing.queue,
      mode: 'chorus'
    });
  }
  
  // Solo mode - first claim wins
  return res.json({
    granted: false,
    claimedBy: existing.botId,
    mode: 'solo'
  });
});

/**
 * POST /next
 * 
 * Advance to next bot in chorus mode queue
 * Body: { messageId, currentBot }
 */
app.post('/next', (req, res) => {
  const { messageId, currentBot } = req.body;
  
  const claim = claims.get(messageId);
  if (!claim) {
    return res.status(404).json({ error: 'No claim found' });
  }
  
  if (claim.mode !== 'chorus') {
    return res.status(400).json({ error: 'Not in chorus mode' });
  }
  
  const currentIndex = claim.queue.indexOf(currentBot);
  if (currentIndex === -1) {
    return res.status(400).json({ error: 'Bot not in queue' });
  }
  
  // Move to next bot
  const nextIndex = currentIndex + 1;
  if (nextIndex >= claim.queue.length) {
    return res.json({ done: true, message: 'All bots have responded' });
  }
  
  claim.currentTurn = claim.queue[nextIndex];
  return res.json({ 
    done: false, 
    nextBot: claim.currentTurn,
    position: nextIndex
  });
});

/**
 * GET /status/:messageId
 * 
 * Check claim status for a message
 */
app.get('/status/:messageId', (req, res) => {
  const claim = claims.get(req.params.messageId);
  
  if (!claim) {
    return res.json({ claimed: false });
  }
  
  return res.json({
    claimed: true,
    by: claim.botId,
    at: claim.claimedAt,
    mode: claim.mode,
    queue: claim.queue,
    currentTurn: claim.currentTurn
  });
});

/**
 * DELETE /release/:messageId
 * 
 * Release a claim (usually auto-expires)
 */
app.delete('/release/:messageId', (req, res) => {
  const deleted = claims.delete(req.params.messageId);
  return res.json({ released: deleted });
});

/**
 * POST /presence/:botId
 * 
 * Set a bot's presence/status
 * Body: { focus, available, domain }
 */
app.post('/presence/:botId', (req, res) => {
  const { botId } = req.params;
  const { focus, available, domain } = req.body;
  
  presence.set(botId, {
    focus: focus || null,
    available: available !== false, // default true
    domain: domain || null,
    updatedAt: Date.now()
  });
  
  return res.json({ ok: true, botId, status: presence.get(botId) });
});

/**
 * GET /presence
 * 
 * Get all bots' presence
 */
app.get('/presence', (req, res) => {
  const all = {};
  for (const [botId, status] of presence) {
    all[botId] = status;
  }
  return res.json(all);
});

/**
 * GET /presence/:botId
 * 
 * Get one bot's presence
 */
app.get('/presence/:botId', (req, res) => {
  const status = presence.get(req.params.botId);
  if (!status) {
    return res.status(404).json({ error: 'Bot not found' });
  }
  return res.json(status);
});

/**
 * DELETE /presence/:botId
 * 
 * Clear a bot's presence (going offline)
 */
app.delete('/presence/:botId', (req, res) => {
  const deleted = presence.delete(req.params.botId);
  return res.json({ cleared: deleted });
});

/**
 * GET /health
 * 
 * Health check
 */
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    activeClaims: claims.size,
    activePresence: presence.size,
    uptime: process.uptime()
  });
});

// Start server
const PORT = process.env.PORT || 3847;
app.listen(PORT, () => {
  console.log(`Claw Lock server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});
