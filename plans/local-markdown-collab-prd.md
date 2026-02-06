# Local-First Markdown Collaboration PRD

**Status:** Draft  
**Author:** Clawcian  
**Date:** 2026-02-06  
**Target:** Humans + AI agents who need to collaborate on markdown files with GitHub backing

---

## Problem Statement

Collaborating on markdown documentation is broken. Current tools force you to choose between:

- **GitHub flow:** Too heavy. Every change requires commit → push → pull → rebase → resolve conflicts. Manual commit messages burn cognitive cycles.
- **Notion/Obsidian Sync:** Opinionated formats, poor Git integration, vendor lock-in.
- **Google Docs:** No markdown, no version control, no local editing in preferred tools.
- **HackMD:** Not local-first. Web-only editing, limited offline support.

**The gap:** No tool exists that lets you:
1. Edit locally in your preferred editor (VSCode, Vim, Emacs, etc.)
2. See changes from collaborators in near-real-time
3. Auto-sync to GitHub with AI-generated commit messages
4. Handle simultaneous edits without manual conflict resolution
5. Work offline and sync when reconnected

This problem affects:
- **Open source projects** with distributed contributors
- **Agent swarms** coordinating on shared knowledge bases
- **Remote teams** documenting in markdown
- **Anyone** who loves local tools but needs collaboration

---

## User Personas

### 1. Human Developer (Primary)
- Edits markdown in VSCode/Vim locally
- Wants collaboration without leaving their editor
- Needs to see who's editing what
- Expects Google Docs-like simultaneous editing
- Wants Git history without manual commits

### 2. AI Agent (Secondary but Critical)
- Edits workspace files programmatically
- Needs headless operation (no UI)
- Syncs on heartbeat (every 5-10 minutes)
- Requires conflict-free merges
- Must respect human edits in real-time

### 3. Non-Technical Contributor (Tertiary)
- Prefers web UI fallback when local setup is too complex
- Needs simple onboarding (clone → install → go)
- Wants visual diff/history browser
- Expects commenting/suggestions like Google Docs

---

## Core Requirements (Must-Have)

### Local-First Editing
- ✅ Edit markdown files in any local editor
- ✅ File watcher detects changes automatically
- ✅ Offline-first (sync when reconnected)
- ✅ Zero latency for local edits

### GitHub Integration
- ✅ Auto-commit changed files with AI-generated commit messages
- ✅ Auto-push to configured branch (default: main)
- ✅ Auto-pull and merge remote changes
- ✅ Respect `.gitignore` and Git conventions

### Simultaneous Editing
- ✅ CRDT or Operational Transform (OT) for conflict-free merges
- ✅ Show live presence ("Aaron is editing USER.md")
- ✅ Character-level sync (not file-level)
- ✅ Graceful degradation when offline

### AI Commit Messages
- ✅ Analyze diff and generate meaningful commit messages
- ✅ Follow conventional commits format (optional config)
- ✅ User can override/edit before push (optional approval mode)
- ✅ Learn from project's commit style

### Agent Support
- ✅ Headless CLI mode (no GUI required)
- ✅ Programmatic API for reading recent changes
- ✅ Heartbeat-driven sync (configurable interval)
- ✅ Webhook/event stream for "file X changed by user Y"

---

## Nice-to-Have

### Enhanced Collaboration
- 💡 Comments/suggestions on specific lines (like Google Docs)
- 💡 @mentions that notify collaborators
- 💡 Visual diff browser (web UI)
- 💡 Rollback/restore to any point in history
- 💡 Branch/PR workflow integration

### Agent Intelligence
- 💡 AI-powered conflict resolution (not just CRDT merge)
- 💡 Suggest improvements to markdown structure
- 💡 Auto-format tables, links, headings
- 💡 Detect and fix broken internal links

### Developer Experience
- 💡 VSCode extension for presence indicators
- 💡 CLI with `init`, `status`, `sync` commands
- 💡 Config file (`.mdcollab.json`) for repo-level settings
- 💡 Ignore patterns for files that shouldn't sync

---

## Technical Approach

### Architecture

```
┌─────────────────┐
│  Local Editor   │ (VSCode, Vim, Emacs)
└────────┬────────┘
         │
    File Watcher
         │
┌────────▼────────┐
│  Sync Engine    │ ← CRDT/OT merge logic
│  (Node.js)      │ ← AI commit message gen
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼──┐  ┌──▼────┐
│ Git  │  │ Server│ (optional relay for presence)
│ Repo │  │ (WS)  │
└──────┘  └───────┘
```

### Key Technologies

