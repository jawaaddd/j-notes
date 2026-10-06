package memory

import (
	"sort"
	"time"

	"notes-app/internal/domain"
)

func (s *Store) ListInbox(typ *domain.InboxType) (domain.InboxList, error) {
	var out domain.InboxList
	err := s.view(func(st *state, _ time.Time) error {
		out = domain.InboxList{Items: []domain.InboxItem{}}
		for _, item := range st.pendingInbox() {
			out.Counts.All++
			switch item.Type {
			case domain.InboxVoice:
				out.Counts.Voice++
			case domain.InboxChange:
				out.Counts.Change++
			case domain.InboxDuplicate:
				out.Counts.Duplicate++
			}
			if typ == nil || item.Type == *typ {
				out.Items = append(out.Items, cloneItem(item))
			}
		}
		return nil
	})
	return out, err
}

// pendingInbox returns pending items, newest first.
func (st *state) pendingInbox() []domain.InboxItem {
	var out []domain.InboxItem
	for _, item := range st.inbox {
		if item.Status == "pending" {
			out = append(out, item)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if !out[i].ReceivedAt.Equal(out[j].ReceivedAt) {
			return out[i].ReceivedAt.After(out[j].ReceivedAt)
		}
		return out[i].ID > out[j].ID
	})
	return out
}

// cloneItem copies the item's map so callers can't reach into the store.
func cloneItem(item domain.InboxItem) domain.InboxItem {
	u := make(map[string]string, len(item.Parsed.Uncertain))
	for k, v := range item.Parsed.Uncertain {
		u[k] = v
	}
	item.Parsed.Uncertain = u
	return item
}

func (s *Store) ResolveInbox(itemID int64, in domain.InboxResolve) (domain.InboxResolution, error) {
	var out domain.InboxResolution
	err := s.tx(func(st *state, now time.Time) error {
		item, ok := st.inbox[itemID]
		if !ok {
			return domain.ErrNotFound("inbox item", itemID)
		}
		if item.Status != "pending" {
			return domain.ErrInvalidAction("this item was already resolved")
		}
		var (
			status string
			c      *card
			err    error
		)
		switch {
		case item.Type == domain.InboxVoice && in.Action == "accept":
			status = "accepted"
			c, err = st.acceptVoice(item, in.Edits, now)
		case item.Type == domain.InboxVoice && in.Action == "discard":
			status = "discarded"
		case item.Type == domain.InboxChange && in.Action == "accept":
			status = "accepted"
			c, err = st.applyChange(item, now)
		case item.Type == domain.InboxChange && in.Action == "ignore":
			status = "ignored"
		case item.Type == domain.InboxDuplicate && in.Action == "merge":
			status = "merged"
			c, err = st.mergeDuplicate(item, now)
		case item.Type == domain.InboxDuplicate && in.Action == "keep_both":
			status = "kept_both"
			c, err = st.keepBoth(item, now)
		default:
			return domain.ErrInvalidAction(`action "` + in.Action + `" doesn't apply to a ` + string(item.Type) + " item")
		}
		if err != nil {
			return err
		}
		item.Status = status
		item.ResolvedAt = &now
		st.inbox[item.ID] = item
		out = domain.InboxResolution{Item: cloneItem(item)}
		if c != nil {
			full := st.toCard(*c)
			out.Card = &full
		}
		return nil
	})
	return out, err
}

func (st *state) sourceIDOf(item domain.InboxItem) int64 {
	src, _ := st.sourceByName(item.Source)
	return src.id
}

