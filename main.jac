"""Jacord — entry point.

Backend (walkers, nodes, edges) lives in ./server.jac.  Client (`app`
component) lives in ./frontend.cl.jac.  This file just glues them: the
client-side app becomes the page served at `/` when jac.toml sets
`base_route_app = "app"`.
"""

cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
