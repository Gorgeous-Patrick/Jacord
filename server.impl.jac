"""Implementations for jacord's server-side walkers."""

import from datetime { datetime, timezone }
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
# Helper — resolve a username to a User node under the current Root.
# ---------------------------------------------------------------------------

def _find_user(username: str) -> User | None {
    for u in [root -->[?:User]] {
        if u.username == username {
            return u;
        }
    }
    return None;
}

# ---------------------------------------------------------------------------
# EnsureUser
# ---------------------------------------------------------------------------

impl EnsureUser.run with Root entry {
    existing = _find_user(self.username);
    if existing is not None {
        report jid(existing);
        return;
    }
    u = User(
        username=self.username,
        display_name=self.display_name or self.username,
        created_at=_now(),
    );
    root ++> u;
    report jid(u);
}

# ---------------------------------------------------------------------------
# CreateWorkspace / CreateChannel
# ---------------------------------------------------------------------------

impl CreateWorkspace.run with Root entry {
    ws = Workspace(name=self.name, created_at=_now());
    root +>: Contains :+> ws;
    report jid(ws);
}

impl CreateChannel.run with Root entry {
    ws = jobj(self.workspace_id);
    if not isinstance(ws, Workspace) {
        report "";
        return;
    }
    ch = Channel(name=self.name, topic=self.topic, created_at=_now());
    ws +>: HasChannel :+> ch;
    report jid(ch);
}

# ---------------------------------------------------------------------------
# PostMessage / PostReply
# ---------------------------------------------------------------------------

impl PostMessage.run with Root entry {
    ch = jobj(self.channel_id);
    if not isinstance(ch, Channel) {
        report "";
        return;
    }
    msg = Message(
        content=self.content,
        author_username=self.author_username,
        created_at=_now(),
    );
    ch +>: Posted :+> msg;
    a = _find_user(self.author_username);
    if a is not None {
        msg +>: AuthoredBy :+> a;
    }
    report jid(msg);
}

impl PostReply.run with Root entry {
    parent = jobj(self.parent_message_id);
    if not isinstance(parent, Message) {
        report "";
        return;
    }
    reply = Message(
        content=self.content,
        author_username=self.author_username,
        created_at=_now(),
    );
    parent +>: ReplyTo :+> reply;
    a = _find_user(self.author_username);
    if a is not None {
        reply +>: AuthoredBy :+> a;
    }
    report jid(reply);
}

# ---------------------------------------------------------------------------
# ListWorkspaces / ListChannels / ListChannelIds
# ---------------------------------------------------------------------------

impl ListWorkspaces.run with Root entry {
    out: list[WorkspaceView] = [];
    for ws in [root -->[?:Workspace]] {
        out.append(WorkspaceView(id=jid(ws), name=ws.name));
    }
    report out;
}

impl ListChannels.run with Root entry {
    ws = jobj(self.workspace_id);
    out: list[ChannelView] = [];
    if not isinstance(ws, Workspace) {
        report out;
        return;
    }
    for ch in [ws ->:HasChannel:->[?:Channel]] {
        out.append(ChannelView(id=jid(ch), name=ch.name, topic=ch.topic));
    }
    report out;
}

impl ListChannelIds.run with Root entry {
    ids: list[str] = [];
    for ws in [root -->[?:Workspace]] {
        for ch in [ws ->:HasChannel:->[?:Channel]] {
            ids.append(jid(ch));
            if len(ids) >= self.limit {
                report ids;
                return;
            }
        }
    }
    report ids;
}

# ---------------------------------------------------------------------------
# load_channel — the "open channel" walker
# ---------------------------------------------------------------------------

impl load_channel.enter with Root entry {
    target = jobj(self.channel_id);
    if isinstance(target, Channel) {
        visit [target];
    }
}

impl load_channel.gather_messages with Channel entry {
    visit [->:Posted:->[?:Message]];
}

impl load_channel.collect_message with Message entry {
    self.messages.append(here.to_view());
    # is_visit=True because this is a literal edge-ref inside a
    # VisitStmt — TTG will recursively prefetch the reply chain up
    # to prefetch_limit.
    visit [->:ReplyTo:->[?:Message]];
}

impl load_channel.deliver with Root exit {
    report self.messages;
}
