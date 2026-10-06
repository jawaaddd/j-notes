package memory

import (
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"reflect"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"

	"notes-app/internal/domain"
)

// Persistence: a store opened with Open keeps its whole working set in memory,
// as the mock does, and writes every change through to a SQLite file. tx
// diffs the old and new state and saves the changed rows in one SQLite
// transaction before swapping the new state in, so a failed write leaves both
// the file and memory unchanged. On startup the file is loaded back in full.
//
// The rules (positions, completedAt, same-board checks) live in this package
// only; the schema has no foreign keys, so it can't disagree with them.

//go:embed sqlite_schema.sql
var sqliteSchema string

// Open loads (or creates) the SQLite database at path. A new database starts
// with the default sources and one empty board, or with the mock's sample data
// when sample is set. now and loc are as for New.
func Open(path string, sample bool, now func() time.Time, loc *time.Location) (*Store, error) {
	dsn := "file:" + path + "?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(sqliteSchema); err != nil {
		db.Close()
		return nil, fmt.Errorf("create schema: %w", err)
	}
	st, err := load(db)
	if err != nil {
		db.Close()
		return nil, fmt.Errorf("load %s: %w", path, err)
	}
	s := New(now, loc)
	s.st = st
	s.db = db
	fill := s.upgrade
	if len(st.sources) == 0 {
		fill = s.bootstrap
		if sample {
			fill = s.Seed
		}
	}
	if err := fill(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

// upgrade brings a database from an older build in line with today's rules:
// Urgent tags are yellow and no other tag is, and a source that has never
// reported in is "not_set_up" rather than "ok".
func (s *Store) upgrade() error {
	return s.tx(func(st *state, _ time.Time) error {
		for id, t := range st.tags {
			switch {
			case t.systemKey != nil:
				t.color = domain.UrgentColor
			case t.color == domain.UrgentColor:
				t.color = "orange"
			}
			st.tags[id] = t
		}
		for id, src := range st.sources {
			if src.kind != "manual" && src.health == "ok" && src.lastSyncAt == nil {
				src.health = notSetUp
				st.sources[id] = src
			}
		}
		return nil
	})
}

// Backup writes a consistent copy of the database to path, which must not
// exist. Writes wait until it's done.
func (s *Store) Backup(path string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.db == nil {
		return errors.New("no database: the in-memory mock has nothing to back up")
	}
	_, err := s.db.Exec("VACUUM INTO ?", path)
	return err
}

// Close closes the database, if the store has one.
func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.db == nil {
		return nil
	}
	return s.db.Close()
}

// bootstrap fills a new database: the sources the API knows, and a first board
// so the app has somewhere to put cards.
func (s *Store) bootstrap() error {
	return s.tx(func(st *state, now time.Time) error {
		for _, src := range defaultSources {
			src.id = st.nextID("sources")
			src.health = "ok"
			if src.kind != "manual" {
				src.health = notSetUp
			}
			st.sources[src.id] = src
		}
		_, err := st.insertBoard(domain.BoardCreate{Name: "My board"}, now)
		return err
	})
}

var defaultSources = []source{
	{name: "webwork", kind: "scraper"},
	{name: "autolab", kind: "scraper"},
	{name: "voice", kind: "voice"},
	{name: "syllabus", kind: "import"},
	{name: "manual", kind: "manual"},
}

// ---- writing ----

func (s *Store) persist(old, next *state) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	w := writer{tx: tx, st: next}
	syncTable(&w, old.boards, next.boards, w.board, "boards")
	syncTable(&w, old.lists, next.lists, w.list, "lists")
	syncTable(&w, old.tags, next.tags, w.tag, "tags")
	syncTable(&w, old.sources, next.sources, w.source, "sources")
	syncTable(&w, old.cards, next.cards, w.card, "cards")
	syncTable(&w, old.inbox, next.inbox, w.inbox, "inbox_items")
	syncTable(&w, old.tokens, next.tokens, w.token, "auth_tokens")
	for _, id := range removed(old.cards, next.cards) {
		w.exec("DELETE FROM card_tags WHERE card_id = ?", id)
	}
	if old.passwordHash != next.passwordHash {
		w.setting("password_hash", next.passwordHash)
	}
	for table, n := range next.seq {
		if old.seq[table] != n {
			w.setting("seq."+table, strconv.FormatInt(n, 10))
		}
	}
	if w.err != nil {
		return fmt.Errorf("save to database: %w", w.err)
	}
	return tx.Commit()
}

