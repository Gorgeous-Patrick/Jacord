#!/usr/bin/env python3
"""Seed a jacord backend with a multi-user dataset for TTG benchmarks.

Talks to a running `jac start` on http://localhost:8000.

Shape (default `medium` preset):

    10 users, each with their own workspace
    10 channels per workspace          →   100 channels
    500 messages per channel           →   50,000 messages
    heavy-tailed reply distribution    →   ~75,000 replies
                                           ~125k message anchors total

Each user is registered + logged in with their own token.  Every user
also joins every other user's workspace via `JoinWorkspace`, so all
users have full read/write access across the graph — the "primary"
user (`user_0000`) is the one whose walkers `sweep_tool` should target.

Presets via --scale:
    small   ~2.5k msgs      (10 users × 10 ch × 25 msgs)
    medium  ~50k msgs       (10 users × 10 ch × 500 msgs)      [default]
    large   ~400k msgs      (20 users × 20 ch × 1000 msgs)     [SLOW]

Usage:
    python3 bootstrap.py                        # medium
    python3 bootstrap.py --scale small
    python3 bootstrap.py --users 20 --channels 20 --messages 800
    python3 bootstrap.py --workers 32           # more parallelism
"""

from __future__ import annotations

import argparse
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests


BASE_URL = "http://localhost:8000"

CHANNEL_NAMES = [
    "general", "random", "announcements", "help", "showcase",
    "off-topic", "introductions", "resources", "watercooler", "feedback",
    "jobs", "events", "memes", "music", "gaming",
    "coffee", "food", "books", "movies", "sports",
]

TOPIC_TEMPLATES = [
    "Welcome to #{name} — say hi!",
    "Discuss all things {name}",
    "The #{name} channel for {ws}",
    "{ws} · {name}",
    "",
]

MESSAGE_TEMPLATES = [
    "hey everyone, what's up?",
    "just shipped a new feature to prod!",
    "anyone free for a quick call?",
    "did anyone else see the release notes?",
    "quick question: how do you deal with N+1 queries?",
    "gm",
    "TIL you can do that with a walker",
    "does anyone have a spare license for {tool}?",
    "check this out: https://example.com/{slug}",
    "+1 to the above",
    "sounds good, let's ship it",
    "why is this suddenly a debate?",
    "friendly reminder: standup in 5 minutes",
    "the {ws} eng blog just posted about our stack",
    "moving this to a thread so we don't spam the channel",
    "congrats on the promo!",
    "does the sweep tool work with prefetch_limit=0?",
    "walker returned 500 again, looking at logs...",
    "PR is up when someone gets a minute: https://example.com/pr/{slug}",
    "lunch spot recs?",
]

REPLY_TEMPLATES = [
    "same", "+1", "lol", "why though", "makes sense",
    "I'll take a look after lunch",
    "opened a bug: https://example.com/bug/{slug}",
    "let's move this to a call",
    "any updates on this?",
    "closed as fixed",
    "reproducing on my end",
    "works on my machine",
]


PRESETS = {
    "small":  dict(users=10, channels=10, messages=25),
    "medium": dict(users=10, channels=10, messages=500),
    "large":  dict(users=20, channels=20, messages=1000),
}


def _slug() -> str:
    return "".join(random.choices("abcdefghijklmnopqrstuvwxyz0123456789", k=8))


def _pick_message(ws_name: str) -> str:
    return random.choice(MESSAGE_TEMPLATES).format(
        ws=ws_name,
        tool=random.choice(["Figma", "Notion", "Postman", "1Password"]),
        slug=_slug(),
    )


def _pick_reply() -> str:
    return random.choice(REPLY_TEMPLATES).format(slug=_slug())


def _reply_count() -> int:
    """Heavy-tailed reply distribution — most msgs get 0-1 replies,
    a small tail goes long, matching real chat traffic."""
    r = random.random()
    if r < 0.55:
        return 0
    if r < 0.85:
        return random.randint(1, 3)
    if r < 0.97:
        return random.randint(4, 10)
    return random.randint(11, 25)


class Client:
    """One logged-in user; holds its own session + bearer token."""

    def __init__(self, username: str, password: str):
        self.username = username
        self.password = password
        self.session = requests.Session()
        self.token: str | None = None
        self.user_jid: str | None = None
        self.workspace_id: str | None = None

    # --- auth ---

    def register(self) -> None:
        """Idempotent register — swallows duplicate-user errors."""
        try:
            self.session.post(
                f"{BASE_URL}/user/register",
                json={
                    "identities": [{"type": "username", "value": self.username}],
                    "credential": {"type": "password", "password": self.password},
                },
                timeout=15,
            )
        except Exception:
            pass

    def login(self) -> None:
        r = self.session.post(
            f"{BASE_URL}/user/login",
            json={
                "identity": {"type": "username", "value": self.username},
                "credential": {"type": "password", "password": self.password},
            },
            timeout=15,
        )
        r.raise_for_status()
        self.token = r.json()["data"]["token"]

    # --- walker spawn helper ---

    def call(self, walker: str, params: dict, *, retries: int = 3):
        """Spawn a walker, return the first report or None."""
        assert self.token, "login() first"
        last_err: Exception | None = None
        for attempt in range(retries):
            try:
                r = self.session.post(
                    f"{BASE_URL}/walker/{walker}",
                    json=params,
                    headers={"Authorization": f"Bearer {self.token}"},
                    timeout=30,
                )
                r.raise_for_status()
                reports = r.json()["data"].get("reports") or []
                return reports[0] if reports else None
            except Exception as e:
                last_err = e
                time.sleep(0.05 * (attempt + 1))
        raise RuntimeError(f"{walker} failed after {retries} tries: {last_err}")


