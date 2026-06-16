#!/bin/bash
cd "$(dirname "$0")"
echo "[Caveman] Making tiny zip..."
tar -a -c -f Kill_metraj_Web1_Tiny.zip --exclude=node_modules --exclude=.git --exclude=.next "--exclude=*.zip" .
echo "[Caveman] Done! Kill_metraj_Web1_Tiny.zip is ready. Very small!"
