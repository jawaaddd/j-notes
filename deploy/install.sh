#!/usr/bin/env bash
# Installs notes-app for the current user on Linux:
#   ~/.local/bin/notes-server             the API, run by a systemd user service
#   ~/.local/share/notes-app/notes.db     your data; daily backups in ./backups
#   ~/.local/share/notes-app/app/         the desktop app, with a launcher entry
#   ~/.local/bin/notes                    a link to the app, for run menus
# Run it again to update; your data is kept. `install.sh uninstall` removes the
# program files and service but leaves your data.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
bin=$HOME/.local/bin
data=${XDG_DATA_HOME:-$HOME/.local/share}/notes-app
units=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
icons=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps

if [[ ${1:-} == uninstall ]]; then
  systemctl --user disable --now notes-server.service 2>/dev/null || true
  rm -f "$units/notes-server.service" "$bin/notes-server" "$bin/notes" "$apps/notes.desktop" "$icons/notes-app.svg"
  rm -rf "$data/app"
  systemctl --user daemon-reload
  echo "Removed notes-app. Your data is still in $data"
  exit 0
fi

echo "Building the server..."
mkdir -p "$bin" "$data" "$units" "$apps" "$icons"
(cd "$repo/backend" && go build -trimpath -o "$bin/notes-server.new" ./cmd/server)
mv "$bin/notes-server.new" "$bin/notes-server"

echo "Building the app..."
(cd "$repo/app" && flutter build linux --release)
rm -rf "$data/app.new"
cp -r "$repo/app/build/linux/x64/release/bundle" "$data/app.new"
rm -rf "$data/app"
mv "$data/app.new" "$data/app"
ln -sfn "$data/app/notes_app" "$bin/notes"

cat > "$units/notes-server.service" <<UNIT
[Unit]
Description=notes-app API

[Service]
ExecStart=$bin/notes-server
Environment=NOTES_ADDR=127.0.0.1:8080
Environment=NOTES_DB=$data/notes.db
Environment=NOTES_BACKUPS=$data/backups
Restart=on-failure

[Install]
WantedBy=default.target
UNIT

cp "$repo/deploy/notes.svg" "$icons/notes-app.svg"
cat > "$apps/notes.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Notes
Comment=Boards, cards, and notes
Exec=$data/app/notes_app
Icon=notes-app
Terminal=false
Categories=Office;ProjectManagement;
StartupWMClass=dev.notesapp.notes_app
DESKTOP
update-desktop-database "$apps" 2>/dev/null || true

systemctl --user daemon-reload
systemctl --user enable notes-server.service >/dev/null
systemctl --user reset-failed notes-server.service 2>/dev/null || true
systemctl --user restart notes-server.service
sleep 2
if ! systemctl --user is-active --quiet notes-server.service; then
  echo
  echo "The server didn't start:" >&2
  journalctl --user -u notes-server -n 3 --no-pager -o cat | grep ERROR >&2 || true
  echo "Fix that (a dev server on port 8080?), then: systemctl --user restart notes-server" >&2
  exit 1
fi

echo
echo "Installed. Open \"Notes\" from your launcher and connect to http://localhost:8080."
# The latest code belongs to the running server; a new one is made each start
# until a password is set.
code=$(journalctl --user -u notes-server -n 20 --no-pager -o cat | grep -o 'setupCode=[^ ]*' | tail -1 || true)
if [[ -n $code ]] && curl -fs http://127.0.0.1:8080/api/auth/status | grep -q '"setupRequired":true'; then
  echo "First run: set your password in the app with this one-time code: ${code#setupCode=}"
fi