def wait_for_server(timeout: float = 30.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(f"{BASE_URL}/healthz", timeout=2)
            return
        except Exception:
            time.sleep(0.5)
    print(f"error: server at {BASE_URL} did not respond within {timeout}s", file=sys.stderr)
    sys.exit(1)


def _bootstrap_user(idx: int) -> Client:
    """Register + login one user, create their User node + workspace."""
    c = Client(f"user_{idx:04d}", "password")
    c.register()
    c.login()
    c.user_jid = c.call("EnsureUser", {
        "username": c.username,
        "display_name": f"User {idx}",
    })
    c.workspace_id = c.call("CreateWorkspace", {"name": f"workspace-{idx:02d}"})
    return c


def seed(*, users: int, channels: int, messages: int, seed_val: int, workers: int) -> None:
    random.seed(seed_val)
    wait_for_server()

    # ---- users + their own workspaces ----
    print(f"[1/4] registering {users} users + workspaces...")
    clients: list[Client] = []
    with ThreadPoolExecutor(max_workers=min(workers, users)) as ex:
        for c in ex.map(_bootstrap_user, range(users)):
            clients.append(c)
    clients.sort(key=lambda c: c.username)  # deterministic order

    # ---- cross-membership: every user joins every other user's workspace ----
    print(f"[2/4] cross-joining ({users}×{users - 1} JoinWorkspace calls)...")

    def _join(pair):
        joiner, host = pair
        joiner.call("JoinWorkspace", {"workspace_id": host.workspace_id})

    pairs = [(a, b) for a in clients for b in clients if a is not b]
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(_join, pairs))

    # ---- channels per workspace (created by workspace owner) ----
    print(f"[3/4] creating {channels} channels × {users} workspaces = "
          f"{channels * users} channels...")

    def _make_channels(owner: Client):
        result = []
        for c in range(channels):
            name = CHANNEL_NAMES[c % len(CHANNEL_NAMES)]
            if c >= len(CHANNEL_NAMES):
                name = f"{name}-{c // len(CHANNEL_NAMES)}"
            topic = random.choice(TOPIC_TEMPLATES).format(
                name=name, ws=f"workspace-{clients.index(owner):02d}"
            )
            ch_id = owner.call("CreateChannel", {
                "workspace_id": owner.workspace_id,
                "name": name,
                "topic": topic,
            })
            if ch_id:
                result.append((ch_id, f"workspace-{clients.index(owner):02d}"))
        return result

    all_channels: list[tuple[str, str]] = []  # (ch_id, ws_name)
    with ThreadPoolExecutor(max_workers=min(workers, users)) as ex:
        for chs in ex.map(_make_channels, clients):
            all_channels.extend(chs)

    # ---- messages + replies (bulk) ----
    total_targets = len(all_channels) * messages
    print(f"[4/4] posting ~{total_targets} messages (+ replies) across "
          f"{len(all_channels)} channels with {workers} workers...")

    posted_msgs = 0
    posted_replies = 0
    started = time.time()

    def _post_one(job):
        """One message + its reply chain, posted as random members."""
        ch_id, ws_name = job
        author = random.choice(clients)
        msg_id = author.call("PostMessage", {
            "channel_id": ch_id,
            "content": _pick_message(ws_name),
        })
        replies = 0
        if msg_id:
            for _ in range(_reply_count()):
                r_author = random.choice(clients)
                r_author.call("PostReply", {
                    "parent_message_id": msg_id,
                    "content": _pick_reply(),
                })
                replies += 1
        return 1 if msg_id else 0, replies

    # Flatten (channel, msg_index) so we can parallelize
    jobs = [ch for ch in all_channels for _ in range(messages)]
    random.shuffle(jobs)

    progress_every = max(1, len(jobs) // 20)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(_post_one, j) for j in jobs]
        for i, f in enumerate(as_completed(futs), 1):
            ok, rc = f.result()
            posted_msgs += ok
            posted_replies += rc
            if i % progress_every == 0 or i == len(jobs):
                pct = 100.0 * i / len(jobs)
                dt = time.time() - started
                rate = i / dt if dt > 0 else 0
                print(f"    {i}/{len(jobs)} ({pct:.0f}%) — {rate:.0f} msg/s "
                      f"— msgs={posted_msgs} replies={posted_replies}")

    print()
    print("=" * 60)
    print("Done.")
    print(f"  users              = {users}")
    print(f"  workspaces         = {users}")
    print(f"  channels           = {len(all_channels)}")
    print(f"  top-level messages = {posted_msgs}")
    print(f"  replies            = {posted_replies}")
    print(f"  total msg anchors  = {posted_msgs + posted_replies}")
    print(f"  elapsed            = {time.time() - started:.1f}s")
    print("=" * 60)
    print("Primary user for benchmarks: user_0000 (password 'password').")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--scale", choices=list(PRESETS.keys()), default="medium",
                   help="preset dataset size (default: medium)")
    p.add_argument("--users", type=int, help="override preset --users")
    p.add_argument("--channels", type=int, help="override preset --channels per workspace")
    p.add_argument("--messages", type=int, help="override preset --messages per channel")
    p.add_argument("--workers", type=int, default=16,
                   help="concurrent HTTP workers for the message-posting phase (default 16)")
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()

    preset = PRESETS[args.scale]
    users = args.users or preset["users"]
    channels = args.channels or preset["channels"]
    messages = args.messages or preset["messages"]

    print(f"scale={args.scale} users={users} channels/ws={channels} "
          f"msgs/ch={messages} workers={args.workers}")
    seed(
        users=users,
        channels=channels,
        messages=messages,
        seed_val=args.seed,
        workers=args.workers,
    )


if __name__ == "__main__":
    main()
