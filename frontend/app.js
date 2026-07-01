/* Jacord frontend — single-file React SPA served as static assets.

   Talks to the jac server via fetch().  API_BASE_URL is inferred:
   the page can be served from anywhere; we assume the jac server
   is at http://localhost:8000.  Adjust below if it's elsewhere. */

const API_BASE = "http://localhost:8000";

const {
    useState, useEffect, useMemo, useCallback, useRef, StrictMode,
} = React;

/* ------------------------- tiny API client ------------------------ */

function getToken() { return localStorage.getItem("jacord_token") || ""; }
function setToken(t) {
    if (t) localStorage.setItem("jacord_token", t);
    else localStorage.removeItem("jacord_token");
}
function getUsername() { return localStorage.getItem("jacord_username") || ""; }
function setUsername(u) {
    if (u) localStorage.setItem("jacord_username", u);
    else localStorage.removeItem("jacord_username");
}

async function api(path, body = null, method = "POST") {
    const opts = {
        method,
        headers: {"Content-Type": "application/json"},
    };
    const tok = getToken();
    if (tok) opts.headers["Authorization"] = `Bearer ${tok}`;
    if (body != null && method !== "GET") opts.body = JSON.stringify(body);
    const r = await fetch(`${API_BASE}${path}`, opts);
    let data;
    try { data = await r.json(); }
    catch (e) { throw new Error(`${r.status} ${r.statusText}`); }
    if (!r.ok || data.error) {
        const msg = data?.error?.message || `${r.status} ${r.statusText}`;
        throw new Error(msg);
    }
    return data;
}

async function callFn(name, params = {}) {
    const r = await api(`/function/${name}`, params);
    return r.data.result;
}
async function callWalker(name, params = {}) {
    const r = await api(`/walker/${name}`, params);
    // Walker responses put reports under data.reports (list of lists,
    // one per `report` statement).  load_channel does a single report,
    // so return the first entry.
    const reports = r.data?.reports || [];
    return reports[0] ?? r.data?.result;
}

/* ------------------------- Auth screen ---------------------------- */

function AuthScreen({onAuth}) {
    const [mode, setMode] = useState("login");
    const [username, setUsername_] = useState("");
    const [password, setPassword] = useState("");
    const [error, setError] = useState("");
    const [pending, setPending] = useState(false);

    async function submit(e) {
        e.preventDefault();
        setError("");
        setPending(true);
        try {
            if (mode === "register") {
                await api("/user/register", {
                    identities: [{type: "username", value: username}],
                    credential: {type: "password", password},
                });
            }
            const r = await api("/user/login", {
                identity: {type: "username", value: username},
                credential: {type: "password", password},
            });
            setToken(r.data.token);
            setUsername(username);
            // Ensure a User node exists for message authorship lookups.
            try { await callFn("create_user", {username, display_name: username}); }
            catch (e) { /* first-run users still work without it */ }
            onAuth();
        } catch (e) {
            setError(e.message || "authentication failed");
        } finally {
            setPending(false);
        }
    }

    return (
        <div className="auth-screen">
            <form className="auth-card" onSubmit={submit}>
                <h1>{mode === "login" ? "Sign in to Jacord" : "Create a Jacord account"}</h1>
                <label>Username</label>
                <input
                    value={username}
                    onChange={e => setUsername_(e.target.value)}
                    autoFocus
                    autoComplete="username"
                />
                <label>Password</label>
                <input
                    type="password"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    autoComplete={mode === "login" ? "current-password" : "new-password"}
                />
                <div className="error">{error}</div>
                <button
                    type="submit"
                    className="primary"
                    disabled={pending || !username || !password}
                >
                    {pending ? <span className="spinner" /> : (mode === "login" ? "Sign in" : "Create account")}
                </button>
                <div className="switch">
                    {mode === "login" ? (
                        <>New here?  <a onClick={() => setMode("register")}>Create an account</a></>
                    ) : (
                        <>Already have an account?  <a onClick={() => setMode("login")}>Sign in</a></>
                    )}
                </div>
            </form>
        </div>
    );
}

