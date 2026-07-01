"""Left sidebar — workspaces list, expandable channels, footer."""

sv import from ..server { WorkspaceView, ChannelView }

def:pub Sidebar(
    workspaces: list[WorkspaceView],
    channelsByWs: dict[str, list[ChannelView]],
    expanded: dict[str, bool],
    activeChannel: ChannelView | None,
    username: str,
    onToggleWorkspace: Callable[[str], None],
    onSelectChannel: Callable[[ChannelView], None],
    onNewWorkspace: Callable[[], None],
    onLogout: Callable[[], None],
) -> JsxElement {
    activeId = activeChannel.id if activeChannel else "";
    return
        <div className="jc-sidebar">
            <div className="jc-sidebar-header">
                <div className="jc-brand">Jacord</div>
                <div className="jc-username">{username}</div>
            </div>
            <div className="jc-sidebar-content">
                {if not workspaces {
                    <div className="jc-sidebar-empty">
                        No workspaces yet.  Create one below.
                    </div>
                }}
                {for ws in workspaces {
                    <div className="jc-workspace" key={ws.id}>
                        <div
                            className="jc-workspace-name"
                            onClick={lambda { onToggleWorkspace(ws.id); }}
                        >
                            <span>{ws.name}</span>
                            <span className={(
                                "jc-chevron jc-chevron-open"
                                    if (expanded.get(ws.id) or False)
                                    else "jc-chevron"
                            )}>▶</span>
                        </div>
                        {if (expanded.get(ws.id) or False) {
                            <div className="jc-channels">
                                {for ch in (channelsByWs.get(ws.id) or []) {
                                    <div
                                        key={ch.id}
                                        className={(
                                            "jc-channel jc-channel-active"
                                                if ch.id == activeId
                                                else "jc-channel"
                                        )}
                                        onClick={lambda { onSelectChannel(ch); }}
                                    >
                                        <span className="jc-hash">#</span>{ch.name}
                                    </div>
                                }}
                                {if not (channelsByWs.get(ws.id) or []) {
                                    <div className="jc-channels-empty">
                                        (no channels)
                                    </div>
                                }}
                            </div>
                        }}
                    </div>
                }}
            </div>
            <div className="jc-sidebar-footer">
                <button className="jc-btn" onClick={onNewWorkspace}>+ Workspace</button>
                <button className="jc-btn" onClick={onLogout}>Sign out</button>
            </div>
        </div>;
}
