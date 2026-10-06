package memory

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"notes-app/internal/classify"
	"notes-app/internal/domain"
)

var healths = map[string]bool{"ok": true, "needs_reauth": true, "error": true}

// notSetUp is the health of a source that has never sent a heartbeat or an
// item. The first one replaces it.
const notSetUp = "not_set_up"

func (s *Store) Ingest(in domain.IngestBatch) ([]domain.IngestResult, error) {
	var out []domain.IngestResult
	err := s.tx(func(st *state, now time.Time) error {
		src, ok := st.sourceByName(in.Source)
		if !ok {
			return domain.ErrValidation("source", "unknown source")
		}
		out = []domain.IngestResult{}
		for i, item := range in.Items {
			field := fmt.Sprintf("items[%d]", i)
			var (
				r   domain.IngestResult
				err error
			)
			if item.ExternalID == nil {
				r, err = st.ingestVoice(src, item, field, now, s.loc)
			} else {
				r, err = st.ingestScraped(src, item, field, now, s.loc)
			}
			if err != nil {
				return err
			}
			out = append(out, r)
		}
		if src.health == notSetUp {
			src.health, src.lastSyncAt = "ok", &now
			st.sources[src.id] = src
		}
		return nil
	})
	return out, err
}

// ingestScraped handles a structured item from a scraper or importer.
func (st *state) ingestScraped(src source, item domain.IngestItem, field string, now time.Time, loc *time.Location) (domain.IngestResult, error) {
	r := domain.IngestResult{ExternalID: item.ExternalID}
	if strings.TrimSpace(*item.ExternalID) == "" {
		return r, domain.ErrValidation(field+".externalId", "externalId must not be empty")
	}
	if item.BoardID == nil {
		return r, domain.ErrValidation(field+".boardId", "boardId is required for items with an externalId")
	}
	if _, ok := st.boards[*item.BoardID]; !ok {
		return r, domain.ErrValidation(field+".boardId", "unknown board")
	}
	title, err := cleanName(field+".title", deref(item.Title), 255)
	if err != nil {
		return r, err
	}

	if c, ok := st.cardByExternal(src.id, *item.ExternalID); ok {
		return st.syncExisting(c, src, item, title, now)
	}

	parsed := domain.Parsed{
		Title: title, DueAt: item.DueAt, DueAllDay: item.DueAllDay, Uncertain: map[string]string{},
		SpecialTagID: st.specialTagByName(*item.BoardID, deref(item.SpecialTagName)),
		ExternalID:   item.ExternalID, URL: item.URL,
	}
	// Seen before as a duplicate: still waiting in the Inbox, or merged into a
	// card that already had its own external id (so cardByExternal can't find it).
	for _, prev := range st.inbox {
		if prev.Type != domain.InboxDuplicate || prev.Source != src.name ||
			prev.Parsed.ExternalID == nil || *prev.Parsed.ExternalID != *item.ExternalID {
			continue
		}
		switch prev.Status {
		case "pending":
			r.Result, r.InboxItemID, r.CardID = "inboxed", ptr(prev.ID), prev.CardID
			return r, nil
		case "merged":
			r.Result, r.CardID = "unchanged", prev.CardID
			return r, nil
		}
	}
	return st.createOrFlagDuplicate(src, *item.BoardID, title, parsed, now, loc, r)
}

// syncExisting updates sync fields on a card the source created earlier and
// raises Change items for a changed title or due date.
func (st *state) syncExisting(c card, src source, item domain.IngestItem, title string, now time.Time) (domain.IngestResult, error) {
	r := domain.IngestResult{ExternalID: item.ExternalID, CardID: ptr(c.id), Result: "unchanged"}
	if title != c.title {
		if id, raised := st.raiseChange(c, src, "title", ptr(c.title), ptr(title), now); raised {
			r.Result, r.InboxItemID = "inboxed", ptr(id)
		}
	}
	if !sameTime(item.DueAt, c.dueAt) {
		if id, raised := st.raiseChange(c, src, "dueAt", timeString(c.dueAt), timeString(item.DueAt), now); raised {
			if r.InboxItemID == nil {
				r.InboxItemID = ptr(id)
			}
			r.Result = "inboxed"
		}
	} else if item.DueAllDay != c.dueAllDay {
		c.dueAllDay = item.DueAllDay
		r.Result = "updated"
	}
	if item.URL != nil && (c.sourceURL == nil || *c.sourceURL != *item.URL) {
		c.sourceURL = item.URL
		if r.Result == "unchanged" {
			r.Result = "updated"
		}
	}
	c.lastSyncedAt = &now
	if r.Result == "updated" {
		c.updatedAt = now
	}
	st.cards[c.id] = c
	return r, nil
}

// raiseChange puts a change in the Inbox unless it's already there or the
// user ignored this exact value before. Reports whether an item is pending.
func (st *state) raiseChange(c card, src source, field string, oldV, newV *string, now time.Time) (int64, bool) {
	var latestIgnored *domain.InboxItem
	for _, item := range st.inbox {
		if item.Type != domain.InboxChange || deref(item.CardID) != c.id || item.Change.Field != field {
			continue
		}
		if item.Status == "pending" {
			if !sameString(item.Change.NewValue, newV) {
				item.Change = &domain.Change{Field: field, OldValue: oldV, NewValue: newV}
				item.ReceivedAt = now
				st.inbox[item.ID] = item
			}
			return item.ID, true
		}
		if item.Status == "ignored" && (latestIgnored == nil || item.ID > latestIgnored.ID) {
			latestIgnored = &item
		}
	}
	if latestIgnored != nil && sameString(latestIgnored.Change.NewValue, newV) {
		return 0, false
	}
	what := "title"
	if field == "dueAt" {
		what = "due date"
	}
	item := domain.InboxItem{
		ID: st.nextID("inbox"), Type: domain.InboxChange, Source: src.name, BoardID: ptr(c.boardID),
		RawText: c.title + " / " + what + " changed on the source site",
		Parsed: domain.Parsed{Title: c.title, SpecialTagID: c.specialTagID, DueAt: c.dueAt, DueAllDay: c.dueAllDay,
			Uncertain: map[string]string{}, ExternalID: c.externalID, URL: c.sourceURL},
		CardID: ptr(c.id), Change: &domain.Change{Field: field, OldValue: oldV, NewValue: newV},
		Status: "pending", ReceivedAt: now,
	}
	st.inbox[item.ID] = item
	return item.ID, true
}

