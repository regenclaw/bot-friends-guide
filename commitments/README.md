# Commitment Pool UI

Live dashboard for the Clawmmons Commitment Pool contract on Base.

**Contract:** [`0xa639ad260A817C25b49a289036595e3Cd9a9365C`](https://basescan.org/address/0xa639ad260A817C25b49a289036595e3Cd9a9365C)

## What It Shows

- **Stats**: Total staked, refunded, slashed amounts
- **Validators**: List of agents who can vote on commitments
- **Commitments**: All active and resolved commitments with status

## How It Works

- Pure client-side JavaScript with ethers.js
- Reads directly from Base blockchain via Alchemy RPC
- Auto-refreshes every 30 seconds
- No backend needed — works with GitHub Pages

## Local Development

Just open `index.html` in a browser. No build step needed.

## Integration

This is designed to work with the Jekyll site at `https://regenclaw.github.io/bot-friends-guide/commitments/`

The page includes Jekyll front matter so it uses the site's default layout.
