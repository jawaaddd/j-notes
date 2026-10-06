package memory

import (
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"notes-app/internal/domain"
)

// TestSQLiteRoundTrip makes changes of every kind, reopens the file, and
// checks the loaded state matches what was in memory.
func TestSQLiteRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notes.db")
	now := func() time.Time { return time.Date(2026, 10, 6, 15, 0, 0, 0, time.UTC) }
	s, err := Open(path, true, now, time.UTC)
	if err != nil {
		t.Fatal(err)
	}
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	_, err = s.CreateBoard(domain.BoardCreate{Name: "Summer"})
	must(err)
	cards, err := s.ListCards(1, domain.CardQuery{Sort: domain.SortPosition})
	must(err)
	var tagged []int64
	for _, x := range cards {
		tagged = append(tagged, x.TagIDs...)
	}
	c, err := s.CreateCard(1, domain.CardCreate{Title: "New", TagIDs: tagged[:1]})
	must(err)
	_, err = s.UpdateCard(c.ID, domain.CardPatch{Position: domain.Some(0)})
	must(err)
	_, err = s.SaveNotes(c.ID, []domain.NoteBlock{{ID: "a", Type: domain.BlockTodo, Text: "x", Done: true}})
	must(err)
	_, err = s.MarkDone(cards[1].ID)
	must(err)
	must(s.DeleteCard(cards[2].ID))
	inbox, err := s.ListInbox(nil)
	must(err)
	_, err = s.ResolveInbox(inbox.Items[0].ID, domain.InboxResolve{Action: "discard"})
	must(err)
	_, err = s.CreateToken(domain.AuthToken{Kind: domain.TokenAPI, Name: "scraper", Hash: [32]byte{1, 2}, CreatedAt: now()})
	must(err)
	must(s.SetPasswordHash("hash"))
	want := s.st
	must(s.Close())

	s2, err := Open(path, true, now, time.UTC)
	must(err)
	defer s2.Close()
	got := s2.st
	for id, c := range want.cards { // a fresh card may hold nil where a loaded one holds []
		if c.tagIDs == nil {
			c.tagIDs = []int64{}
			want.cards[id] = c
		}
	}
	for name, pair := range map[string][2]any{
		"boards": {want.boards, got.boards}, "lists": {want.lists, got.lists}, "tags": {want.tags, got.tags},
		"cards": {want.cards, got.cards}, "sources": {want.sources, got.sources}, "inbox": {want.inbox, got.inbox},
		"tokens": {want.tokens, got.tokens}, "password": {want.passwordHash, got.passwordHash}, "seq": {want.seq, got.seq},
	} {
		if !reflect.DeepEqual(pair[0], pair[1]) {
			t.Errorf("%s differs after reload:\nwant %+v\n got %+v", name, pair[0], pair[1])
		}
	}
}

// TestFreshAndUpgrade covers a new database (sources not set up, Urgent
// yellow) and the upgrade of one written by an older build.
func TestFreshAndUpgrade(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notes.db")
	s, err := Open(path, false, nil, time.UTC)
	if err != nil {
		t.Fatal(err)
	}
	health := func(s *Store) map[string]string {
		t.Helper()
		srcs, err := s.ListSources()
		if err != nil {
			t.Fatal(err)
		}
		out := map[string]string{}
		for _, x := range srcs {
			out[x.Name] = x.Health
		}
		return out
	}
	if h := health(s); h["webwork"] != notSetUp || h["voice"] != notSetUp || h["manual"] != "ok" {
		t.Fatalf("fresh sources: %v", h)
	}
	if _, err := s.Ingest(domain.IngestBatch{Source: "voice", Items: []domain.IngestItem{{RawText: ptr("call mom tomorrow")}}}); err != nil {
		t.Fatal(err)
	}
	if h := health(s); h["voice"] != "ok" {
		t.Fatalf("voice should be ok after its first item: %v", h)
	}

	// Write what an older build would have: a pink Urgent, a yellow tag, and
	// sources marked ok that never synced.
	for _, q := range []string{
		`UPDATE tags SET color = 'pink' WHERE system_key IS NOT NULL`,
		`INSERT INTO tags (id, board_id, name, color, is_special, position) VALUES (999, 1, 'Old', 'yellow', 0, 9)`,
		`UPDATE sources SET health = 'ok'`,
	} {
		if _, err := s.db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	s.Close()
	s, err = Open(path, false, nil, time.UTC)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	tags, err := s.ListTags(1)
	if err != nil {
		t.Fatal(err)
	}
	for _, tg := range tags {
		if (tg.SystemKey != nil) != (tg.Color == domain.UrgentColor) {
			t.Fatalf("only Urgent should be yellow: %+v", tg)
		}
	}
	if h := health(s); h["webwork"] != notSetUp || h["voice"] != "ok" {
		t.Fatalf("upgraded sources: %v", h)
	}
}

func TestBackup(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(filepath.Join(dir, "notes.db"), true, nil, time.UTC)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	want, _ := s.ListBoards()
	copyPath := filepath.Join(dir, "copy.db")
	if err := s.Backup(copyPath); err != nil {
		t.Fatal(err)
	}
	c, err := Open(copyPath, false, nil, time.UTC)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	got, _ := c.ListBoards()
	if len(got) != len(want) || len(got) == 0 {
		t.Fatalf("copy has %d boards, want %d", len(got), len(want))
	}
	if err := New(nil, nil).Backup(filepath.Join(dir, "x.db")); err == nil {
		t.Fatal("mock store backup should fail")
	}
}
