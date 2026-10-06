package memory

import (
	"slices"
	"time"

	"notes-app/internal/domain"
)

func (st *state) checkTagName(boardID, exceptID int64, name string) error {
	for _, t := range st.boardTags(boardID) {
		if t.id != exceptID && t.name == name {
			return domain.ErrValidation("name", "a tag with that name already exists on this board")
		}
	}
	return nil
}

// checkColor allows the palette minus yellow, which is the Urgent tag's.
func checkColor(c string) error {
	if c == domain.UrgentColor {
		return domain.ErrValidation("color", "yellow is reserved for the Urgent tag")
	}
	if !domain.Colors[c] {
		return domain.ErrValidation("color", "color must be one of pink, blue, violet, cyan, orange")
	}
	return nil
}

// tagOrder is the board's tag ids by stored position (ignoring the
// special-first display order), which is what position updates edit.
func (st *state) tagOrder(boardID int64) []int64 {
	tags := st.boardTags(boardID)
	slices.SortStableFunc(tags, func(a, b tag) int {
		if a.position != b.position {
			return a.position - b.position
		}
		return int(a.id - b.id)
	})
	out := make([]int64, len(tags))
	for i, t := range tags {
		out[i] = t.id
	}
	return out
}

func (st *state) renumberTags(order []int64) {
	for i, id := range order {
		t := st.tags[id]
		t.position = i
		st.tags[id] = t
	}
}

func (s *Store) ListTags(boardID int64) ([]domain.Tag, error) {
	var out []domain.Tag
	err := s.view(func(st *state, _ time.Time) error {
		if _, err := st.board(boardID); err != nil {
			return err
		}
		out = []domain.Tag{}
		for _, t := range st.boardTags(boardID) {
			out = append(out, st.toTag(t))
		}
		return nil
	})
	return out, err
}

func (s *Store) CreateTag(boardID int64, in domain.TagCreate) (domain.Tag, error) {
	var out domain.Tag
	err := s.tx(func(st *state, _ time.Time) error {
		if _, err := st.board(boardID); err != nil {
			return err
		}
		name, err := cleanName("name", in.Name, 50)
		if err != nil {
			return err
		}
		if err := st.checkTagName(boardID, 0, name); err != nil {
			return err
		}
		if err := checkColor(in.Color); err != nil {
			return err
		}
		t := tag{id: st.nextID("tags"), boardID: boardID, name: name, color: in.Color,
			isSpecial: deref(in.IsSpecial), position: len(st.boardTags(boardID))}
		st.tags[t.id] = t
		out = st.toTag(t)
		return nil
	})
	return out, err
}

func (s *Store) UpdateTag(tagID int64, in domain.TagPatch) (domain.Tag, error) {
	var out domain.Tag
	err := s.tx(func(st *state, now time.Time) error {
		t, err := st.tag(tagID)
		if err != nil {
			return err
		}
		if in.Name.Set {
			name, err := cleanName("name", deref(in.Name.Value), 50)
			if err != nil {
				return err
			}
			if err := st.checkTagName(t.boardID, t.id, name); err != nil {
				return err
			}
			t.name = name
		}
		if in.Color.Set && t.systemKey != nil && deref(in.Color.Value) != t.color {
			return domain.ErrSystemTag("the Urgent tag's color can't be changed")
		}
		if in.Color.Set && t.systemKey == nil {
			if err := checkColor(deref(in.Color.Value)); err != nil {
				return err
			}
			t.color = *in.Color.Value
		}
		if in.IsSpecial.Set {
			if in.IsSpecial.Value == nil {
				return domain.ErrValidation("isSpecial", "isSpecial must be true or false")
			}
			want := *in.IsSpecial.Value
			if want && t.systemKey != nil {
				return domain.ErrSystemTag("the Urgent tag can't be made special")
			}
			if want != t.isSpecial {
				st.convertTagUses(t, want, now)
				t.isSpecial = want
			}
		}
		st.tags[t.id] = t
		if in.Position.Set {
			if in.Position.Value == nil || *in.Position.Value < 0 {
				return domain.ErrValidation("position", "position must be a non-negative number")
			}
			st.renumberTags(moveTo(st.tagOrder(t.boardID), t.id, *in.Position.Value))
		}
		out = st.toTag(st.tags[t.id])
		return nil
	})
	return out, err
}

// convertTagUses keeps every card's label when a tag's isSpecial flips.
// Special → regular: cards using it as their special tag get it as a regular
// tag instead. Regular → special: cards carrying it as a regular tag take it
// as their special tag if they have none; the rest keep it as a regular tag.
func (st *state) convertTagUses(t tag, toSpecial bool, now time.Time) {
	for id, c := range st.cards {
		if c.boardID != t.boardID {
			continue
		}
		changed := false
		if !toSpecial && c.specialTagID != nil && *c.specialTagID == t.id {
			c.specialTagID = nil
			if !slices.Contains(c.tagIDs, t.id) {
				c.tagIDs = append(slices.Clone(c.tagIDs), t.id)
			}
			changed = true
		}
		if toSpecial && c.specialTagID == nil && slices.Contains(c.tagIDs, t.id) {
			c.specialTagID = ptr(t.id)
			c.tagIDs = slices.DeleteFunc(slices.Clone(c.tagIDs), func(x int64) bool { return x == t.id })
			changed = true
		}
		if changed {
			c.updatedAt = now
			st.cards[id] = c
		}
	}
}

func (s *Store) DeleteTag(tagID int64) error {
	return s.tx(func(st *state, now time.Time) error {
		t, err := st.tag(tagID)
		if err != nil {
			return err
		}
		if t.systemKey != nil {
			return domain.ErrSystemTag("the Urgent tag can't be deleted")
		}
		for id, c := range st.cards {
			changed := false
			if c.specialTagID != nil && *c.specialTagID == t.id {
				c.specialTagID = nil
				changed = true
			}
			if slices.Contains(c.tagIDs, t.id) {
				c.tagIDs = slices.DeleteFunc(slices.Clone(c.tagIDs), func(x int64) bool { return x == t.id })
				changed = true
			}
			if changed {
				c.updatedAt = now
				st.cards[id] = c
			}
		}
		delete(st.tags, t.id)
		st.renumberTags(st.tagOrder(t.boardID))
		return nil
	})
}
