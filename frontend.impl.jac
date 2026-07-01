"""Jacord — client handler bodies."""

impl app.loadWorkspaces -> None {
    # Also ensures the current user has a User node so PostMessage's
    # AuthoredBy lookup finds a target.  Idempotent.
    username = localStorage.getItem("jacord_username") or "";
    if username {
        root spawn EnsureUser(username=username, display_name=username);
    }
    result = root spawn ListWorkspaces();
    workspaces = result.reports[0] if result.reports else [];
}

impl app.toggleWorkspace(workspaceId: str) -> None {
    # `.get(key, default)` with two args to avoid the `x ?? undefined || y`
    # emission the transpiler does for `.get(key) or default`.
    now_open = not expanded.get(workspaceId, False);
    expanded = {**expanded, workspaceId: now_open};
    if now_open and workspaceId not in channelsByWs {
        result = root spawn ListChannels(workspace_id=workspaceId);
        chs = result.reports[0] if result.reports else [];
        channelsByWs = {**channelsByWs, workspaceId: chs};
    }
}

impl app.selectChannel(channel: ChannelView) -> None {
    activeChannel = channel;
    messagesLoading = True;
    messages = [];
    result = root spawn load_channel(channel_id=channel.id);
    messages = result.reports[0] if result.reports else [];
    messagesLoading = False;
}

impl app.refreshMessages -> None {
    if activeChannel is None {
        return;
    }
    result = root spawn load_channel(channel_id=activeChannel.id);
    messages = result.reports[0] if result.reports else [];
}

impl app.sendMessage -> None {
    if activeChannel is None {
        return;
    }
    text = composerText.strip();
    if not text {
        return;
    }
    author = localStorage.getItem("jacord_username") or "";
    root spawn PostMessage(
        channel_id=activeChannel.id,
        author_username=author,
        content=text,
    );
    composerText = "";
    refreshMessages();
}

impl app.createChannelFlow(workspaceId: str) -> None {
    # v0: browser prompt for the channel name.  A proper inline
    # input row belongs in a later iteration.
    name = prompt("Channel name:", "");
    if not name {
        return;
    }
    name = name.strip();
    if not name {
        return;
    }
    root spawn CreateChannel(workspace_id=workspaceId, name=name, topic="");
    result = root spawn ListChannels(workspace_id=workspaceId);
    chs = result.reports[0] if result.reports else [];
    channelsByWs = {**channelsByWs, workspaceId: chs};
    expanded = {**expanded, workspaceId: True};
}

impl app.createWorkspaceFlow -> None {
    # v0: create a default-named workspace + a "general" channel.
    # A proper "New workspace" modal with a form belongs in a later
    # component; for now the sidebar's "+" button just wires the
    # scaffolding so the user can immediately post messages.
    result = root spawn CreateWorkspace(name="New workspace");
    ws_id = result.reports[0] if result.reports else "";
    if not ws_id {
        return;
    }
    root spawn CreateChannel(workspace_id=ws_id, name="general", topic="");
    loadWorkspaces();
    expanded = {**expanded, ws_id: True};
    result2 = root spawn ListChannels(workspace_id=ws_id);
    chs = result2.reports[0] if result2.reports else [];
    channelsByWs = {**channelsByWs, ws_id: chs};
}

impl app.handleLogin -> None {
    authError = "";
    if not authUsername.strip() or not authPassword {
        authError = "Please fill in all fields";
        return;
    }
    authLoading = True;
    ok: bool = await jacLogin(authUsername, authPassword);
    authLoading = False;
    if ok {
        localStorage.setItem("jacord_username", authUsername);
        isLoggedIn = True;
        authPassword = "";
        authError = "";
    } else {
        authError = "Invalid username or password";
    }
}

impl app.handleSignup -> None {
    authError = "";
    if not authUsername.strip() or not authPassword {
        authError = "Please fill in all fields";
        return;
    }
    if len(authPassword) < 4 {
        authError = "Password must be at least 4 characters";
        return;
    }
    authLoading = True;
    result: dict[str, any] = await jacSignup(authUsername, authPassword);
    if result["success"] {
        ok: bool = await jacLogin(authUsername, authPassword);
        authLoading = False;
        if ok {
            localStorage.setItem("jacord_username", authUsername);
            isLoggedIn = True;
            authPassword = "";
            authError = "";
        } else {
            isSignup = False;
            authError = "Account created — please sign in.";
        }
    } else {
        authLoading = False;
        authError = str(result["error"] if result["error"] else "Signup failed");
    }
}

impl app.handleLogout -> None {
    jacLogout();
    localStorage.removeItem("jacord_username");
    isLoggedIn = False;
    workspaces = [];
    channelsByWs = {};
    expanded = {};
    activeChannel = None;
    messages = [];
}
