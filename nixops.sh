#!/usr/bin/env bash
# Deploy "Brain" to Honeybot
# DEPLOYMENT BOUNDARY (2026-09-13):
# A served body changes when its file is synced; an HTML-only edit does not
# require a NixOS rebuild. Prefer a targeted sync for a body-only change.
# NixOS configuration is merely staged here. Its runtime changes require a
# successful build and activation before an AFTER probe can witness them.
# "Sync Complete" alone proves neither activation nor certificate issuance.

TARGET="mike@192.168.10.100"

echo "🚀 Syncing Hooks..."
scp remotes/honeybot/hooks/post-receive $TARGET:~/git/mikelev.in.git/hooks/post-receive
ssh $TARGET "chmod +x ~/git/mikelev.in.git/hooks/post-receive"

echo "🚀 Syncing Scripts (New Location)..."
# Ensure the directory exists
ssh $TARGET "mkdir -p ~/www/mikelev.in/scripts ~/www/mikelev.in/imports"

# Sync the new dedicated script folder
rsync --delete -av remotes/honeybot/scripts/ $TARGET:~/www/mikelev.in/scripts/

# Surgical sync of the visual display and patronus engine assets
rsync -av imports/ascii_displays.py $TARGET:~/www/mikelev.in/imports/

echo "🚀 Syncing NPvg pad (one address, two bodies)..."
ssh $TARGET "mkdir -p ~/www/npvg.org"
rsync -av remotes/honeybot/www/npvg.org/ $TARGET:~/www/npvg.org/
# ONE SOURCE, TWO PROJECTIONS: the installer lives at assets/installer/install.sh.
# release.py projects it to Pipulate.com; this line projects it to the pad.
rsync -av assets/installer/install.sh $TARGET:~/www/npvg.org/install.sh

echo "🚀 Syncing NixOS Config..."
rsync --delete -av remotes/honeybot/nixos/ $TARGET:~/nixos-config-staged/

echo "✅ Sync Complete."
echo "   To apply NixOS config: ssh -t $TARGET 'sudo cp ~/nixos-config-staged/* /etc/nixos/ && sudo nixos-rebuild switch'"
