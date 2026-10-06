# notes-app backend

Go + Gin JSON API for notes-app. The contract is in [`backend-api-spec.md`](../DevelopmentReferences/backend-api-spec.md); the data model is [`schema.sql`](../DevelopmentReferences/schema.sql).

Data is saved to a single SQLite file, so there's no database server to run. The whole data set is kept in memory and every change is written through to the file before the request returns; a personal tracker's data fits comfortably. With `NOTES_MOCK=1` nothing is saved and the server starts with the sample data from the Figma frames.

## Run

Requires Go 1.26+.

```sh
go run ./cmd/server
```

The first run creates `notes.db` with one empty board and prints a one-time setup code; enter it in the app with your new password. To develop against the sample data instead:

```sh
NOTES_MOCK=1 go run ./cmd/server                                   # in memory, resets on restart
NOTES_SAMPLE_DATA=1 NOTES_DB=dev.db go run ./cmd/server            # saved, starting from the sample data
```

The API listens on `http://127.0.0.1:8080`. In the mock, sign in with the password `dev`:

```sh
TOKEN=$(curl -s -X POST localhost:8080/api/auth/login -d '{"password":"dev"}' | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/boards
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `NOTES_ADDR` | `127.0.0.1:8080` | Listen address. Use `0.0.0.0:8080` to accept other devices. |
| `NOTES_DB` | `notes.db` | The SQLite file, created if missing. |
| `NOTES_BACKUPS` | `backups` next to the database | Folder for daily backups (`notes-YYYY-MM-DD.db`, taken at start and checked hourly), keeping the newest 14. `off` turns them off. A backup is a normal database file: to restore, stop the server and copy it over `NOTES_DB`. |
| `NOTES_SAMPLE_DATA` | unset | `1` fills a new database with the sample data instead of one empty board. |
| `NOTES_MOCK` | unset | `1` keeps everything in memory with the sample data; nothing is saved. |
| `NOTES_PASSWORD` | unset (`dev` in the mock) | Sets the password from the environment, replacing any set in the app. Unset, the server uses the stored password or runs first-run setup. In the mock, set it to an empty string (`NOTES_MOCK=1 NOTES_PASSWORD= go run ./cmd/server`) to try first-run setup. |

## Install

`../deploy/install.sh` installs the server as a systemd user service with its data in `~/.local/share/notes-app` and the desktop app with a launcher entry; see the [app README](../app/README.md#install).

## Layout

| Path | What |
| --- | --- |
| `cmd/server` | Entry point: config, seeding, graceful shutdown |
| `internal/api` | Gin routes, auth middleware, request parsing, error responses |
| `internal/auth` | Password hashing (argon2id), session and API tokens, login rate limiting |
| `internal/domain` | Resource shapes, request bodies, and the error type |
| `internal/store` | Persistence interfaces the handlers depend on |
| `internal/store/memory` | The store: rules, the in-memory working set, SQLite write-through (`sqlite.go`, `sqlite_schema.sql`), and the sample data |
| `internal/classify` | Mock voice parser and duplicate matcher (placeholders until the real classifier is chosen) |

A MySQL store could still be added later as a `store/mysql` package implementing `store.Store`; the handlers wouldn't change.

## Test

```sh
go test ./...
```
