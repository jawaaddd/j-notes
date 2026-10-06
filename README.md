# notes-app

A personal Kanban tracker: boards of cards with due dates, tags, and Markdown-like notes with todo lists. A Go server keeps the data in SQLite, and a Flutter desktop app talks to it over a small JSON API. Scrapers and a voice app can send items in through the same API; anything uncertain lands in an Inbox for review.

## Layout

| Path | What |
| --- | --- |
| `backend/` | Go + Gin API server, SQLite storage, daily backups. See [backend/README.md](backend/README.md). |
| `app/` | Flutter desktop app (Linux). See [app/README.md](app/README.md). |
| `deploy/` | Install script for Linux: systemd user service, release app build, launcher entry. |
| `DevelopmentReferences/` | API spec, UI spec, database schema, and the TODO list. |
| `Scrapers/` | Data scrapers (not built yet). |

## Install (Linux)

Requires Go 1.26+ and Flutter 3.47+.

```sh
deploy/install.sh
```

This installs the server as the `notes-server` systemd user service on `127.0.0.1:8080`, keeps data in `~/.local/share/notes-app/` with 14 days of backups, and adds a `notes` command and a Notes launcher entry. On first install it prints a one-time setup code; open the app, connect to `http://localhost:8080`, and enter the code with a new password.

Run it again to update. `deploy/install.sh uninstall` removes everything except your data.

## Development

```sh
cd backend && NOTES_MOCK=1 go run ./cmd/server   # sample data in memory, password "dev"
cd app && flutter run -d linux
```

Tests:

```sh
cd backend && go test ./...
cd app && flutter test
```

## Docs

- [API spec](DevelopmentReferences/backend-api-spec.md)
- [UI spec](DevelopmentReferences/ui-frontend-spec.md)
- [Schema](DevelopmentReferences/schema.sql)
- [TODO](DevelopmentReferences/TODO.md)
