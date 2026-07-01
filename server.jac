"""Jacord — Discord-lite chat backend.

Graph shape (multi-user; Workspace lives under its creator's user root
and is `grant`ed so any authenticated user can walk into it):

    creator_root
     └── Contains ── Workspace ─── HasChannel ── Channel
                       │                          └── Posted ── Message
                       └── Member ─→ User (in that member's own root)
                                                            │
                                                            └── AuthoredBy ─→ User

Every walker starts on the caller's root.  Cross-root traversal into a
Workspace works because CreateWorkspace `grant`s the workspace + all of
its child nodes at creation.

All client-facing entry points are walkers so the client-side Jac can
spawn them via `root spawn NAME(...)`.  See server.impl.jac for bodies.
"""

import from datetime { datetime, timezone }
import from jaclang { JacRuntimeInterface as Jac }

def _now -> str;

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

node User {
    has username: str = "";
    has display_name: str = "";
    has created_at: str = "";
}

node Workspace {
    has name: str = "";
    has created_at: str = "";
}

node Channel {
    has name: str = "";
    has topic: str = "";
    has created_at: str = "";
}

node Message {
    has content: str = "";
    has created_at: str = "";
}

# ---------------------------------------------------------------------------
# Edges
# ---------------------------------------------------------------------------

edge Contains {}
edge HasChannel {}
edge Posted {}
edge ReplyTo {}
edge AuthoredBy {}
edge Member {}

# ---------------------------------------------------------------------------
# Wire types (imported by the client via `sv import from .server`)
# ---------------------------------------------------------------------------

obj MessageView {
    has id: str,
        content: str,
        author_username: str,
        created_at: str,
        reply_count: int = 0;
}

obj WorkspaceView {
    has id: str,
        name: str;
}

obj ChannelView {
    has id: str,
        name: str,
        topic: str;
}

# ---------------------------------------------------------------------------
# Walkers — all client-callable entry points
# ---------------------------------------------------------------------------

"""Ensure a User node exists for `username` under the caller's root.
The User node is `grant`ed ReadPerm so other users can resolve authorship
across roots.  Idempotent.  Reports the User's jid."""
walker EnsureUser {
    has username: str,
        display_name: str = "";

    can run with Root entry;
}

"""Create a Workspace under the caller's root, add the caller as first
Member, and `grant` the workspace tree so other users can join it."""
walker CreateWorkspace {
    has name: str;

    can run with Root entry;
}

"""Create a Channel under an existing Workspace.  Grants the channel so
non-owner members can read its messages.  Reports the new jid or ""."""
walker CreateChannel {
    has workspace_id: str,
        name: str,
        topic: str = "";

    can run with Root entry;
}

"""Post a top-level message.  Author is derived from the caller's own
User node (no client-provided username)."""
walker PostMessage {
    has channel_id: str,
        content: str;

    can run with Root entry;
}

"""Reply to an existing Message.  Author is derived from caller's root."""
walker PostReply {
    has parent_message_id: str,
        content: str;

    can run with Root entry;
}

"""Join a Workspace by id.  Adds a Member edge from the caller's User
node to the Workspace.  No-op if the caller is already a member."""
walker JoinWorkspace {
    has workspace_id: str;

    can run with Root entry;
}

"""List every Workspace the caller is a Member of, as WorkspaceView rows
— walked from `[root-->User]-->Member-->Workspace`."""
walker ListWorkspaces {
    can run with Root entry;
}

"""List every Channel under one Workspace as ChannelView rows — the
sidebar's expanded section."""
walker ListChannels {
    has workspace_id: str;

    can run with Root entry;
}

"""Sweep helper — reports the first N channel jids across all
workspaces the caller is a member of."""
walker ListChannelIds {
    has limit: int = 100;

    can run with Root entry;
}

"""The main walker — used by both the frontend "open channel" flow and
the sweep_tool benchmark.  Reports list[MessageView] with author
username resolved server-side via `[msg-->AuthoredBy-->User]` so the
client doesn't need to fetch users separately."""
walker load_channel {
    has channel_id: str = "",
        messages: list[MessageView] = [];

    can enter with Root entry;
    can gather_messages with Channel entry;
    can collect_message with Message entry;
    can deliver with Root exit;
}
