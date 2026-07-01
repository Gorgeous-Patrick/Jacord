# Jacord

A Discord-lite chat backend, written in Jac, used as a benchmark for the
TTG prefetch planner.

## Graph shape

```
Root
 └── Contains ── Workspace
                 └── HasChannel ── Channel
                                   └── Posted ── Message ── AuthoredBy ─→ User
                                                 └── ReplyTo ─→ Message ── AuthoredBy ─→ User
                                                                └── ReplyTo ─→ Message ...
```

Single-Root by design — all workspaces, channels, messages, and users
live under the auth user's Root. Authorship is resolved via a `User`
node pool, mirroring how a real chat product resolves message authors
via a users table.

## What makes it interesting for benchmarking

Different from `littlex5`:

- **Bounded per-request working set** (~200–500 anchors for a
  `load_channel` on a 100-message channel with a heavy-tailed reply
  distribution). Tighter than littlex5's ~10K social-fan-out, so the
  prefetch race dynamics look different.
- **Reply tree is variable depth** — most messages have 0 replies, a
  few have 20+. Exercises the TTG BFS with heterogeneous fan-out per
  message.
- **Single-Root** — deliberately drops cross-Root traversal, so the
  planner overhead is smaller and the interesting variable is
  `prefetch_limit` alone.

## Prereqs

- Docker + docker-compose
- Python 3.10+ with `requests` (`pip install requests`)
- `jac` on PATH (with `jac-scale` plugin loaded)

## Bootstrap

```bash
docker compose up -d
sleep 5
jac start &          # in a separate shell
sleep 10
python3 bootstrap.py                       # default: 5 workspaces × 10 channels × 100 msgs
# or larger:
python3 bootstrap.py --workspaces 10 --channels 20 --messages 500
```

Then save a Mongo dump so future sweep runs don't re-seed:

```bash
docker exec mongodb mongodump --db jac_db --archive=/tmp/jac_db.dump
docker cp mongodb:/tmp/jac_db.dump ./jac_db.dump
```

## Sweep

```bash
bash sweep_prefetch_limit.sh
# or via the sweep_tool UI: manifests/jacord.yaml under sweep_tool/
```

## Main walker

`load_channel(channel_id)` — the "open a channel" page load:

1. Navigate to the Channel by jid.
2. Visit every top-level message via `->:Posted:->`.
3. For each message, visit its reply subtree via `->:ReplyTo:->`
   (bounded by whatever the tree looks like).
4. Report a `list[MessageView]` — id, content, author username,
   created_at, reply count.

That's the shape of a chat app's headline query. Everything else
(post_message, workspace_stats, etc.) is scaffolding for seeding and
smoke testing.

## Structure

```
jacord/
├── main.jac                  # types + walker + endpoint declarations
├── main.impl.jac             # implementations
├── jac.toml                  # Jac config (TTG on, thread mode, 4 workers)
├── docker-compose.yaml       # mongo + redis (same shape as littlex5)
├── bootstrap.py              # seed script
├── quick_run.sh              # per-trial runner
├── sweep_prefetch_limit.sh   # sweep driver
├── logs/                     # runtime output (git-ignored)
├── profiles/                 # cProfile output (git-ignored)
└── README.md
```
