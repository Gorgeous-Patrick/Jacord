"""Sign-in / sign-up form for Jacord."""

def:pub AuthForm(
    isSignup: bool,
    username: str,
    password: str,
    error: str,
    loading: bool,
    onUsernameChange: Callable[[ChangeEvent], None],
    onPasswordChange: Callable[[ChangeEvent], None],
    onSubmit: Callable[[FormEvent], None],
    onToggleMode: Callable[[], None],
) -> JsxElement {
    return
        <div className="jc-auth-screen">
            <form className="jc-auth-card" {onSubmit}>
                <h1 className="jc-auth-title">
                    {"Create a Jacord account" if isSignup else "Sign in to Jacord"}
                </h1>
                <label className="jc-auth-label">Username</label>
                <input
                    className="jc-input"
                    type="text"
                    value={username}
                    onChange={onUsernameChange}
                    autoComplete="username"
                    autoFocus
                />
                <label className="jc-auth-label">Password</label>
                <input
                    className="jc-input"
                    type="password"
                    value={password}
                    onChange={onPasswordChange}
                    autoComplete={"new-password" if isSignup else "current-password"}
                />
                {if error {
                    <div className="jc-auth-error">{error}</div>
                }}
                <button
                    type="submit"
                    className="jc-btn jc-btn-primary jc-auth-submit"
                    disabled={loading}
                >
                    {("…" if loading else ("Create account" if isSignup else "Sign in"))}
                </button>
                <div className="jc-auth-switch">
                    {(
                        "Already have an account? "
                            if isSignup
                            else "New here? "
                    )}
                    <a onClick={onToggleMode}>
                        {("Sign in" if isSignup else "Create an account")}
                    </a>
                </div>
            </form>
        </div>;
}
