#!/usr/bin/env python3
"""Seed a jacord backend with a realistic-shaped graph.

Talks to a running `jac start` on http://localhost:8000.

Defaults produce something roughly Discord-server-sized:

    50 users
    5 workspaces
    10 channels per workspace          →   50 channels
    100 top-level messages per channel →   5,000 messages
    reply tree per message drawn from a heavy-tailed distribution
    (most messages have 0 replies, a few have 20+)   →  ~8,000 replies

Total: ~13k anchors.  Similar order of magnitude to littlex5 but
different shape — bounded per-request working set (~200-500 anchors
per load_channel call) instead of a 10K social fan-out.

Usage:
    python3 bootstrap.py                    # defaults
    python3 bootstrap.py --workspaces 10 --channels 20 --messages 500

Assumes an admin user 'admin' (password 'password') exists; if not, it
will attempt to register one first.
"""

from __future__ import annotations

import argparse
import random
from datetime import datetime, timezone

import requests


BASE_URL = "http://localhost:8000"
SESSION = requests.Session()


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
    "gm ☕",
    "TIL you can do that with a walker",
    "does anyone have a spare license for {tool}?",
    "check this out: https://example.com/{slug}",
    "+1 to the above",
    "sounds good, let's ship it",
    "why is this suddenly a debate?",
    "friendly reminder: standup in 5 minutes",
    "the {ws} eng blog just posted about our stack",
    "moving this to a thread so we don't spam the channel",
    "🎉 congrats on the promo!",
    "does the sweep tool work with prefetch_limit=0?",
    "walker returned 500 again, looking at logs...",
    "PR is up when someone gets a minute: https://example.com/pr/{slug}",
    "lunch spot recs?",
]

REPLY_TEMPLATES = [
    "same",
    "+1",
    "lol",
    "why though",
    "makes sense",
    "I'll take a look after lunch",
    "opened a bug: https://example.com/bug/{slug}",
    "let's move this to a call",
    "any updates on this?",
    "closed as fixed",
    "reproducing on my end",
    "works on my machine 🤷",
]


def _slug() -> str:
    return "".join(random.choices("abcdefghijklmnopqrstuvwxyz0123456789", k=8))


def _pick_message(ws_name: str) -> str:
    template = random.choice(MESSAGE_TEMPLATES)
    return template.format(
        ws=ws_name,
        tool=random.choice(["Figma", "Notion", "Postman", "1Password"]),
        slug=_slug(),
    )


def _pick_reply() -> str:
    return random.choice(REPLY_TEMPLATES).format(slug=_slug())


def _reply_count() -> int:
    """Heavy-tailed reply-count distribution.

    Most messages have 0 replies (60%), some have a few, a small tail
    goes long (real chat channels look like this — a handful of
    "the thread" messages dominate the reply volume).
    """
    r = random.random()
    if r < 0.60:
        return 0
    if r < 0.85:
        return random.randint(1, 3)
    if r < 0.97:
        return random.randint(4, 10)
    return random.randint(11, 25)


def register_admin() -> None:
    """Ensure admin/password exists — ignore any 4xx from a duplicate register."""
    try:
        SESSION.post(
            f"{BASE_URL}/user/register",
            json={
                "identities": [{"type": "username", "value": "admin"}],
                "credential": {"type": "password", "password": "password"},
            },
        )
    except Exception:
        pass


def login(username: str = "admin", password: str = "password") -> str:
    resp = SESSION.post(
        f"{BASE_URL}/user/login",
        json={
            "identity": {"type": "username", "value": username},
            "credential": {"type": "password", "password": password},
        },
    )
    resp.raise_for_status()
    return resp.json()["data"]["token"]


def _call(token: str, walker: str, params: dict):
    """Spawn a walker and return the first report value."""
    r = SESSION.post(
        f"{BASE_URL}/walker/{walker}",
        json=params,
        headers={"Authorization": f"Bearer {token}"},
    )
    r.raise_for_status()
    reports = r.json()["data"].get("reports") or []
    return reports[0] if reports else None


def seed(*, workspaces: int, channels: int, messages: int, users: int, seed_val: int) -> None:
    random.seed(seed_val)

    register_admin()
    token = login()

    print(f"seeding {users} users...")
    usernames: list[str] = []
    for i in range(users):
        name = f"user_{i:04d}"
        _call(token, "EnsureUser", {"username": name, "display_name": f"User {i}"})
        usernames.append(name)

    total_messages = 0
    total_replies = 0

    for w in range(workspaces):
        ws_name = f"workspace-{w:02d}"
        ws_id = _call(token, "CreateWorkspace", {"name": ws_name})
        print(f"  {ws_name}", end="", flush=True)

        for c in range(channels):
            ch_name = CHANNEL_NAMES[c % len(CHANNEL_NAMES)]
            topic = random.choice(TOPIC_TEMPLATES).format(name=ch_name, ws=ws_name)
            ch_id = _call(
                token, "CreateChannel",
                {"workspace_id": ws_id, "name": ch_name, "topic": topic},
            )

            for m in range(messages):
                author = random.choice(usernames)
                msg_id = _call(
                    token, "PostMessage",
                    {
                        "channel_id": ch_id,
                        "author_username": author,
                        "content": _pick_message(ws_name),
                    },
                )
                total_messages += 1
                for _ in range(_reply_count()):
                    reply_author = random.choice(usernames)
                    _call(
                        token, "PostReply",
                        {
                            "parent_message_id": msg_id,
                            "author_username": reply_author,
                            "content": _pick_reply(),
                        },
                    )
                    total_replies += 1
        print(f"  ✓  ({total_messages} msgs, {total_replies} replies so far)")

    print()
    print("=" * 60)
    print(f"Done.")
    print(f"  workspaces = {workspaces}")
    print(f"  channels/ws = {channels}   total channels = {workspaces * channels}")
    print(f"  msgs/ch    = {messages}   total msgs    = {total_messages}")
    print(f"  replies    = {total_replies}")
    print(f"  users      = {users}")
    print("=" * 60)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--workspaces", type=int, default=5)
    p.add_argument("--channels", type=int, default=10)
    p.add_argument("--messages", type=int, default=100)
    p.add_argument("--users", type=int, default=50)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    seed(
        workspaces=args.workspaces,
        channels=args.channels,
        messages=args.messages,
        users=args.users,
        seed_val=args.seed,
    )


if __name__ == "__main__":
    main()
