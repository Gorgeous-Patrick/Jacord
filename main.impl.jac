"""Implementations for jacord's node methods, walker abilities, and
wire endpoint functions.  See main.jac for the type signatures."""

import from datetime { datetime, timezone }
import from jaclang.jac0core.runtime { jid, jobj, allroots }
import from jaclang { JacRuntimeInterface as Jac }

impl _now -> str {
    return datetime.now(timezone.utc).isoformat();
}

# ---------------------------------------------------------------------------
# Node methods
# ---------------------------------------------------------------------------

impl Message.to_view -> MessageView {
    return MessageView(
        id=jid(self),
        content=self.content,
        author_username=self.author_username,
        created_at=self.created_at,
        reply_count=len([self->:ReplyTo:->]),
    );
}

# ---------------------------------------------------------------------------
# Walker: load_channel
# ---------------------------------------------------------------------------

impl load_channel.enter with Root entry {
    target = jobj(self.channel_id);
    if isinstance(target, Channel) {
        visit [target];
    }
}

impl load_channel.gather_messages with Channel entry {
    # Every top-level message in this channel, in insertion order.
    visit [->:Posted:->[?:Message]];
}

impl load_channel.collect_message with Message entry {
    self.messages.append(here.to_view());
    # One hop of replies — the typical "expand this thread" affordance.
    # `is_visit=True` because this is a literal edge-ref inside a
    # VisitStmt, so the TTG planner will recursively prefetch the reply
    # chain up to prefetch_limit.
    visit [->:ReplyTo:->[?:Message]];
}

# ---------------------------------------------------------------------------
# Walker: workspace_stats
# ---------------------------------------------------------------------------

impl workspace_stats.enter with Root entry {
    target = jobj(self.workspace_id);
    if isinstance(target, Workspace) {
        visit [target->:HasChannel:->[?:Channel]];
    }
}

impl workspace_stats.visit_channel with Channel entry {
    self.channel_count += 1;
    visit [->:Posted:->[?:Message]];
}

impl workspace_stats.visit_message with Message entry {
    self.message_count += 1;
    visit [->:ReplyTo:->[?:Message]];
}

impl workspace_stats.deliver with Root exit {
    report {
        "channels": self.channel_count,
        "messages": self.message_count,
    };
}

# ---------------------------------------------------------------------------
# Wire endpoints
# ---------------------------------------------------------------------------

impl create_user(username: str, display_name: str) -> str {
    for u in [root -->[?:User]] {
        if u.username == username {
            return jid(u);
        }
    }
    new_u = User(
        username=username,
        display_name=display_name or username,
        created_at=_now(),
    );
    root ++> new_u;
    return jid(new_u);
}

impl create_workspace(name: str) -> str {
    ws = Workspace(name=name, created_at=_now());
    root +>: Contains :+> ws;
    return jid(ws);
}

impl create_channel(workspace_id: str, name: str, topic: str = "") -> str {
    ws = jobj(workspace_id);
    if not isinstance(ws, Workspace) {
        return "";
    }
    ch = Channel(name=name, topic=topic, created_at=_now());
    ws +>: HasChannel :+> ch;
    return jid(ch);
}

impl post_message(channel_id: str, author_username: str, content: str) -> str {
    ch = jobj(channel_id);
    if not isinstance(ch, Channel) {
        return "";
    }
    msg = Message(
        content=content,
        author_username=author_username,
        created_at=_now(),
    );
    ch +>: Posted :+> msg;
    # AuthoredBy is optional — the username string on the Message is
    # what the walker uses for the page render.  We still connect the
    # edge so a future walker could compute "messages by this user".
    for a in [root -->[?:User]] {
        if a.username == author_username {
            msg +>: AuthoredBy :+> a;
            break;
        }
    }
    return jid(msg);
}

impl post_reply(parent_message_id: str, author_username: str, content: str) -> str {
    parent = jobj(parent_message_id);
    if not isinstance(parent, Message) {
        return "";
    }
    reply = Message(
        content=content,
        author_username=author_username,
        created_at=_now(),
    );
    parent +>: ReplyTo :+> reply;
    for a in [root -->[?:User]] {
        if a.username == author_username {
            reply +>: AuthoredBy :+> a;
            break;
        }
    }
    return jid(reply);
}

impl list_channel_ids(limit: int = 100) -> list[str] {
    ids: list[str] = [];
    for ws in [root -->[?:Workspace]] {
        for ch in [ws ->:HasChannel:->[?:Channel]] {
            ids.append(jid(ch));
            if len(ids) >= limit {
                return ids;
            }
        }
    }
    return ids;
}

impl list_workspaces -> list[dict[str, str]] {
    out: list[dict[str, str]] = [];
    for ws in [root -->[?:Workspace]] {
        out.append({"id": jid(ws), "name": ws.name});
    }
    return out;
}

impl list_channels(workspace_id: str) -> list[dict[str, str]] {
    ws = jobj(workspace_id);
    out: list[dict[str, str]] = [];
    if not isinstance(ws, Workspace) {
        return out;
    }
    for ch in [ws ->:HasChannel:->[?:Channel]] {
        out.append({
            "id": jid(ch),
            "name": ch.name,
            "topic": ch.topic,
        });
    }
    return out;
}
