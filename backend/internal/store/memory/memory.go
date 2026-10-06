// Package memory is the mock-phase store: everything lives in process memory
// and is lost on restart.
//
// Every write runs through tx, which applies the change to a copy of the state
// and swaps it in only if the change succeeds. That gives each method the same
// all-or-nothing behavior a MySQL transaction will.
package memory

import (
	"maps"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"

	"notes-app/internal/domain"
	"notes-app/internal/store"
)

var _ store.Store = (*Store)(nil)

type Store struct {
	mu  sync.Mutex
	st  *state
	now func() time.Time
	// loc is the user's time zone, used for all-day dates ("due thursday"
	// means 23:59 Thursday here) and same-day duplicate checks.
	loc *time.Location
}

// New returns an empty store. now may be nil to use the wall clock; loc may be
// nil to use the server's local time zone.
func New(now func() time.Time, loc *time.Location) *Store {
	if now == nil {
		now = time.Now
	}
	if loc == nil {
		loc = time.Local
	}
	return &Store{st: newState(), now: now, loc: loc}
}

func (s *Store) clock() time.Time { return s.now().UTC().Truncate(time.Second) }

func (s *Store) tx(fn func(st *state, now time.Time) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := s.st.clone()
	if err := fn(next, s.clock()); err != nil {
		return err
	}
	s.st = next
	return nil
}

func (s *Store) view(fn func(st *state, now time.Time) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return fn(s.st, s.clock())
}

type board struct {
	id                       int64
	name, itemNoun, tagLabel string
	position                 int
	createdAt, updatedAt     time.Time
}

type list struct {
	id, boardID int64
	name        string
	kind        domain.ListKind
	position    int
}

type tag struct {
	id, boardID int64
	name, color string
	isSpecial   bool
	systemKey   *string
	position    int
}

// card fields holding pointers or slices are never mutated in place; changes
// assign a fresh value, so a shallow struct copy is safe to share.
type card struct {
	id, boardID, listID  int64
	title                string
	dueAt                *time.Time
	dueAllDay            bool
	specialTagID         *int64
	tagIDs               []int64
	notes                []domain.NoteBlock
	sourceID             int64
	externalID           *string
	sourceURL            *string
	lastSyncedAt         *time.Time
	completedAt          *time.Time
	archivedAt           *time.Time
	createdAt, updatedAt time.Time
}

type source struct {
	id                 int64
	name, kind, health string
	statusMessage      *string
	lastSyncAt         *time.Time
}

type state struct {
	boards       map[int64]board
	lists        map[int64]list
	tags         map[int64]tag
	cards        map[int64]card
	sources      map[int64]source
	inbox        map[int64]domain.InboxItem
	tokens       map[int64]domain.AuthToken
	passwordHash string
	seq          map[string]int64
}

func newState() *state {
	return &state{
		boards:  map[int64]board{},
		lists:   map[int64]list{},
		tags:    map[int64]tag{},
		cards:   map[int64]card{},
		sources: map[int64]source{},
		inbox:   map[int64]domain.InboxItem{},
		tokens:  map[int64]domain.AuthToken{},
		seq:     map[string]int64{},
	}
}

func (st *state) clone() *state {
	c := &state{
		boards:       maps.Clone(st.boards),
		lists:        maps.Clone(st.lists),
		tags:         maps.Clone(st.tags),
		cards:        maps.Clone(st.cards),
		sources:      maps.Clone(st.sources),
		inbox:        maps.Clone(st.inbox),
		tokens:       maps.Clone(st.tokens),
		passwordHash: st.passwordHash,
		seq:          maps.Clone(st.seq),
	}
	return c
}

// nextID hands out ids per table, starting where the spec's examples do.
func (st *state) nextID(table string) int64 {
	starts := map[string]int64{"boards": 1, "lists": 11, "tags": 21, "cards": 101, "inbox": 201, "sources": 1, "tokens": 1}
	if st.seq[table] == 0 {
		st.seq[table] = starts[table]
	} else {
		st.seq[table]++
	}
	return st.seq[table]
}

// ---- lookups ----

func (st *state) board(id int64) (board, error) {
	b, ok := st.boards[id]
	if !ok {
		return board{}, domain.ErrNotFound("board", id)
	}
	return b, nil
}

func (st *state) list(id int64) (list, error) {
	l, ok := st.lists[id]
	if !ok {
		return list{}, domain.ErrNotFound("list", id)
	}
	return l, nil
}

func (st *state) tag(id int64) (tag, error) {
	t, ok := st.tags[id]
	if !ok {
		return tag{}, domain.ErrNotFound("tag", id)
	}
	return t, nil
}

func (st *state) card(id int64) (card, error) {
	c, ok := st.cards[id]
	if !ok {
		return card{}, domain.ErrNotFound("card", id)
	}
	return c, nil
}

func (st *state) sourceByName(name string) (source, bool) {
	for _, s := range st.sources {
		if s.name == name {
			return s, true
		}
	}
	return source{}, false
}

// boardLists returns a board's lists by position.
func (st *state) boardLists(boardID int64) []list {
	var out []list
	for _, l := range st.lists {
		if l.boardID == boardID {
			out = append(out, l)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].position < out[j].position })
	return out
}

// boardTags returns a board's tags, special tags first, then by position.
func (st *state) boardTags(boardID int64) []tag {
	var out []tag
	for _, t := range st.tags {
		if t.boardID == boardID {
			out = append(out, t)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].isSpecial != out[j].isSpecial {
			return out[i].isSpecial
		}
		if out[i].position != out[j].position {
			return out[i].position < out[j].position
		}
		return out[i].id < out[j].id
	})
	return out
}

