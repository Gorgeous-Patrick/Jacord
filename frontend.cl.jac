"""Jacord — top-level client component.

`app` owns the auth + selected-channel state and coordinates all
data-load / mutation handlers.  Rendering delegates to focused
components in ./components/.  Handler bodies are in ./frontend.impl.jac.
"""

import from "@jac/runtime" { jacSignup, jacLogin, jacLogout, jacIsLoggedIn }
sv import from .server {
    EnsureUser,
    CreateWorkspace,
    CreateChannel,
    JoinWorkspace,
    PostMessage,
    ListWorkspaces,
    ListChannels,
    load_channel
}
sv import from .server { WorkspaceView, ChannelView, MessageView }
import from .components.AuthForm { AuthForm }
import from .components.Sidebar { Sidebar }
import from .components.ChatPane { ChatPane }
import "./global.css";

def:pub app -> JsxElement {
    has isLoggedIn: bool = False,
        checkingAuth: bool = True,
        isSignup: bool = False,
        authUsername: str = "",
        authPassword: str = "",
        authError: str = "",
        authLoading: bool = False,
        # Sidebar state
        workspaces: list[WorkspaceView] = [],
        expanded: dict[str, bool] = {},
        channelsByWs: dict[str, list[ChannelView]] = {},
        # Active channel + its messages
        activeChannel: ChannelView | None = None,
        messages: list[MessageView] = [],
        messagesLoading: bool = False,
        composerText: str = "";

    can with entry {
        isLoggedIn = jacIsLoggedIn();
        checkingAuth = False;
    }

    can with [isLoggedIn] entry {
        if isLoggedIn {
            # Fire-and-forget: `root spawn` here would be turned into
            # `await` by the transpiler and useEffect's callback isn't
            # async.  All bootstrap work goes through loadWorkspaces().
            loadWorkspaces();
        }
    }

    async def loadWorkspaces -> None;
    async def toggleWorkspace(workspaceId: str) -> None;
    async def selectChannel(channel: ChannelView) -> None;
    async def refreshMessages -> None;
    async def sendMessage -> None;
    async def createWorkspaceFlow -> None;
    async def joinWorkspaceFlow -> None;
    async def createChannelFlow(workspaceId: str) -> None;
    async def handleLogin -> None;
    async def handleSignup -> None;
    def handleLogout -> None;

    if checkingAuth {
        return <div className="jc-loading">Loading…</div>;
    }

    if not isLoggedIn {
        return
            <AuthForm
                {isSignup}
                username={authUsername}
                password={authPassword}
                error={authError}
                loading={authLoading}
                onUsernameChange={lambda e: ChangeEvent { authUsername = e.target.value; }}
                onPasswordChange={lambda e: ChangeEvent { authPassword = e.target.value; }}
                onSubmit={lambda e: FormEvent {
                    e.preventDefault();
                    if isSignup {
                        handleSignup();
                    } else {
                        handleLogin();
                    }
                }}
                onToggleMode={lambda {
                    isSignup = not isSignup;
                    authError = "";
                }}
            />;
    }

    myUsername = localStorage.getItem("jacord_username") or "";

    return
        <div className="jc-app">
            <Sidebar
                {workspaces}
                {channelsByWs}
                {expanded}
                {activeChannel}
                username={myUsername}
                onToggleWorkspace={toggleWorkspace}
                onSelectChannel={selectChannel}
                onNewWorkspace={createWorkspaceFlow}
                onJoinWorkspace={joinWorkspaceFlow}
                onNewChannel={createChannelFlow}
                onLogout={handleLogout}
            />
            <ChatPane
                channel={activeChannel}
                {messages}
                loading={messagesLoading}
                composerText={composerText}
                onComposerChange={lambda v: str { composerText = v; }}
                onSend={sendMessage}
            />
        </div>;
}