**CRDT Implementation:**
- **Yjs** (proven, used by Notion, Figma)
- **Automerge** (pure CRDT, Git-friendly)
- **Local state** persists in `.mdcollab/` directory

**Git Integration:**
- **isomorphic-git** (pure JS, works in Node + browser)
- **simple-git** (wrapper, easier API)
- Commit on interval (e.g., every 30s of inactivity) or manual trigger

**AI Commit Messages:**
- Diff extraction → LLM prompt
- Model: GPT-4 Turbo / Claude Sonnet (fast, cheap)
- Fallback: conventional-commits pattern matching

**Sync Server (Optional):**
- WebSocket relay for presence + real-time diffs
- Falls back to Git-only if server unavailable
- Could be self-hosted or SaaS

---

## User Flows

### 1. Initial Setup (Human)

```bash
# Install CLI
npm install -g mdcollab

# Initialize in a Git repo
cd my-docs
mdcollab init

# Configure GitHub remote (auto-detected from .git)
# Generates auth token if needed

# Start syncing
mdcollab start
```

Watcher runs in background. Edits in VSCode auto-sync.

### 2. Simultaneous Editing (Human + Agent)

**Scenario:** Aaron edits `USER.md` in VSCode. Clawcian (agent) updates same file via script.

1. Aaron types "## New Section" at line 42
2. Clawcian appends "- Note: Updated 2026-02-06" at line 100
3. CRDT merges both edits without conflict
4. Aaron sees Clawcian's change appear in ~2 seconds
5. Clawcian's next read shows Aaron's new section
6. AI generates commit: "docs: add new section, update timestamp"
7. Auto-push to GitHub

### 3. Offline → Online Sync

1. Aaron goes offline, edits 3 files
2. Clawcian (still online) edits 2 of the same files
3. Aaron reconnects
4. mdcollab pulls remote changes, applies CRDT merge
5. Aaron's local state updates, no conflicts
6. Push Aaron's changes with AI commit message

### 4. Agent Headless Mode

```javascript
const MDCollab = require('mdcollab');

const collab = new MDCollab({
  repoPath: '/home/agent/.openclaw/workspace',
  syncInterval: 300000, // 5 min
  autoCommit: true,
  author: { name: 'Clawcian', email: 'clawcian@agents.openclaw.ai' }
});

collab.start();

// Listen for changes
collab.on('file-changed', (file, author) => {
  console.log(`${file} changed by ${author}`);
});

// Programmatic edit
collab.editFile('MEMORY.md', (content) => {
  return content + '\n\n## New Section\nAdded by agent';
});
```

---

## Success Metrics

**Adoption:**
- 1000+ GitHub repos using it within 6 months
- 50+ AI agents using headless mode

**Performance:**
- < 2 second latency for syncing edits
- < 5 second commit generation time
- 99% conflict-free merges with CRDT

**User Satisfaction:**
- NPS > 50
- "Feels like Google Docs but for markdown" feedback

---

## Open Questions

### Technical
1. **CRDT vs OT?** Automerge (CRDT) is simpler but has larger state overhead. Yjs (OT-like) is battle-tested but more complex.
2. **Commit frequency?** Every 30s? Every N edits? User-configurable?
3. **Server required?** Can we do pure P2P + Git? Or do we need relay for low-latency presence?
4. **Binary files?** Ignore? Sync but don't CRDT-merge?

### Product
1. **Pricing model?** Open source core + paid SaaS relay? Freemium?
2. **GitHub App or OAuth?** How to handle auth without exposing tokens?
3. **Enterprise?** Self-hosted server option?
4. **Onboarding?** CLI-first or web signup with token download?

### Agents
1. **Conflict resolution?** Should agents defer to humans when uncertain?
2. **Audit trail?** How to make agent edits clearly attributable?
3. **Rate limiting?** Prevent agent from spamming commits?

---

## Next Steps

1. **Validate demand:** Post to Twitter, HN, relevant Discords. Gauge interest.
2. **Prototype CRDT merge:** Prove Automerge + Git works cleanly.
3. **Build MVP:**
   - File watcher + Git sync (no CRDT yet)
   - AI commit messages
   - CLI with `init`, `start`, `status`
4. **Alpha test:** Use it for bot-friends-guide collaboration.
5. **Iterate:** Add CRDT, presence, web UI based on feedback.

---

## Why This Matters

**For humans:** Markdown is the universal format for docs, READMEs, notes, wikis. Making it collaborative unlocks remote teams.

**For agents:** Shared knowledge bases are critical for multi-agent coordination. This tool lets agents edit collaboratively without stepping on each other.

**For the ecosystem:** Fills a real gap. Could become the "Figma for markdown" — ubiquitous and expected.

Let's build it. 🌀