// ingestVoice runs the classifier on a transcript.
func (st *state) ingestVoice(src source, item domain.IngestItem, field string, now time.Time, loc *time.Location) (domain.IngestResult, error) {
	r := domain.IngestResult{}
	raw := strings.TrimSpace(deref(item.RawText))
	if raw == "" {
		return r, domain.ErrValidation(field+".rawText", "rawText is required for items without an externalId")
	}
	v := classify.ParseVoice(raw, st.classifyBoards(), now, loc)
	parsed := domain.Parsed{Title: v.Title, SpecialTagID: v.SpecialTagID, DueAt: v.DueAt, DueAllDay: v.DueAllDay, Uncertain: v.Uncertain}
	if !v.Confident || v.BoardID == nil {
		inbox := domain.InboxItem{
			ID: st.nextID("inbox"), Type: domain.InboxVoice, Source: src.name, BoardID: v.BoardID,
			RawText: raw, Parsed: parsed, Status: "pending", ReceivedAt: now,
		}
		st.inbox[inbox.ID] = inbox
		r.Result, r.InboxItemID = "inboxed", ptr(inbox.ID)
		return r, nil
	}
	return st.createOrFlagDuplicate(src, *v.BoardID, v.Title, parsed, now, loc, r)
}

// createOrFlagDuplicate creates the card, or a Duplicate Inbox item when a
// card on the same board likely already covers it.
func (st *state) createOrFlagDuplicate(src source, boardID int64, rawText string, p domain.Parsed, now time.Time, loc *time.Location, r domain.IngestResult) (domain.IngestResult, error) {
	for _, c := range st.boardCards(boardID) {
		if c.archivedAt == nil && classify.SameTitle(c.title, p.Title) && classify.SameDay(c.dueAt, p.DueAt, loc) {
			item := domain.InboxItem{
				ID: st.nextID("inbox"), Type: domain.InboxDuplicate, Source: src.name, BoardID: ptr(boardID),
				RawText: rawText, Parsed: p, CardID: ptr(c.id), Status: "pending", ReceivedAt: now,
			}
			st.inbox[item.ID] = item
			r.Result, r.InboxItemID, r.CardID = "inboxed", ptr(item.ID), ptr(c.id)
			return r, nil
		}
	}
	c, err := st.insertCard(newCard{
		boardID: boardID, title: p.Title, dueAt: p.DueAt, dueAllDay: p.DueAllDay, specialTagID: p.SpecialTagID,
		sourceID: src.id, externalID: p.ExternalID, sourceURL: p.URL, synced: p.ExternalID != nil,
	}, now)
	if err != nil {
		return r, err
	}
	r.Result, r.CardID = "created", ptr(c.id)
	return r, nil
}

func (st *state) specialTagByName(boardID int64, name string) *int64 {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil
	}
	for _, t := range st.boardTags(boardID) {
		if t.isSpecial && strings.EqualFold(t.name, name) {
			return ptr(t.id)
		}
	}
	return nil
}

func (st *state) classifyBoards() []classify.Board {
	var out []classify.Board
	for _, b := range st.orderedBoards() {
		cb := classify.Board{ID: b.id, Name: b.name, TagLabel: b.tagLabel}
		for _, t := range st.boardTags(b.id) {
			if t.isSpecial {
				cb.SpecialTags = append(cb.SpecialTags, classify.Tag{ID: t.id, Name: t.name})
			}
		}
		out = append(out, cb)
	}
	return out
}

func (s *Store) ListSources() ([]domain.Source, error) {
	var out []domain.Source
	err := s.view(func(st *state, _ time.Time) error {
		var srcs []source
		for _, src := range st.sources {
			srcs = append(srcs, src)
		}
		sort.Slice(srcs, func(i, j int) bool { return srcs[i].id < srcs[j].id })
		out = []domain.Source{}
		for _, src := range srcs {
			out = append(out, toSource(src))
		}
		return nil
	})
	return out, err
}

func (s *Store) Heartbeat(name string, in domain.Heartbeat) (domain.Source, error) {
	var out domain.Source
	err := s.tx(func(st *state, now time.Time) error {
		src, ok := st.sourceByName(name)
		if !ok {
			return domain.ErrNotFound("source", name)
		}
		if !healths[in.Health] {
			return domain.ErrValidation("health", `health must be "ok", "needs_reauth", or "error"`)
		}
		src.health = in.Health
		src.statusMessage = in.Message
		if in.Health == "ok" {
			src.lastSyncAt = &now
		}
		st.sources[src.id] = src
		out = toSource(src)
		return nil
	})
	return out, err
}

func toSource(s source) domain.Source {
	return domain.Source{Name: s.name, Kind: s.kind, Health: s.health, StatusMessage: s.statusMessage, LastSyncAt: s.lastSyncAt}
}

func sameTime(a, b *time.Time) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return a.Equal(*b)
}

func sameString(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func timeString(t *time.Time) *string {
	if t == nil {
		return nil
	}
	return ptr(t.UTC().Format(time.RFC3339))
}
