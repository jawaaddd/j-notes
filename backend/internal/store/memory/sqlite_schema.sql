-- notes-app SQLite schema. The canonical design is DevelopmentReferences/schema.sql;
-- this is its SQLite form. The store loads every row at startup and enforces
-- the rules in Go, so there are no foreign keys. Times are UTC RFC 3339 text.

CREATE TABLE IF NOT EXISTS settings (
  name   TEXT PRIMARY KEY,  -- 'password_hash', or 'seq.<table>' for the last id handed out
  value  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_tokens (
  id            INTEGER PRIMARY KEY,
  kind          TEXT NOT NULL,         -- session | api
  name          TEXT NOT NULL,
  token_hash    BLOB NOT NULL UNIQUE,  -- SHA-256 of the token
  created_at    TEXT NOT NULL,
  last_used_at  TEXT,
  expires_at    TEXT
);

CREATE TABLE IF NOT EXISTS boards (
  id                 INTEGER PRIMARY KEY,
  name               TEXT NOT NULL,
  item_noun          TEXT NOT NULL,
  special_tag_label  TEXT NOT NULL,
  position           INTEGER NOT NULL,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS lists (
  id        INTEGER PRIMARY KEY,
  board_id  INTEGER NOT NULL,
  name      TEXT NOT NULL,
  kind      TEXT NOT NULL,  -- open | done
  position  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS tags (
  id          INTEGER PRIMARY KEY,
  board_id    INTEGER NOT NULL,
  name        TEXT NOT NULL,
  color       TEXT NOT NULL,
  is_special  INTEGER NOT NULL,
  system_key  TEXT,
  position    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sources (
  id              INTEGER PRIMARY KEY,
  name            TEXT NOT NULL UNIQUE,
  kind            TEXT NOT NULL,
  health          TEXT NOT NULL,
  status_message  TEXT,
  last_sync_at    TEXT
);

CREATE TABLE IF NOT EXISTS cards (
  id              INTEGER PRIMARY KEY,
  board_id        INTEGER NOT NULL,
  list_id         INTEGER NOT NULL,
  position        INTEGER NOT NULL,
  title           TEXT NOT NULL,
  due_at          TEXT,
  due_all_day     INTEGER NOT NULL,
  special_tag_id  INTEGER,
  notes           TEXT NOT NULL,  -- JSON array of blocks
  source_id       INTEGER NOT NULL,
  external_id     TEXT,
  source_url      TEXT,
  last_synced_at  TEXT,
  completed_at    TEXT,
  archived_at     TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS card_tags (
  card_id   INTEGER NOT NULL,
  tag_id    INTEGER NOT NULL,
  position  INTEGER NOT NULL,  -- keeps tagIds in the order they were given
  PRIMARY KEY (card_id, tag_id)
);

CREATE TABLE IF NOT EXISTS inbox_items (
  id            INTEGER PRIMARY KEY,
  type          TEXT NOT NULL,
  source_id     INTEGER NOT NULL,
  board_id      INTEGER,
  raw_text      TEXT NOT NULL,
  parsed        TEXT NOT NULL,  -- JSON
  card_id       INTEGER,
  change_field  TEXT,
  old_value     TEXT,
  new_value     TEXT,
  status        TEXT NOT NULL,
  received_at   TEXT NOT NULL,
  resolved_at   TEXT
);
