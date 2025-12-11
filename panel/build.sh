#!/bin/bash
# Site Manager Panel 构建脚本

set -e

cd "$(dirname "$0")"
NODE_PATH="/root/.nvm/versions/node/v20.19.6/bin"
export PATH="$NODE_PATH:$PATH"

echo "=== Building Vue frontend ==="
cd web
npm run build
cd ..

echo "=== Building Go backend ==="
CGO_ENABLED=1 /usr/local/go/bin/go build -o site_manager_panel .

echo "=== Build complete ==="
ls -lh site_manager_panel
echo ""
echo "Run with: ./site_manager_panel --port=8888"