func (st *state) boardCards(boardID int64) []card {
	var out []card
	for _, c := range st.cards {
		if c.boardID == boardID {
			out = append(out, c)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].id < out[j].id })
	return out
}

func (st *state) firstList(boardID int64, kind domain.ListKind) (list, bool) {
	for _, l := range st.boardLists(boardID) {
		if l.kind == kind {
			return l, true
		}
	}
	return list{}, false
}

func (st *state) isOpen(c card) bool {
	return st.lists[c.listID].kind == domain.KindOpen && c.archivedAt == nil
}

// placeCard puts c in list l and keeps completedAt in step with the list's kind.
func placeCard(c *card, l list, now time.Time) {
	c.listID = l.id
	if l.kind == domain.KindDone {
		if c.completedAt == nil {
			c.completedAt = &now
		}
	} else {
		c.completedAt = nil
	}
}

// boardListOnBoard checks that listID exists and belongs to boardID.
func (st *state) listOnBoard(boardID, listID int64, field string) (list, error) {
	l, ok := st.lists[listID]
	if !ok {
		return list{}, domain.ErrValidation(field, "unknown list")
	}
	if l.boardID != boardID {
		return list{}, domain.ErrCrossBoard(field, listID)
	}
	return l, nil
}

func (st *state) tagOnBoard(boardID, tagID int64, field string) (tag, error) {
	t, ok := st.tags[tagID]
	if !ok {
		return tag{}, domain.ErrValidation(field, "unknown tag")
	}
	if t.boardID != boardID {
		return tag{}, domain.ErrCrossBoard(field, tagID)
	}
	return t, nil
}

func (st *state) checkSpecialTag(boardID, tagID int64) error {
	t, err := st.tagOnBoard(boardID, tagID, "specialTagId")
	if err != nil {
		return err
	}
	if !t.isSpecial {
		return domain.ErrNotSpecial(tagID)
	}
	return nil
}

func (st *state) checkRegularTags(boardID int64, ids []int64) ([]int64, error) {
	out := []int64{}
	seen := map[int64]bool{}
	for _, id := range ids {
		t, err := st.tagOnBoard(boardID, id, "tagIds")
		if err != nil {
			return nil, err
		}
		if t.isSpecial {
			return nil, domain.ErrValidation("tagIds", "special tags go in specialTagId, not tagIds")
		}
		if !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out, nil
}

// ---- conversions ----

func (st *state) toBoard(b board, now time.Time) domain.Board {
	out := domain.Board{
		ID: b.id, Name: b.name, ItemNoun: b.itemNoun, SpecialTagLabel: b.tagLabel,
		Position: b.position, CreatedAt: b.createdAt, UpdatedAt: b.updatedAt,
	}
	for _, c := range st.boardCards(b.id) {
		if st.isOpen(c) {
			out.OpenCount++
			if c.dueAt != nil && c.dueAt.Before(now) {
				out.OverdueCount++
			}
		}
	}
	return out
}

func (st *state) toList(l list) domain.List {
	n := 0
	for _, c := range st.cards {
		if c.listID == l.id && c.archivedAt == nil {
			n++
		}
	}
	return domain.List{ID: l.id, BoardID: l.boardID, Name: l.name, Kind: l.kind, Position: l.position, CardCount: n}
}

func (st *state) toTag(t tag) domain.Tag {
	n := 0
	for _, c := range st.cards {
		if c.boardID != t.boardID || !st.isOpen(c) {
			continue
		}
		if (c.specialTagID != nil && *c.specialTagID == t.id) || slices.Contains(c.tagIDs, t.id) {
			n++
		}
	}
	return domain.Tag{
		ID: t.id, BoardID: t.boardID, Name: t.name, Color: t.color, IsSpecial: t.isSpecial,
		SystemKey: t.systemKey, Position: t.position, OpenCardCount: n,
	}
}

func toSummary(c card) domain.CardSummary {
	return domain.CardSummary{
		ID: c.id, BoardID: c.boardID, ListID: c.listID, Title: c.title, DueAt: c.dueAt,
		DueAllDay: c.dueAllDay, SpecialTagID: c.specialTagID, TagIDs: append([]int64{}, c.tagIDs...),
		CompletedAt: c.completedAt, ArchivedAt: c.archivedAt, CreatedAt: c.createdAt, UpdatedAt: c.updatedAt,
	}
}

func (st *state) toCard(c card) domain.Card {
	notes := append([]domain.NoteBlock{}, c.notes...)
	return domain.Card{
		CardSummary:  toSummary(c),
		Source:       domain.CardSource{Name: st.sources[c.sourceID].name, URL: c.sourceURL},
		ExternalID:   c.externalID,
		LastSyncedAt: c.lastSyncedAt,
		Notes:        notes,
	}
}

// ---- small helpers ----

// cleanName trims a name and checks it is present and not too long.
func cleanName(field, v string, max int) (string, error) {
	v = strings.TrimSpace(v)
	if v == "" {
		return "", domain.ErrValidation(field, field+" is required")
	}
	if len([]rune(v)) > max {
		return "", domain.ErrValidation(field, field+" is too long")
	}
	return v, nil
}

// moveTo removes id from order and reinserts it at pos (clamped).
func moveTo(order []int64, id int64, pos int) []int64 {
	out := slices.DeleteFunc(slices.Clone(order), func(x int64) bool { return x == id })
	pos = max(0, min(pos, len(out)))
	return slices.Insert(out, pos, id)
}

func ptr[T any](v T) *T { return &v }