// writer runs statements until the first error, which it keeps.
type writer struct {
	tx  *sql.Tx
	st  *state
	err error
}

func (w *writer) exec(query string, args ...any) {
	if w.err == nil {
		_, w.err = w.tx.Exec(query, args...)
	}
}

func (w *writer) setting(name, value string) {
	w.exec("INSERT OR REPLACE INTO settings (name, value) VALUES (?, ?)", name, value)
}

// syncTable upserts rows that are new or changed and deletes rows that are gone.
func syncTable[V any](w *writer, old, next map[int64]V, save func(V), table string) {
	for id, v := range next {
		if o, ok := old[id]; !ok || !reflect.DeepEqual(o, v) {
			save(v)
		}
	}
	for _, id := range removed(old, next) {
		w.exec("DELETE FROM "+table+" WHERE id = ?", id)
	}
}

func removed[V any](old, next map[int64]V) []int64 {
	var out []int64
	for id := range maps.Keys(old) {
		if _, ok := next[id]; !ok {
			out = append(out, id)
		}
	}
	return out
}

func (w *writer) board(b board) {
	w.exec(`INSERT OR REPLACE INTO boards (id, name, item_noun, special_tag_label, position, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, b.id, b.name, b.itemNoun, b.tagLabel, b.position, ts(b.createdAt), ts(b.updatedAt))
}

func (w *writer) list(l list) {
	w.exec(`INSERT OR REPLACE INTO lists (id, board_id, name, kind, position) VALUES (?, ?, ?, ?, ?)`,
		l.id, l.boardID, l.name, string(l.kind), l.position)
}

func (w *writer) tag(t tag) {
	w.exec(`INSERT OR REPLACE INTO tags (id, board_id, name, color, is_special, system_key, position)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, t.id, t.boardID, t.name, t.color, t.isSpecial, t.systemKey, t.position)
}

func (w *writer) source(s source) {
	w.exec(`INSERT OR REPLACE INTO sources (id, name, kind, health, status_message, last_sync_at)
		VALUES (?, ?, ?, ?, ?, ?)`, s.id, s.name, s.kind, s.health, s.statusMessage, tsPtr(s.lastSyncAt))
}

