package memory

import (
	"sort"
	"time"

	"notes-app/internal/domain"
)

func (st *state) orderedBoards() []board {
	out := make([]board, 0, len(st.boards))
	for _, b := range st.boards {
		out = append(out, b)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].position != out[j].position {
			return out[i].position < out[j].position
		}
		return out[i].id < out[j].id
	})
	return out
}

func (st *state) renumberBoards(order []int64) {
	for i, id := range order {
		b := st.boards[id]
		b.position = i
		st.boards[id] = b
	}
}

func (s *Store) ListBoards() ([]domain.Board, error) {
	var out []domain.Board
	err := s.view(func(st *state, now time.Time) error {
		out = []domain.Board{}
		for _, b := range st.orderedBoards() {
			out = append(out, st.toBoard(b, now))
		}
		return nil
	})
	return out, err
}

func (s *Store) CreateBoard(in domain.BoardCreate) (domain.Board, error) {
	var out domain.Board
	err := s.tx(func(st *state, now time.Time) error {
		b, err := st.insertBoard(in, now)
		if err != nil {
			return err
		}
		out = st.toBoard(b, now)
		return nil
	})
	return out, err
}

// insertBoard creates a board with its default lists and Urgent tag.
func (st *state) insertBoard(in domain.BoardCreate, now time.Time) (board, error) {
	name, err := cleanName("name", in.Name, 100)
	if err != nil {
		return board{}, err
	}
	b := board{id: st.nextID("boards"), name: name, itemNoun: "Cards", tagLabel: "Tags",
		position: len(st.boards), createdAt: now, updatedAt: now}
	if in.ItemNoun != nil {
		if b.itemNoun, err = cleanName("itemNoun", *in.ItemNoun, 50); err != nil {
			return board{}, err
		}
	}
	if in.SpecialTagLabel != nil {
		if b.tagLabel, err = cleanName("specialTagLabel", *in.SpecialTagLabel, 50); err != nil {
			return board{}, err
		}
	}
	st.boards[b.id] = b
	for i, def := range []struct {
		name string
		kind domain.ListKind
	}{{"To Do", domain.KindOpen}, {"In Progress", domain.KindOpen}, {"Done", domain.KindDone}} {
		id := st.nextID("lists")
		st.lists[id] = list{id: id, boardID: b.id, name: def.name, kind: def.kind, position: i}
	}
	id := st.nextID("tags")
	st.tags[id] = tag{id: id, boardID: b.id, name: "Urgent", color: domain.UrgentColor, systemKey: ptr(domain.UrgentKey)}
	return b, nil
}

func (s *Store) GetBoardDetail(boardID int64) (domain.BoardDetail, error) {
	var out domain.BoardDetail
	err := s.view(func(st *state, now time.Time) error {
		b, err := st.board(boardID)
		if err != nil {
			return err
		}
		out = domain.BoardDetail{Board: st.toBoard(b, now), Lists: []domain.List{}, Tags: []domain.Tag{}}
		for _, l := range st.boardLists(boardID) {
			out.Lists = append(out.Lists, st.toList(l))
		}
		for _, t := range st.boardTags(boardID) {
			out.Tags = append(out.Tags, st.toTag(t))
		}
		return nil
	})
	return out, err
}

func (s *Store) UpdateBoard(boardID int64, in domain.BoardPatch) (domain.Board, error) {
	var out domain.Board
	err := s.tx(func(st *state, now time.Time) error {
		b, err := st.board(boardID)
		if err != nil {
			return err
		}
		if in.Name.Set {
			if b.name, err = cleanName("name", deref(in.Name.Value), 100); err != nil {
				return err
			}
		}
		if in.ItemNoun.Set {
			if b.itemNoun, err = cleanName("itemNoun", deref(in.ItemNoun.Value), 50); err != nil {
				return err
			}
		}
		if in.SpecialTagLabel.Set {
			if b.tagLabel, err = cleanName("specialTagLabel", deref(in.SpecialTagLabel.Value), 50); err != nil {
				return err
			}
		}
		b.updatedAt = now
		st.boards[boardID] = b
		if in.Position.Set {
			if in.Position.Value == nil || *in.Position.Value < 0 {
				return domain.ErrValidation("position", "position must be a non-negative number")
			}
			var order []int64
			for _, ob := range st.orderedBoards() {
				order = append(order, ob.id)
			}
			st.renumberBoards(moveTo(order, boardID, *in.Position.Value))
		}
		out = st.toBoard(st.boards[boardID], now)
		return nil
	})
	return out, err
}

func (s *Store) DeleteBoard(boardID int64, in domain.BoardDelete) error {
	return s.tx(func(st *state, now time.Time) error {
		if _, err := st.board(boardID); err != nil {
			return err
		}
		if len(st.boards) == 1 {
			return domain.ErrLastBoard()
		}
		cards := st.boardCards(boardID)
		if len(cards) > 0 {
			if in.Cards == nil {
				return domain.ErrBoardHasCards(len(cards))
			}
			switch *in.Cards {
			case "delete":
				// Cards first: they reference the board's lists and tags.
				for _, c := range cards {
					st.deleteCard(c.id)
				}
			case "move":
				if in.ToBoardID == nil {
					return domain.ErrValidation("toBoardId", "toBoardId is required to move cards")
				}
				if *in.ToBoardID == boardID {
					return domain.ErrValidation("toBoardId", "can't move cards to the board being deleted")
				}
				ids := make([]int64, len(cards))
				for i, c := range cards {
					ids[i] = c.id
				}
				if _, err := st.moveCards(domain.CardMove{CardIDs: ids, ToBoardID: *in.ToBoardID, ApplyTagIDs: in.ApplyTagIDs}, now); err != nil {
					return err
				}
			default:
				return domain.ErrValidation("cards", `cards must be "delete" or "move"`)
			}
		}
		for id, l := range st.lists {
			if l.boardID == boardID {
				delete(st.lists, id)
			}
		}
		for id, t := range st.tags {
			if t.boardID == boardID {
				delete(st.tags, id)
			}
		}
		for id, item := range st.inbox {
			if item.BoardID != nil && *item.BoardID == boardID {
				item.BoardID = nil
				st.inbox[id] = item
			}
		}
		delete(st.boards, boardID)
		var order []int64
		for _, b := range st.orderedBoards() {
			order = append(order, b.id)
		}
		st.renumberBoards(order)
		return nil
	})
}

func deref[T any](p *T) T {
	var zero T
	if p == nil {
		return zero
	}
	return *p
}