/* ------------------------- Sidebar -------------------------------- */

function Sidebar({workspaces, channelsByWs, expanded, setExpanded, activeChannel, onPickChannel, onNewWorkspace, onLogout, username}) {
    return (
        <div className="sidebar">
            <div className="sidebar-header">
                <div className="brand">Jacord</div>
                <div className="username">{username || ""}</div>
            </div>
            <div className="sidebar-content">
                {workspaces.length === 0 && (
                    <div style={{padding: "12px", color: "var(--text-muted)", fontSize: "13px"}}>
                        No workspaces yet.  Create one below.
                    </div>
                )}
                {workspaces.map(ws => {
                    const isOpen = expanded.has(ws.id);
                    const channels = channelsByWs[ws.id] || [];
                    return (
                        <div key={ws.id} className="workspace">
                            <div
                                className="workspace-name"
                                onClick={() => {
                                    const next = new Set(expanded);
                                    if (isOpen) next.delete(ws.id); else next.add(ws.id);
                                    setExpanded(next);
                                }}
                            >
                                <span>{ws.name}</span>
                                <span className={`chevron ${isOpen ? "open" : ""}`}>▶</span>
                            </div>
                            {isOpen && (
                                <div className="channels">
                                    {channels.map(ch => (
                                        <div
                                            key={ch.id}
                                            className={`channel ${activeChannel?.id === ch.id ? "active" : ""}`}
                                            onClick={() => onPickChannel(ch)}
                                        >
                                            <span className="hash">#</span>{ch.name}
                                        </div>
                                    ))}
                                    {channels.length === 0 && (
                                        <div style={{padding: "4px 10px", color: "var(--text-dim)", fontSize: "12px"}}>
                                            (no channels)
                                        </div>
                                    )}
                                </div>
                            )}
                        </div>
                    );
                })}
            </div>
            <div className="sidebar-footer">
                <button onClick={onNewWorkspace}>+ Workspace</button>
                <button onClick={onLogout}>Sign out</button>
            </div>
        </div>
    );
}

/* ------------------------- Channel view --------------------------- */

function initials(username) {
    if (!username) return "?";
    return username.slice(0, 2).toUpperCase();
}

function fmtTime(iso) {
    if (!iso) return "";
    try {
        const d = new Date(iso);
        return d.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"});
    } catch { return iso; }
}

function Message({m, onExpandReplies}) {
    return (
        <div className="message">
            <div className="avatar">{initials(m.author_username)}</div>
            <div className="body">
                <div className="head">
                    <span className="author">{m.author_username || "unknown"}</span>
                    <span className="ts">{fmtTime(m.created_at)}</span>
                </div>
                <div className="content">{m.content}</div>
                {m.reply_count > 0 && (
                    <span className="replies" onClick={() => onExpandReplies?.(m)}>
                        💬 {m.reply_count} {m.reply_count === 1 ? "reply" : "replies"}
                    </span>
                )}
            </div>
        </div>
    );
}

