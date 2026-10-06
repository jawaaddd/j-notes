package memory

import (
	"slices"
	"time"

	"notes-app/internal/domain"
)

func (st *state) renumberLists(order []int64) {
	for i, id := range order {
		l := st.lists[id]
		l.position = i
		st.lists[id] = l
	}
}

func listIDs(ls []list) []int64 {
	out := make([]int64, len(ls))
	for i, l := range ls {
		out[i] = l.id
	}
	return out
}

func (st *state) checkListName(boardID, exceptID int64, name string) error {
	for _, l := range st.boardLists(boardID) {
		if l.id != exceptID && l.name == name {
			return domain.ErrValidation("name", "a list with that name already exists on this board")
		}
	}
	return nil
}

// checkKeepsKind fails if removing (or re-kinding) l would leave its board
// without a list of l's kind.
func (st *state) checkKeepsKind(l list) error {
	for _, other := range st.boardLists(l.boardID) {
		if other.id != l.id && other.kind == l.kind {
			return nil
		}
	}
	return domain.ErrLastOfKind(l.kind)
}

func validKind(k domain.ListKind) bool { return k == domain.KindOpen || k == domain.KindDone }

func (s *Store) ListLists(boardID int64) ([]domain.List, error) {
	var out []domain.List
	err := s.view(func(st *state, _ time.Time) error {
		if _, err := st.board(boardID); err != nil {
			return err
		}
		out = []domain.List{}
		for _, l := range st.boardLists(boardID) {
			out = append(out, st.toList(l))
		}
		return nil
	})
	return out, err
}

func (s *Store) CreateList(boardID int64, in domain.ListCreate) (domain.List, error) {
	var out domain.List
	err := s.tx(func(st *state, _ time.Time) error {
		if _, err := st.board(boardID); err != nil {
			return err
		}
		name, err := cleanName("name", in.Name, 50)
		if err != nil {
			return err
		}
		if err := st.checkListName(boardID, 0, name); err != nil {
			return err
		}
		kind := domain.KindOpen
		if in.Kind != nil {
			if !validKind(*in.Kind) {
				return domain.ErrValidation("kind", `kind must be "open" or "done"`)
			}
			kind = *in.Kind
		}
		order := listIDs(st.boardLists(boardID))
		pos := len(order)
		if in.Position != nil {
			if *in.Position < 0 {
				return domain.ErrValidation("position", "position must be a non-negative number")
			}
			pos = *in.Position
		}
		l := list{id: st.nextID("lists"), boardID: boardID, name: name, kind: kind}
		st.lists[l.id] = l
		st.renumberLists(moveTo(order, l.id, pos))
		out = st.toList(st.lists[l.id])
		return nil
	})
	return out, err
}

func (s *Store) UpdateList(listID int64, in domain.ListPatch) (domain.List, error) {
	var out domain.List
	err := s.tx(func(st *state, now time.Time) error {
		l, err := st.list(listID)
		if err != nil {
			return err
		}
		if in.Name.Set {
			name, err := cleanName("name", deref(in.Name.Value), 50)
			if err != nil {
				return err
			}
			if err := st.checkListName(l.boardID, l.id, name); err != nil {
				return err
			}
			l.name = name
		}
		if in.Kind.Set {
			kind := deref(in.Kind.Value)
			if !validKind(kind) {
				return domain.ErrValidation("kind", `kind must be "open" or "done"`)
			}
			if kind != l.kind {
				if err := st.checkKeepsKind(l); err != nil {
					return err
				}
				l.kind = kind
				// Cards follow their list's new kind.
				for id, c := range st.cards {
					if c.listID == l.id {
						placeCard(&c, l, now)
						c.updatedAt = now
						st.cards[id] = c
					}
				}
			}
		}
		st.lists[l.id] = l
		out = st.toList(l)
		return nil
	})
	return out, err
}

func (s *Store) ReorderLists(boardID int64, ids []int64) ([]domain.List, error) {
	var out []domain.List
	err := s.tx(func(st *state, _ time.Time) error {
		if _, err := st.board(boardID); err != nil {
			return err
		}
		current := listIDs(st.boardLists(boardID))
		a, b := slices.Clone(ids), slices.Clone(current)
		slices.Sort(a)
		slices.Sort(b)
		if !slices.Equal(a, b) {
			return domain.ErrValidation("listIds", "listIds must contain every list on the board exactly once")
		}
		st.renumberLists(ids)
		out = []domain.List{}
		for _, l := range st.boardLists(boardID) {
			out = append(out, st.toList(l))
		}
		return nil
	})
	return out, err
}

func (s *Store) DeleteList(listID int64, in domain.ListDelete) error {
	return s.tx(func(st *state, now time.Time) error {
		l, err := st.list(listID)
		if err != nil {
			return err
		}
		if err := st.checkKeepsKind(l); err != nil {
			return err
		}
		var inList []card
		for _, c := range st.cards {
			if c.listID == l.id {
				inList = append(inList, c)
			}
		}
		if len(inList) > 0 {
			if in.MoveToListID == nil {
				return domain.ErrListHasCards(len(inList))
			}
			if *in.MoveToListID == l.id {
				return domain.ErrValidation("moveToListId", "can't move cards into the list being deleted")
			}
			target, err := st.listOnBoard(l.boardID, *in.MoveToListID, "moveToListId")
			if err != nil {
				return err
			}
			for _, c := range inList {
				placeCard(&c, target, now)
				c.updatedAt = now
				st.cards[c.id] = c
			}
		}
		delete(st.lists, l.id)
		st.renumberLists(listIDs(st.boardLists(l.boardID)))
		return nil
	})
}
