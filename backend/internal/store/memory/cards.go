package memory

import (
	"slices"
	"sort"
	"strings"
	"time"

	"notes-app/internal/domain"
)

func (s *Store) ListCards(boardID int64, q domain.CardQuery) ([]domain.CardSummary, error) {
	var out []domain.CardSummary
	err := s.view(func(st *state, _ time.Time) error {
		if _, err := st.board(boardID); err != nil {
			return err
		}
		var cards []card
		for _, c := range st.boardCards(boardID) {
			if q.ListID != nil && c.listID != *q.ListID {
				continue
			}
			if !q.Archived && c.archivedAt != nil {
				continue
			}
			if q.DueFrom != nil || q.DueTo != nil {
				if c.dueAt == nil ||
					(q.DueFrom != nil && c.dueAt.Before(*q.DueFrom)) ||
					(q.DueTo != nil && !c.dueAt.Before(*q.DueTo)) {
					continue
				}
			}
			cards = append(cards, c)
		}
		sort.SliceStable(cards, func(i, j int) bool {
			a, b := cards[i], cards[j]
			if pa, pb := st.lists[a.listID].position, st.lists[b.listID].position; pa != pb {
				return pa < pb
			}
			switch q.Sort {
			case domain.SortPosition:
				if a.position != b.position {
					return a.position < b.position
				}
			case domain.SortCreated:
				if !a.createdAt.Equal(b.createdAt) {
					return a.createdAt.Before(b.createdAt)
				}
			case domain.SortTitle:
				if ta, tb := strings.ToLower(a.title), strings.ToLower(b.title); ta != tb {
					return ta < tb
				}
			default: // due; no due date sorts last
				switch {
				case a.dueAt == nil && b.dueAt != nil:
					return false
				case a.dueAt != nil && b.dueAt == nil:
					return true
				case a.dueAt != nil && !a.dueAt.Equal(*b.dueAt):
					return a.dueAt.Before(*b.dueAt)
				}
			}
			return a.id < b.id
		})
		out = []domain.CardSummary{}
		for _, c := range cards {
			out = append(out, toSummary(c))
		}
		return nil
	})
	return out, err
}

// newCard is everything needed to create a card; shared by manual create,
// ingest, and Inbox accept.
type newCard struct {
	boardID      int64
	listID       *int64 // nil = first open list
	title        string
	dueAt        *time.Time
	dueAllDay    bool
	specialTagID *int64
	tagIDs       []int64
	sourceID     int64
	externalID   *string
	sourceURL    *string
	synced       bool
}

func (st *state) insertCard(in newCard, now time.Time) (card, error) {
	if _, err := st.board(in.boardID); err != nil {
		return card{}, err
	}
	title, err := cleanName("title", in.title, 255)
	if err != nil {
		return card{}, err
	}
	var l list
	if in.listID != nil {
		if l, err = st.listOnBoard(in.boardID, *in.listID, "listId"); err != nil {
			return card{}, err
		}
	} else {
		l, _ = st.firstList(in.boardID, domain.KindOpen)
	}
	if in.specialTagID != nil {
		if err := st.checkSpecialTag(in.boardID, *in.specialTagID); err != nil {
			return card{}, err
		}
	}
	tagIDs, err := st.checkRegularTags(in.boardID, in.tagIDs)
	if err != nil {
		return card{}, err
	}
	c := card{
		id: st.nextID("cards"), boardID: in.boardID, title: title, dueAt: in.dueAt, dueAllDay: in.dueAllDay,
		specialTagID: in.specialTagID, tagIDs: tagIDs, notes: []domain.NoteBlock{}, sourceID: in.sourceID,
		externalID: in.externalID, sourceURL: in.sourceURL, createdAt: now, updatedAt: now,
	}
	if in.synced {
		c.lastSyncedAt = &now
	}
	return st.moveCard(c, l, nil, now), nil // new cards go to the end of the list
}

func (st *state) manualSourceID() int64 {
	src, _ := st.sourceByName("manual")
	return src.id
}

func (s *Store) CreateCard(boardID int64, in domain.CardCreate) (domain.Card, error) {
	var out domain.Card
	err := s.tx(func(st *state, now time.Time) error {
		c, err := st.insertCard(newCard{
			boardID: boardID, listID: in.ListID, title: in.Title, dueAt: in.DueAt, dueAllDay: deref(in.DueAllDay),
			specialTagID: in.SpecialTagID, tagIDs: in.TagIDs, sourceID: st.manualSourceID(),
		}, now)
		if err != nil {
			return err
		}
		out = st.toCard(c)
		return nil
	})
	return out, err
}

func (s *Store) GetCard(cardID int64) (domain.Card, error) {
	var out domain.Card
	err := s.view(func(st *state, _ time.Time) error {
		c, err := st.card(cardID)
		if err != nil {
			return err
		}
		out = st.toCard(c)
		return nil
	})
	return out, err
}

