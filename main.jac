"""Jacord — a Discord-lite chat backend for benchmarking TTG prefetch.

Graph shape (single-Root; the auth user owns the whole graph):

    Root
     └── Contains ── Workspace
                     └── HasChannel ── Channel
                                       └── Posted ── Message ── AuthoredBy ─→ User
                                                     └── ReplyTo ─→ Message ── AuthoredBy ─→ User
                                                                    └── ReplyTo ─→ Message ...

The main walker is `load_channel(channel_id)` — the "open a channel"
page-load workload.  Fetches every top-level message plus a bounded
reply tree, materialises MessageView objects with the author's
username baked in.

Authorship deliberately uses a shared `User` node pool (single-Root
lookup) rather than cross-Root — mirrors how a real chat product
resolves authorship via a users table, and keeps this benchmark
different in shape from littlex5 which pushes cross-Root traversal.
"""
import from datetime { datetime, timezone }
import from typing { Any }
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
    # Author username inlined for the same reason littlex5 inlines
    # author_username on Tweet: page-render needs it, and hoisting the
    # per-message User fetch out of the walker's hot path saves ~50%
    # of the request.
    has author_username: str = "";

    def to_view -> MessageView;
}

# ---------------------------------------------------------------------------
# Edges (typed so TTG can prefetch chains)
# ---------------------------------------------------------------------------

edge Contains {}          # Root  → Workspace
edge HasChannel {}        # Workspace → Channel
edge Posted {}            # Channel → Message  (top-level)
edge ReplyTo {}           # Message → Message  (thread reply)
edge AuthoredBy {}        # Message → User

# ---------------------------------------------------------------------------
# Views (wire types)
# ---------------------------------------------------------------------------

obj MessageView {
    has id: str,
        content: str,
        author_username: str,
        created_at: str,
        reply_count: int = 0;
}

obj ChannelView {
    has id: str,
        name: str,
        topic: str,
        messages: list[MessageView] = [];
}

# ---------------------------------------------------------------------------
# Walkers
# ---------------------------------------------------------------------------

"""Load a channel: every top-level message + one hop of replies.

This is the shape of an "open channel #general" page load.  Fanout is
bounded (channel has N messages, each has M replies) and the working
set is roughly N × (1 + M) anchors — with the defaults (100 messages,
avg 3 replies), that's ~400 anchors per request.  Tighter than
littlex5's ~10K, so the prefetch race dynamics look different."""
walker load_channel {
    has channel_id: str = "";
    has messages: list[MessageView] = [];
    has reports: list[ChannelView] = [];

    can enter with Root entry;
    can gather_messages with Channel entry;
    can collect_message with Message entry;
}

"""Sum of message counts across all channels in a workspace.  Cheap,
useful as a "smoke test" walker with a totally different traffic
pattern from load_channel."""
walker workspace_stats {
    has workspace_id: str = "",
        channel_count: int = 0,
        message_count: int = 0;

    can enter with Root entry;
    can visit_channel with Channel entry;
    can visit_message with Message entry;
    can deliver with Root exit;
}

# ---------------------------------------------------------------------------
# Wire endpoints
# ---------------------------------------------------------------------------

"""Create a User node under the current Root.  Idempotent — noop when
a User with this username already exists.  Wire endpoint so the
bootstrap script can seed users without needing a walker."""
def create_user(username: str, display_name: str) -> str;

"""Create a Workspace under the current Root.  Returns its jid."""
def create_workspace(name: str) -> str;

"""Create a Channel under an existing Workspace.  Returns its jid."""
def create_channel(workspace_id: str, name: str, topic: str = "") -> str;

"""Post a message to a Channel.  Returns the new Message's jid so a
follow-up call can attach replies to it."""
def post_message(channel_id: str, author_username: str, content: str) -> str;

"""Post a reply under an existing Message.  Returns the reply's jid."""
def post_reply(parent_message_id: str, author_username: str, content: str) -> str;

"""Return the first N channel jids across all workspaces owned by the
current Root — used by the sweep script to pick a target channel."""
def list_channel_ids(limit: int = 100) -> list[str];

"""Return every Workspace under the current Root as (id, name) rows —
used by the frontend sidebar."""
def list_workspaces -> list[dict[str, str]];

"""Return every Channel under one Workspace as (id, name, topic) rows
— used when the sidebar expands a workspace."""
def list_channels(workspace_id: str) -> list[dict[str, str]];
