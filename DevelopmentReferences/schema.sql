-- notes-app schema (MySQL 8, InnoDB, utf8mb4)
--
-- Terms
--   Board        a fully separate set of cards ("Fall 2026", "Personal")
--   List         a board's column (default: To Do, In Progress, Done)
--   Card         a single item on a board
--   Tag          a label on a card; per board, one palette color
--   Special Tag  a tag with is_special = TRUE; shown in the sidebar and as filter chips
--                ("Classes" on Fall 2026). A card has at most one.
--
-- Rules enforced in the API, not the database
--   - New boards get three lists: To Do (open), In Progress (open), Done (done).
--   - Every board keeps at least one open and one done list.
--   - New cards go to the board's first open list (lowest position).
--   - "Mark as done" moves a card to the first done list; entering a done list
--     sets completed_at, leaving one clears it.
--   - cards.special_tag_id must point at a tag with is_special = TRUE.
--   - Deleting a board or list that still has cards requires an explicit
--     delete-or-move choice. Board delete removes the board's cards before the
--     board itself, because cards reference lists and tags without ON DELETE.
--   - Connections set time_zone = '+00:00', so every DATETIME here is UTC.
--
-- Auth: one user per server. The password hash lives in settings; session and
-- API tokens are stored only as SHA-256 hashes in auth_tokens.

SET NAMES utf8mb4;

CREATE TABLE settings (
  name        VARCHAR(50) PRIMARY KEY,                 -- 'password_hash'
  value       TEXT NOT NULL,                           -- argon2id PHC string
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE auth_tokens (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  kind          ENUM('session','api') NOT NULL,        -- login session or named API token
  name          VARCHAR(100) NOT NULL,                 -- device name or "autolab scraper"
  token_hash    BINARY(32) NOT NULL,                   -- SHA-256 of the token string
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at  DATETIME NULL,
  expires_at    DATETIME NULL,                         -- sessions: 30 days after last use; API tokens: NULL
  UNIQUE KEY uq_token_hash (token_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE boards (
  id                 BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name               VARCHAR(100) NOT NULL,                  -- "Fall 2026"
  item_noun          VARCHAR(50)  NOT NULL DEFAULT 'Cards',  -- page title: "Assignments"
  special_tag_label  VARCHAR(50)  NOT NULL DEFAULT 'Tags',   -- sidebar section: "Classes"
  position           INT NOT NULL DEFAULT 0,                 -- order in the board menu
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE lists (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  board_id    BIGINT UNSIGNED NOT NULL,
  name        VARCHAR(50) NOT NULL,                    -- "To Do", "Waiting", "Shipped"
  kind        ENUM('open','done') NOT NULL DEFAULT 'open',
  position    INT NOT NULL,                            -- column order, left to right
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_list_name  (board_id, name),
  UNIQUE KEY uq_list_board (id, board_id),            -- target for composite FKs
  FOREIGN KEY (board_id) REFERENCES boards(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE tags (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  board_id    BIGINT UNSIGNED NOT NULL,
  name        VARCHAR(50) NOT NULL,
  color       ENUM('pink','blue','violet','cyan','orange','yellow') NOT NULL,
  is_special  BOOLEAN NOT NULL DEFAULT FALSE,          -- sidebar list + filter chips
  system_key  VARCHAR(20) NULL,                        -- 'urgent' for the shortcut pill
  position    INT NOT NULL DEFAULT 0,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tag_name   (board_id, name),
  UNIQUE KEY uq_tag_system (board_id, system_key),
  UNIQUE KEY uq_tag_board  (id, board_id),             -- target for composite FKs
  FOREIGN KEY (board_id) REFERENCES boards(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE sources (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name            VARCHAR(50) NOT NULL UNIQUE,         -- webwork, autolab, voice, syllabus, manual
  kind            ENUM('scraper','voice','import','manual') NOT NULL,
  health          ENUM('ok','needs_reauth','error') NOT NULL DEFAULT 'ok',
  status_message  VARCHAR(255) NULL,                   -- "needs re-login"
  last_sync_at    DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE cards (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  board_id        BIGINT UNSIGNED NOT NULL,
  list_id         BIGINT UNSIGNED NOT NULL,            -- which column the card is in
  title           VARCHAR(255) NOT NULL,
  due_at          DATETIME NULL,                       -- UTC
  due_all_day     BOOLEAN NOT NULL DEFAULT FALSE,      -- "the 14th" vs "11:59 PM"
  special_tag_id  BIGINT UNSIGNED NULL,                -- at most one per card
  notes           JSON NULL,                           -- ordered blocks: text | subtask | link
  source_id       BIGINT UNSIGNED NOT NULL,
  external_id     VARCHAR(255) NULL,                   -- the source's own id for this item
  source_url      VARCHAR(2048) NULL,                  -- "Open on Autolab ↗"
  last_synced_at  DATETIME NULL,
  completed_at    DATETIME NULL,
  archived_at     DATETIME NULL,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_card_external (source_id, external_id), -- makes ingest idempotent
  UNIQUE KEY uq_card_board    (id, board_id),           -- target for composite FKs
  KEY ix_board_list (board_id, list_id),
  KEY ix_board_due   (board_id, due_at),
  FOREIGN KEY (board_id) REFERENCES boards(id) ON DELETE CASCADE,
  FOREIGN KEY (source_id) REFERENCES sources(id),
  -- no ON DELETE: a list with cards can't be deleted until they're moved
  FOREIGN KEY (list_id, board_id) REFERENCES lists(id, board_id),
  FOREIGN KEY (special_tag_id, board_id) REFERENCES tags(id, board_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE card_tags (
  card_id   BIGINT UNSIGNED NOT NULL,
  tag_id    BIGINT UNSIGNED NOT NULL,
  board_id  BIGINT UNSIGNED NOT NULL,                  -- exists only to enforce same-board
  PRIMARY KEY (card_id, tag_id),
  KEY ix_tag (tag_id),
  FOREIGN KEY (card_id, board_id) REFERENCES cards(id, board_id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id, board_id)  REFERENCES tags(id, board_id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE inbox_items (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  type          ENUM('voice','change','duplicate') NOT NULL,
  source_id     BIGINT UNSIGNED NOT NULL,
  board_id      BIGINT UNSIGNED NULL,                  -- parsed or guessed; NULL = unsure
  raw_text      TEXT NOT NULL,                         -- transcript or change description
  parsed        JSON NOT NULL,                         -- {title, specialTagId, dueAt, uncertain: {due: "from 'before thursday'"}}
  card_id       BIGINT UNSIGNED NULL,                  -- change target or duplicate match
  change_field  VARCHAR(50) NULL,                      -- 'title' or 'dueAt' (API field name)
  old_value     VARCHAR(255) NULL,
  new_value     VARCHAR(255) NULL,
  status        ENUM('pending','accepted','discarded','merged','kept_both','ignored') NOT NULL DEFAULT 'pending',
  received_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at   DATETIME NULL,
  KEY ix_status (status, received_at),
  FOREIGN KEY (source_id) REFERENCES sources(id),
  FOREIGN KEY (board_id)  REFERENCES boards(id) ON DELETE SET NULL,
  FOREIGN KEY (card_id)   REFERENCES cards(id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
