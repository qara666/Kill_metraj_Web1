#!/bin/bash
cd "$(dirname "$0")"
echo "[Caveman] Smashing fat folders..."
find . -name "node_modules" -type d -prune -exec rm -rf '{}' +
find . -name ".next" -type d -prune -exec rm -rf '{}' +
echo "[Caveman] Folders smashed. Project clean!"
