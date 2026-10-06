# notes-app desktop

Flutter desktop client for notes-app. The UI follows [`ui-frontend-spec.md`](../DevelopmentReferences/ui-frontend-spec.md) and the notes-app Figma file; it talks to the API in [`../backend`](../backend).

## Run

Start the backend with sample data (`cd ../backend && NOTES_MOCK=1 go run ./cmd/server`), then:

```sh
flutter run -d linux
```

Connect to `http://localhost:8080` and sign in with the mock password `dev`. The server address is remembered; the session token is kept in the OS keychain (Secret Service on Linux). Without one, as on a bare Hyprland session, it goes in `session-tokens.json` in the app's support folder (`~/.local/share/dev.notesapp.notes_app/` on Linux), readable only by you. Sessions last 30 days from last use.

## Install

To use it day to day on Linux, from the repo root:

```sh
deploy/install.sh
```

It builds and installs:

- the server at `~/.local/bin/notes-server`, run at login by the `notes-server` systemd user service on `127.0.0.1:8080`
- your data at `~/.local/share/notes-app/notes.db`, with daily backups in `backups/` beside it (newest 14 kept)
- the release app at `~/.local/share/notes-app/app/`, started with the `notes` command (`~/.local/bin/notes`, so run menus like `rofi -show run` list it) or the **Notes** entry in app menus that read `.desktop` files (`rofi -show drun`)

On first install it prints a one-time setup code; open Notes, connect to `http://localhost:8080`, and enter the code with your new password. If you miss it: `journalctl --user -u notes-server | grep setupCode` (a new code is made each time the server starts until a password is set).

Run it again after pulling changes to update; data is kept. `deploy/install.sh uninstall` removes the program and service but not your data. Server logs: `journalctl --user -u notes-server -f`.

## Layout

| Path | What |
| --- | --- |
| `lib/theme/tokens.dart` | Colors, tag palette, radii, and type scale from the Figma variables |
| `lib/api/` | JSON models and the HTTP client |
| `lib/state/` | Riverpod providers: session, server data, and UI state (view, filters, open card) |
| `lib/util/dates.dart` | Due text and card states (due soon, overdue, done) |
| `lib/ui/` | Shell (title bar, sidebar, status bar) and the Board, Inbox, Calendar, Card Modal, Archive, Settings, and sign-in screens |
| `assets/icons/` | Line icons exported from Figma |
| `assets/fonts/` | Geist and Geist Mono (SIL Open Font License) |

## Test

```sh
flutter test
```

`test/screens_test.dart` renders each designed screen at 1440×900 from API responses captured in `test/fixtures` and compares it to `test/goldens/`. After an intentional UI change, regenerate with `flutter test test/screens_test.dart --update-goldens` and compare the PNGs against the Figma frames. Goldens are rendered on Linux; other platforms may differ slightly in text rendering.
