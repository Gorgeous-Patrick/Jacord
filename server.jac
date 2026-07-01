"""Jacord — Discord-lite chat backend.

Graph shape (single-Root; auth user owns the whole graph):

    Root
     └── Contains ── Workspace
                     └── HasChannel ── Channel
                                       └── Posted ── Message ── AuthoredBy ─→ User
                                                     └── ReplyTo ─→ Message ── AuthoredBy ─→ User

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
    has author_username: str = "";

    def to_view -> MessageView;
}

# ---------------------------------------------------------------------------
# Edges
# ---------------------------------------------------------------------------

edge Contains {}
edge HasChannel {}
edge Posted {}
edge ReplyTo {}
edge AuthoredBy {}

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

"""Ensure a User node exists for `username`.  Idempotent.  Reports the
User's jid."""
walker EnsureUser {
    has username: str,
        display_name: str = "";

    can run with Root entry;
}

"""Create a Workspace under the current Root.  Reports the new jid."""
walker CreateWorkspace {
    has name: str;

    can run with Root entry;
}

"""Create a Channel under an existing Workspace.  Reports the new jid
or "" if workspace_id was invalid."""
walker CreateChannel {
    has workspace_id: str,
        name: str,
        topic: str = "";

    can run with Root entry;
}

"""Post a top-level message.  Reports the new jid."""
walker PostMessage {
    has channel_id: str,
        author_username: str,
        content: str;

    can run with Root entry;
}

"""Reply to an existing Message.  Reports the reply's jid."""
walker PostReply {
    has parent_message_id: str,
        author_username: str,
        content: str;

    can run with Root entry;
}

"""List every Workspace under the current Root as WorkspaceView rows —
the sidebar's top level."""
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
workspaces so the benchmark can pick a random target."""
walker ListChannelIds {
    has limit: int = 100;

    can run with Root entry;
}

"""The main walker — used by both the frontend "open channel" flow and
the sweep_tool benchmark.  Reports list[MessageView] with author
username inlined so the page render doesn't need per-message User
fetches."""
walker load_channel {
    has channel_id: str = "",
        messages: list[MessageView] = [];

    can enter with Root entry;
    can gather_messages with Channel entry;
    can collect_message with Message entry;
    can deliver with Root exit;
}
