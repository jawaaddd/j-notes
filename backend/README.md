# notes-app backend

Go + Gin JSON API for notes-app. The contract is in [`../backend-api-spec.md`](../backend-api-spec.md); the database schema it will move to is [`../schema.sql`](../schema.sql).

This is the **mock phase**: everything lives in memory, seeded with the sample data from the Figma frames, and resets when the server restarts.

## Run

Requires Go 1.25+.

```sh
go run ./cmd/server
```

The API listens on `http://127.0.0.1:8080`. Sign in with the mock password `dev`:

```sh
TOKEN=$(curl -s -X POST localhost:8080/api/auth/login -d '{"password":"dev"}' | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/boards
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `NOTES_ADDR` | `127.0.0.1:8080` | Listen address. Use `0.0.0.0:8080` to accept other devices. |
| `NOTES_PASSWORD` | `dev` (mock only) | The password. Set it to an empty string (`NOTES_PASSWORD= go run ./cmd/server`) to start with no password and try first-run setup; the one-time setup code is printed in the log. |

## Layout

| Path | What |
| --- | --- |
| `cmd/server` | Entry point: config, seeding, graceful shutdown |
| `internal/api` | Gin routes, auth middleware, request parsing, error responses |
| `internal/auth` | Password hashing (argon2id), session and API tokens, login rate limiting |
| `internal/domain` | Resource shapes, request bodies, and the error type |
| `internal/store` | Persistence interfaces the handlers depend on |
| `internal/store/memory` | The in-memory implementation and seed data |
| `internal/classify` | Mock voice parser and duplicate matcher (placeholders until the real classifier is chosen) |

Switching to MySQL means adding a `store/mysql` package that implements `store.Store`; the handlers don't change.

## Test

```sh
go test ./...
```