function ChannelView({channel, refresh}) {
    const [messages, setMessages] = useState([]);
    const [pending, setPending] = useState(false);
    const [error, setError] = useState("");
    const [text, setText] = useState("");
    const [posting, setPosting] = useState(false);
    const bottomRef = useRef(null);

    const load = useCallback(async () => {
        if (!channel) return;
        setPending(true); setError("");
        try {
            const feed = await callWalker("load_channel", {channel_id: channel.id});
            setMessages(Array.isArray(feed) ? feed : []);
        } catch (e) {
            setError(e.message);
        } finally {
            setPending(false);
        }
    }, [channel]);

    useEffect(() => { load(); }, [load, refresh]);

    useEffect(() => {
        // Auto-scroll to bottom when messages update.
        bottomRef.current?.scrollIntoView({behavior: "auto"});
    }, [messages.length]);

    async function send(e) {
        e.preventDefault();
        if (!text.trim() || !channel) return;
        setPosting(true);
        try {
            await callFn("post_message", {
                channel_id: channel.id,
                author_username: getUsername(),
                content: text.trim(),
            });
            setText("");
            await load();
        } catch (e) {
            setError(e.message);
        } finally {
            setPosting(false);
        }
    }

    if (!channel) {
        return (
            <div className="channel-view">
                <div className="centered">Pick a channel from the sidebar to start chatting.</div>
            </div>
        );
    }

    return (
        <div className="channel-view">
            <div className="channel-header">
                <div className="name"># {channel.name}</div>
                {channel.topic && <div className="topic">{channel.topic}</div>}
            </div>
            <div className="messages">
                {pending && <div className="centered"><span className="spinner" /></div>}
                {!pending && error && <div className="centered" style={{color: "var(--danger)"}}>{error}</div>}
                {!pending && !error && messages.length === 0 && (
                    <div className="centered">No messages here yet.  Be the first to post.</div>
                )}
                {!pending && messages.map(m => (
                    <Message key={m.id} m={m} />
                ))}
                <div ref={bottomRef} />
            </div>
            <form className="composer" onSubmit={send}>
                <textarea
                    placeholder={`Message #${channel.name}`}
                    value={text}
                    onChange={e => setText(e.target.value)}
                    rows={1}
                    onKeyDown={e => {
                        if (e.key === "Enter" && !e.shiftKey) { send(e); }
                    }}
                    disabled={posting}
                />
            </form>
        </div>
    );
}

/* ------------------------- App shell ------------------------------ */

function App() {
    const [signedIn, setSignedIn] = useState(!!getToken());
    const [workspaces, setWorkspaces] = useState([]);
    const [channelsByWs, setChannelsByWs] = useState({});
    const [expanded, setExpanded] = useState(new Set());
    const [activeChannel, setActiveChannel] = useState(null);
    const [refreshTick, setRefreshTick] = useState(0);

    const reloadWorkspaces = useCallback(async () => {
        try {
            const ws = await callFn("list_workspaces");
            setWorkspaces(Array.isArray(ws) ? ws : []);
        } catch (e) { console.error(e); }
    }, []);

    useEffect(() => {
        if (!signedIn) return;
        reloadWorkspaces();
    }, [signedIn, reloadWorkspaces]);

    // Auto-expand + fetch channels the first time a workspace is shown.
    async function ensureChannels(wsId) {
        if (channelsByWs[wsId]) return;
        try {
            const chs = await callFn("list_channels", {workspace_id: wsId});
            setChannelsByWs(prev => ({...prev, [wsId]: Array.isArray(chs) ? chs : []}));
        } catch (e) { console.error(e); }
    }
    useEffect(() => {
        [...expanded].forEach(ensureChannels);
    }, [expanded]);

    async function newWorkspace() {
        const name = prompt("Workspace name:");
        if (!name) return;
        try {
            const id = await callFn("create_workspace", {name});
            const chName = prompt("First channel name:", "general") || "general";
            await callFn("create_channel", {workspace_id: id, name: chName, topic: ""});
            await reloadWorkspaces();
            setChannelsByWs(prev => ({...prev, [id]: undefined}));  // force refetch
            const next = new Set(expanded); next.add(id); setExpanded(next);
        } catch (e) { alert(e.message); }
    }

    function signOut() {
        setToken(""); setUsername("");
        setSignedIn(false); setWorkspaces([]); setChannelsByWs({});
        setExpanded(new Set()); setActiveChannel(null);
    }

    if (!signedIn) return <AuthScreen onAuth={() => setSignedIn(true)} />;
    return (
        <div className="app">
            <Sidebar
                workspaces={workspaces}
                channelsByWs={channelsByWs}
                expanded={expanded}
                setExpanded={setExpanded}
                activeChannel={activeChannel}
                onPickChannel={ch => { setActiveChannel(ch); setRefreshTick(t => t+1); }}
                onNewWorkspace={newWorkspace}
                onLogout={signOut}
                username={getUsername()}
            />
            <ChannelView channel={activeChannel} refresh={refreshTick} />
        </div>
    );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