func (w *writer) card(c card) {
	notes, err := json.Marshal(c.notes)
	if err != nil && w.err == nil {
		w.err = err
	}
	w.exec(`INSERT OR REPLACE INTO cards (id, board_id, list_id, position, title, due_at, due_all_day, special_tag_id,
		notes, source_id, external_id, source_url, last_synced_at, completed_at, archived_at, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		c.id, c.boardID, c.listID, c.position, c.title, tsPtr(c.dueAt), c.dueAllDay, c.specialTagID,
		string(notes), c.sourceID, c.externalID, c.sourceURL, tsPtr(c.lastSyncedAt), tsPtr(c.completedAt),
		tsPtr(c.archivedAt), ts(c.createdAt), ts(c.updatedAt))
	w.exec("DELETE FROM card_tags WHERE card_id = ?", c.id)
	for i, tagID := range c.tagIDs {
		w.exec("INSERT INTO card_tags (card_id, tag_id, position) VALUES (?, ?, ?)", c.id, tagID, i)
	}
}

func (w *writer) inbox(it domain.InboxItem) {
	src, ok := w.st.sourceByName(it.Source)
	if !ok && w.err == nil {
		w.err = fmt.Errorf("inbox item %d: unknown source %q", it.ID, it.Source)
	}
	parsed, err := json.Marshal(it.Parsed)
	if err != nil && w.err == nil {
		w.err = err
	}
	var field, oldV, newV *string
	if it.Change != nil {
		field, oldV, newV = &it.Change.Field, it.Change.OldValue, it.Change.NewValue
	}
	w.exec(`INSERT OR REPLACE INTO inbox_items (id, type, source_id, board_id, raw_text, parsed, card_id,
		change_field, old_value, new_value, status, received_at, resolved_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		it.ID, string(it.Type), src.id, it.BoardID, it.RawText, string(parsed), it.CardID,
		field, oldV, newV, it.Status, ts(it.ReceivedAt), tsPtr(it.ResolvedAt))
}

func (w *writer) token(t domain.AuthToken) {
	w.exec(`INSERT OR REPLACE INTO auth_tokens (id, kind, name, token_hash, created_at, last_used_at, expires_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, t.ID, string(t.Kind), t.Name, t.Hash[:], ts(t.CreatedAt),
		tsPtr(t.LastUsedAt), tsPtr(t.ExpiresAt))
}

// Times are stored as UTC RFC 3339 text, which sorts correctly as a string.

func ts(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

func tsPtr(t *time.Time) *string {
	if t == nil {
		return nil
	}
	return ptr(ts(*t))
}

// ---- loading ----

func load(db *sql.DB) (*state, error) {
	st := newState()
	r := reader{db: db}

	r.each("SELECT name, value FROM settings", func(sc scanner) error {
		var name, value string
		if err := sc.Scan(&name, &value); err != nil {
			return err
		}
		switch {
		case name == "password_hash":
			st.passwordHash = value
		case strings.HasPrefix(name, "seq."):
			n, err := strconv.ParseInt(value, 10, 64)
			if err != nil {
				return err
			}
			st.seq[strings.TrimPrefix(name, "seq.")] = n
		}
		return nil
	})
	r.each("SELECT id, name, item_noun, special_tag_label, position, created_at, updated_at FROM boards", func(sc scanner) error {
		var b board
		var created, updated string
		if err := sc.Scan(&b.id, &b.name, &b.itemNoun, &b.tagLabel, &b.position, &created, &updated); err != nil {
			return err
		}
		b.createdAt, b.updatedAt = parseTS(created), parseTS(updated)
		st.boards[b.id] = b
		return nil
	})
	r.each("SELECT id, board_id, name, kind, position FROM lists", func(sc scanner) error {
		var l list
		var kind string
		if err := sc.Scan(&l.id, &l.boardID, &l.name, &kind, &l.position); err != nil {
			return err
		}
		l.kind = domain.ListKind(kind)
		st.lists[l.id] = l
		return nil
	})
	r.each("SELECT id, board_id, name, color, is_special, system_key, position FROM tags", func(sc scanner) error {
		var t tag
		if err := sc.Scan(&t.id, &t.boardID, &t.name, &t.color, &t.isSpecial, &t.systemKey, &t.position); err != nil {
			return err
		}
		st.tags[t.id] = t
		return nil
	})
	r.each("SELECT id, name, kind, health, status_message, last_sync_at FROM sources", func(sc scanner) error {
		var s source
		var last *string
		if err := sc.Scan(&s.id, &s.name, &s.kind, &s.health, &s.statusMessage, &last); err != nil {
			return err
		}
		s.lastSyncAt = parseTSPtr(last)
		st.sources[s.id] = s
		return nil
	})
	r.each(`SELECT id, board_id, list_id, position, title, due_at, due_all_day, special_tag_id, notes, source_id,
		external_id, source_url, last_synced_at, completed_at, archived_at, created_at, updated_at FROM cards`, func(sc scanner) error {
		var c card
		var due, synced, completed, archived *string
		var notes, created, updated string
		if err := sc.Scan(&c.id, &c.boardID, &c.listID, &c.position, &c.title, &due, &c.dueAllDay, &c.specialTagID,
			&notes, &c.sourceID, &c.externalID, &c.sourceURL, &synced, &completed, &archived, &created, &updated); err != nil {
			return err
		}
		if err := json.Unmarshal([]byte(notes), &c.notes); err != nil {
			return fmt.Errorf("card %d notes: %w", c.id, err)
		}
		c.dueAt, c.lastSyncedAt = parseTSPtr(due), parseTSPtr(synced)
		c.completedAt, c.archivedAt = parseTSPtr(completed), parseTSPtr(archived)
		c.createdAt, c.updatedAt = parseTS(created), parseTS(updated)
		c.tagIDs = []int64{}
		st.cards[c.id] = c
		return nil
	})
	r.each("SELECT card_id, tag_id FROM card_tags ORDER BY card_id, position", func(sc scanner) error {
		var cardID, tagID int64
		if err := sc.Scan(&cardID, &tagID); err != nil {
			return err
		}
		if c, ok := st.cards[cardID]; ok {
			c.tagIDs = append(c.tagIDs, tagID)
			st.cards[cardID] = c
		}
		return nil
	})
	r.each(`SELECT id, type, source_id, board_id, raw_text, parsed, card_id, change_field, old_value, new_value,
		status, received_at, resolved_at FROM inbox_items`, func(sc scanner) error {
		var it domain.InboxItem
		var typ, parsed, received string
		var sourceID int64
		var field, resolved *string
		var oldV, newV *string
		if err := sc.Scan(&it.ID, &typ, &sourceID, &it.BoardID, &it.RawText, &parsed, &it.CardID, &field, &oldV, &newV,
			&it.Status, &received, &resolved); err != nil {
			return err
		}
		if err := json.Unmarshal([]byte(parsed), &it.Parsed); err != nil {
			return fmt.Errorf("inbox item %d: %w", it.ID, err)
		}
		it.Type = domain.InboxType(typ)
		it.Source = st.sources[sourceID].name // sources load first
		if field != nil {
			it.Change = &domain.Change{Field: *field, OldValue: oldV, NewValue: newV}
		}
		it.ReceivedAt, it.ResolvedAt = parseTS(received), parseTSPtr(resolved)
		st.inbox[it.ID] = it
		return nil
	})
	r.each("SELECT id, kind, name, token_hash, created_at, last_used_at, expires_at FROM auth_tokens", func(sc scanner) error {
		var t domain.AuthToken
		var kind, created string
		var hash []byte
		var used, expires *string
		if err := sc.Scan(&t.ID, &kind, &t.Name, &hash, &created, &used, &expires); err != nil {
			return err
		}
		if len(hash) != len(t.Hash) {
			return fmt.Errorf("auth token %d: bad hash length", t.ID)
		}
		copy(t.Hash[:], hash)
		t.Kind = domain.TokenKind(kind)
		t.CreatedAt, t.LastUsedAt, t.ExpiresAt = parseTS(created), parseTSPtr(used), parseTSPtr(expires)
		st.tokens[t.ID] = t
		return nil
	})
	if r.err != nil {
		return nil, r.err
	}

	return st, nil
}

type scanner interface{ Scan(dest ...any) error }

// reader runs queries until the first error, which it keeps.
type reader struct {
	db  *sql.DB
	err error
}

func (r *reader) each(query string, fn func(scanner) error) {
	if r.err != nil {
		return
	}
	rows, err := r.db.Query(query)
	if err != nil {
		r.err = err
		return
	}
	defer rows.Close()
	for rows.Next() {
		if err := fn(rows); err != nil {
			r.err = err
			return
		}
	}
	r.err = rows.Err()
}

func parseTS(s string) time.Time {
	t, _ := time.Parse(time.RFC3339Nano, s)
	return t.UTC()
}

func parseTSPtr(s *string) *time.Time {
	if s == nil {
		return nil
	}
	return ptr(parseTS(*s))
}