func (st *state) acceptVoice(item domain.InboxItem, edits *domain.InboxEdits, now time.Time) (*card, error) {
	p := item.Parsed
	boardID := item.BoardID
	specialTagID := p.SpecialTagID
	dueAt, dueAllDay := p.DueAt, p.DueAllDay
	title := p.Title
	if edits != nil {
		if edits.Title.Set {
			title = deref(edits.Title.Value)
		}
		if edits.BoardID.Set {
			boardID = edits.BoardID.Value
			// A guessed special tag from another board doesn't follow the card.
			if !edits.SpecialTagID.Set && specialTagID != nil && boardID != nil {
				if t, ok := st.tags[*specialTagID]; !ok || t.boardID != *boardID {
					specialTagID = nil
				}
			}
		}
		if edits.SpecialTagID.Set {
			specialTagID = edits.SpecialTagID.Value
		}
		if edits.DueAt.Set {
			dueAt = edits.DueAt.Value
		}
		if edits.DueAllDay.Set {
			dueAllDay = deref(edits.DueAllDay.Value)
		}
	}
	if boardID == nil {
		return nil, domain.ErrValidation("boardId", "pick a board for this entry before accepting it")
	}
	if _, ok := st.boards[*boardID]; !ok {
		return nil, domain.ErrValidation("boardId", "unknown board")
	}
	c, err := st.insertCard(newCard{
		boardID: *boardID, title: title, dueAt: dueAt, dueAllDay: dueAllDay, specialTagID: specialTagID,
		sourceID: st.sourceIDOf(item), externalID: p.ExternalID, sourceURL: p.URL,
	}, now)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (st *state) applyChange(item domain.InboxItem, now time.Time) (*card, error) {
	c, err := st.card(deref(item.CardID))
	if err != nil {
		return nil, err
	}
	switch item.Change.Field {
	case "title":
		if c.title, err = cleanName("title", deref(item.Change.NewValue), 255); err != nil {
			return nil, err
		}
	case "dueAt":
		c.dueAt = nil
		if item.Change.NewValue != nil {
			t, err := time.Parse(time.RFC3339, *item.Change.NewValue)
			if err != nil {
				return nil, domain.ErrValidation("change.newValue", "stored due date is not a valid timestamp")
			}
			c.dueAt = &t
		}
	}
	c.lastSyncedAt = &now
	c.updatedAt = now
	st.cards[c.id] = c
	return &c, nil
}

// mergeDuplicate fills the existing card's empty fields from the new entry,
// never overwriting. A card with no external id adopts the entry's source and
// external id, so the next scraper run recognizes it instead of raising the
// same duplicate again.
func (st *state) mergeDuplicate(item domain.InboxItem, now time.Time) (*card, error) {
	c, err := st.card(deref(item.CardID))
	if err != nil {
		return nil, err
	}
	p := item.Parsed
	if c.dueAt == nil && p.DueAt != nil {
		c.dueAt, c.dueAllDay = p.DueAt, p.DueAllDay
	}
	if c.specialTagID == nil && p.SpecialTagID != nil && st.checkSpecialTag(c.boardID, *p.SpecialTagID) == nil {
		c.specialTagID = p.SpecialTagID
	}
	if c.externalID == nil && p.ExternalID != nil {
		srcID := st.sourceIDOf(item)
		if _, taken := st.cardByExternal(srcID, *p.ExternalID); !taken {
			c.sourceID, c.externalID = srcID, p.ExternalID
			c.lastSyncedAt = &now
		}
	}
	if c.sourceURL == nil && p.URL != nil {
		c.sourceURL = p.URL
	}
	c.updatedAt = now
	st.cards[c.id] = c
	return &c, nil
}

func (st *state) keepBoth(item domain.InboxItem, now time.Time) (*card, error) {
	boardID := item.BoardID
	if boardID == nil {
		if existing, ok := st.cards[deref(item.CardID)]; ok {
			boardID = &existing.boardID
		}
	}
	if boardID == nil {
		return nil, domain.ErrValidation("boardId", "this entry has no board")
	}
	p := item.Parsed
	c, err := st.insertCard(newCard{
		boardID: *boardID, title: p.Title, dueAt: p.DueAt, dueAllDay: p.DueAllDay, specialTagID: p.SpecialTagID,
		sourceID: st.sourceIDOf(item), externalID: p.ExternalID, sourceURL: p.URL, synced: p.ExternalID != nil,
	}, now)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (st *state) cardByExternal(sourceID int64, externalID string) (card, bool) {
	for _, c := range st.cards {
		if c.sourceID == sourceID && c.externalID != nil && *c.externalID == externalID {
			return c, true
		}
	}
	return card{}, false
}