func (s *Store) UpdateCard(cardID int64, in domain.CardPatch) (domain.Card, error) {
	var out domain.Card
	err := s.tx(func(st *state, now time.Time) error {
		c, err := st.card(cardID)
		if err != nil {
			return err
		}
		if in.Title.Set {
			if c.title, err = cleanName("title", deref(in.Title.Value), 255); err != nil {
				return err
			}
		}
		if in.ListID.Set || in.Position.Set {
			target := st.lists[c.listID]
			if in.ListID.Set {
				if in.ListID.Value == nil {
					return domain.ErrValidation("listId", "listId can't be null")
				}
				if target, err = st.listOnBoard(c.boardID, *in.ListID.Value, "listId"); err != nil {
					return err
				}
			}
			if in.Position.Set && (in.Position.Value == nil || *in.Position.Value < 0) {
				return domain.ErrValidation("position", "position must be a non-negative number")
			}
			// Without a position, a card moving lists goes to the end of the new one.
			if in.Position.Set || target.id != c.listID {
				c = st.moveCard(c, target, in.Position.Value, now)
			}
		}
		if in.DueAt.Set {
			c.dueAt = in.DueAt.Value
		}
		if in.DueAllDay.Set {
			c.dueAllDay = deref(in.DueAllDay.Value)
		}
		if in.SpecialTagID.Set {
			if in.SpecialTagID.Value != nil {
				if err := st.checkSpecialTag(c.boardID, *in.SpecialTagID.Value); err != nil {
					return err
				}
			}
			c.specialTagID = in.SpecialTagID.Value
		}
		if in.TagIDs.Set {
			if c.tagIDs, err = st.checkRegularTags(c.boardID, deref(in.TagIDs.Value)); err != nil {
				return err
			}
		}
		if in.Archived.Set {
			if in.Archived.Value == nil {
				return domain.ErrValidation("archived", "archived must be true or false")
			}
			if *in.Archived.Value && c.archivedAt == nil {
				c.archivedAt = &now
			} else if !*in.Archived.Value {
				c.archivedAt = nil
			}
		}
		c.updatedAt = now
		st.cards[c.id] = c
		out = st.toCard(c)
		return nil
	})
	return out, err
}

func (s *Store) MarkDone(cardID int64) (domain.Card, error) {
	var out domain.Card
	err := s.tx(func(st *state, now time.Time) error {
		c, err := st.card(cardID)
		if err != nil {
			return err
		}
		done, _ := st.firstList(c.boardID, domain.KindDone)
		if c.listID != done.id {
			c = st.moveCard(c, done, nil, now)
			c.updatedAt = now
			st.cards[c.id] = c
		}
		out = st.toCard(c)
		return nil
	})
	return out, err
}

// deleteCard removes a card and, like the schema's cascade, the Inbox items
// that point at it.
func (st *state) deleteCard(id int64) {
	delete(st.cards, id)
	for itemID, item := range st.inbox {
		if item.CardID != nil && *item.CardID == id {
			delete(st.inbox, itemID)
		}
	}
}

func (s *Store) DeleteCard(cardID int64) error {
	return s.tx(func(st *state, _ time.Time) error {
		if _, err := st.card(cardID); err != nil {
			return err
		}
		st.deleteCard(cardID)
		return nil
	})
}

func (s *Store) SaveNotes(cardID int64, blocks []domain.NoteBlock) (domain.NotesResult, error) {
	var out domain.NotesResult
	err := s.tx(func(st *state, now time.Time) error {
		c, err := st.card(cardID)
		if err != nil {
			return err
		}
		if blocks == nil {
			return domain.ErrValidation("blocks", "blocks is required; send [] to clear the notes")
		}
		if err := domain.ValidateBlocks(blocks); err != nil {
			return err
		}
		c.notes = slices.Clone(blocks)
		c.updatedAt = now
		st.cards[c.id] = c
		out = domain.NotesResult{Blocks: slices.Clone(blocks), UpdatedAt: now}
		return nil
	})
	return out, err
}

func (s *Store) MoveCards(in domain.CardMove) ([]domain.CardSummary, error) {
	var out []domain.CardSummary
	err := s.tx(func(st *state, now time.Time) error {
		var err error
		out, err = st.moveCards(in, now)
		return err
	})
	return out, err
}

// moveCards moves cards to another board: lists map by name, falling back to
// the target's first list of the same kind; all tags are dropped, then
// applyTagIds (tags on the target board) are added.
func (st *state) moveCards(in domain.CardMove, now time.Time) ([]domain.CardSummary, error) {
	if _, err := st.board(in.ToBoardID); err != nil {
		return nil, domain.ErrValidation("toBoardId", "unknown board")
	}
	if len(in.CardIDs) == 0 {
		return nil, domain.ErrValidation("cardIds", "cardIds must not be empty")
	}
	var special *int64
	var regular []int64
	for _, id := range in.ApplyTagIDs {
		t, err := st.tagOnBoard(in.ToBoardID, id, "applyTagIds")
		if err != nil {
			return nil, err
		}
		if t.isSpecial {
			if special != nil && *special != id {
				return nil, domain.ErrValidation("applyTagIds", "at most one special tag can be applied")
			}
			special = ptr(id)
		} else if !slices.Contains(regular, id) {
			regular = append(regular, id)
		}
	}
	targetLists := st.boardLists(in.ToBoardID)
	out := []domain.CardSummary{}
	seen := map[int64]bool{}
	for _, id := range in.CardIDs {
		if seen[id] {
			return nil, domain.ErrValidation("cardIds", "cardIds must not repeat")
		}
		seen[id] = true
		c, ok := st.cards[id]
		if !ok {
			return nil, domain.ErrValidation("cardIds", "unknown card")
		}
		if c.boardID == in.ToBoardID {
			return nil, domain.ErrValidation("cardIds", "card is already on the target board")
		}
		from := st.lists[c.listID]
		target, found := list{}, false
		for _, l := range targetLists {
			if l.name == from.name {
				target, found = l, true
				break
			}
		}
		if !found {
			target, _ = st.firstList(in.ToBoardID, from.kind)
		}
		c.boardID = in.ToBoardID
		c.specialTagID = special
		c.tagIDs = slices.Clone(regular)
		c.updatedAt = now
		c = st.moveCard(c, target, nil, now)
		out = append(out, toSummary(c))
	}
	return out, nil
}
