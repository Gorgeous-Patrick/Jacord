"""Implementations for jacord's server-side walkers."""

import from datetime { datetime, timezone }
import from jaclang { JacRuntimeInterface as Jac }

impl _now -> str {
    return datetime.now(timezone.utc).isoformat();
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _me -> User | None {
    # The caller's User node — bootstrapped by EnsureUser on first login.
    for u in [root -->[?:User]] {
        return u;
    }
    return None;
}

def _resolve_author(msg: Message) -> str {
    for u in [msg ->:AuthoredBy:->[?:User]] {
        return u.username;
    }
    return "";
}

def _message_view(msg: Message) -> MessageView {
    return MessageView(
        id=jid(msg),
        content=msg.content,
        author_username=_resolve_author(msg),
        created_at=msg.created_at,
        reply_count=len([msg->:ReplyTo:->]),
    );
}

# ---------------------------------------------------------------------------
# EnsureUser
# ---------------------------------------------------------------------------

impl EnsureUser.run with Root entry {
    existing = _me();
    if existing is not None {
        if self.display_name {
            existing.display_name = self.display_name;
        }
        report jid(existing);
        return;
    }
    u = User(
        username=self.username,
        display_name=self.display_name or self.username,
        created_at=_now(),
    );
    root ++> u;
    # Other users need to read username / display_name when rendering
    # authorship on messages posted to workspaces this user joins.
    grant(u, level=ReadPerm);
    report jid(u);
}

# ---------------------------------------------------------------------------
# CreateWorkspace / CreateChannel
# ---------------------------------------------------------------------------

impl CreateWorkspace.run with Root entry {
    me = _me();
    if me is None {
        report "";
        return;
    }
    ws = Workspace(name=self.name, created_at=_now());
    root +>: Contains :+> ws;
    # Creator is a Member from day one.
    me +>: Member :+> ws;
    # ConnectPerm so other users can attach their own Member edges when
    # they call JoinWorkspace.  Also implies ReadPerm.
    grant(ws, level=ConnectPerm);
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
    # Members post messages by attaching a `Posted` edge from the Channel
    # to a new Message — that requires CONNECT on the channel, not just
    # READ.  ConnectPerm implies ReadPerm.
    grant(ch, level=ConnectPerm);
    report jid(ch);
}

# ---------------------------------------------------------------------------
# PostMessage / PostReply
# ---------------------------------------------------------------------------

impl PostMessage.run with Root entry {
    me = _me();
    if me is None {
        report "";
        return;
    }
    ch = jobj(self.channel_id);
    if not isinstance(ch, Channel) {
        report "";
        return;
    }
    msg = Message(content=self.content, created_at=_now());
    ch +>: Posted :+> msg;
    msg +>: AuthoredBy :+> me;
    # ConnectPerm so other members can attach `ReplyTo` off this message.
    grant(msg, level=ConnectPerm);
    report jid(msg);
}

impl PostReply.run with Root entry {
    me = _me();
    if me is None {
        report "";
        return;
    }
    parent = jobj(self.parent_message_id);
    if not isinstance(parent, Message) {
        report "";
        return;
    }
    reply = Message(content=self.content, created_at=_now());
    parent +>: ReplyTo :+> reply;
    reply +>: AuthoredBy :+> me;
    grant(reply, level=ConnectPerm);
    report jid(reply);
}

# ---------------------------------------------------------------------------
# JoinWorkspace
# ---------------------------------------------------------------------------

impl JoinWorkspace.run with Root entry {
    me = _me();
    if me is None {
        report "";
        return;
    }
    ws = jobj(self.workspace_id);
    if not isinstance(ws, Workspace) {
        report "";
        return;
    }
    # No-op if already a Member.
    for existing in [me ->:Member:->[?:Workspace]] {
        if jid(existing) == self.workspace_id {
            report jid(ws);
            return;
        }
    }
    me +>: Member :+> ws;
    report jid(ws);
}

# ---------------------------------------------------------------------------
# ListWorkspaces / ListChannels / ListChannelIds
# ---------------------------------------------------------------------------

impl ListWorkspaces.run with Root entry {
    me = _me();
    out: list[WorkspaceView] = [];
    if me is None {
        report out;
        return;
    }
    for ws in [me ->:Member:->[?:Workspace]] {
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
    me = _me();
    ids: list[str] = [];
    if me is None {
        report ids;
        return;
    }
    for ws in [me ->:Member:->[?:Workspace]] {
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
    self.messages.append(_message_view(here));
    # is_visit=True because this is a literal edge-ref inside a
    # VisitStmt — TTG will recursively prefetch the reply chain up
    # to prefetch_limit.
    visit [->:ReplyTo:->[?:Message]];
}

impl load_channel.deliver with Root exit {
    report self.messages;
}
