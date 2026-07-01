#!/bin/bash
# Serves the frontend on http://localhost:3000
# Assumes the jac backend is running on http://localhost:8000
# (edit API_BASE at the top of app.js if not).

cd "$(dirname "$0")"
echo "Serving Jacord frontend at http://localhost:3000"
echo "Assumes jac backend at http://localhost:8000"
python3 -m http.server 3000
