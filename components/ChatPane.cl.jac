"""Right pane — channel header, message list, composer.

The message list is rendered by `load_channel`'s reports, so opening a
channel here produces exactly the traffic pattern the sweep_tool
measures — refresh a channel and you feel prefetch_limit changes."""

sv import from ..server { ChannelView, MessageView }

def _initials(name: str) -> str {
    return name[:2].upper() if name else "?";
}

def:pub ChatPane(
    channel: ChannelView | None,
    messages: list[MessageView],
    loading: bool,
    composerText: str,
    onComposerChange: Callable[[str], None],
    onSend: Callable[[], None],
) -> JsxElement {
    if channel is None {
        return
            <div className="jc-chat-pane">
                <div className="jc-centered">
                    Pick a channel from the sidebar to start chatting.
                </div>
            </div>;
    }
    return
        <div className="jc-chat-pane">
            <div className="jc-channel-header">
                <div className="jc-channel-name">
                    <span className="jc-hash">#</span> {channel.name}
                </div>
                {if channel.topic {
                    <div className="jc-channel-topic">{channel.topic}</div>
                }}
            </div>
            <div className="jc-messages">
                {if loading {
                    <div className="jc-centered">Loading…</div>
                }}
                {if (not loading) and (len(messages) == 0) {
                    <div className="jc-centered">
                        No messages here yet.  Be the first to post.
                    </div>
                }}
                {for m in messages {
                    <div className="jc-message" key={m.id}>
                        <div className="jc-avatar">{_initials(m.author_username)}</div>
                        <div className="jc-msg-body">
                            <div className="jc-msg-head">
                                <span className="jc-msg-author">
                                    {m.author_username or "unknown"}
                                </span>
                                <span className="jc-msg-ts">{m.created_at}</span>
                            </div>
                            <div className="jc-msg-content">{m.content}</div>
                            {if m.reply_count > 0 {
                                <div className="jc-msg-replies">
                                    💬 {str(m.reply_count)} {(
                                        "reply" if m.reply_count == 1 else "replies"
                                    )}
                                </div>
                            }}
                        </div>
                    </div>
                }}
            </div>
            <form
                className="jc-composer"
                onSubmit={lambda e: FormEvent {
                    e.preventDefault();
                    onSend();
                }}
            >
                <input
                    className="jc-input"
                    placeholder={"Message #" + channel.name}
                    value={composerText}
                    onChange={lambda e: ChangeEvent { onComposerChange(e.target.value); }}
                />
            </form>
        </div>;
}
