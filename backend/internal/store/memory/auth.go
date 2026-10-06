package memory

import (
	"sort"
	"time"

	"notes-app/internal/domain"
)

func (s *Store) PasswordHash() (string, bool, error) {
	var hash string
	err := s.view(func(st *state, _ time.Time) error {
		hash = st.passwordHash
		return nil
	})
	return hash, hash != "", err
}

func (s *Store) SetPasswordHash(hash string) error {
	return s.tx(func(st *state, _ time.Time) error {
		st.passwordHash = hash
		return nil
	})
}

func (s *Store) CreateToken(t domain.AuthToken) (domain.AuthToken, error) {
	err := s.tx(func(st *state, _ time.Time) error {
		t.ID = st.nextID("tokens")
		t.Current = false
		st.tokens[t.ID] = t
		return nil
	})
	return t, err
}

func (s *Store) TokenByHash(hash [32]byte) (domain.AuthToken, bool, error) {
	var (
		out   domain.AuthToken
		found bool
	)
	err := s.view(func(st *state, _ time.Time) error {
		for _, t := range st.tokens {
			if t.Hash == hash {
				out, found = t, true
				return nil
			}
		}
		return nil
	})
	return out, found, err
}

func (s *Store) TouchToken(id int64, lastUsedAt time.Time, expiresAt *time.Time) error {
	return s.tx(func(st *state, _ time.Time) error {
		t, ok := st.tokens[id]
		if !ok {
			return domain.ErrNotFound("token", id)
		}
		t.LastUsedAt, t.ExpiresAt = &lastUsedAt, expiresAt
		st.tokens[id] = t
		return nil
	})
}

func (s *Store) ListTokens() ([]domain.AuthToken, error) {
	var out []domain.AuthToken
	err := s.view(func(st *state, _ time.Time) error {
		out = []domain.AuthToken{}
		for _, t := range st.tokens {
			out = append(out, t)
		}
		sort.Slice(out, func(i, j int) bool { return out[i].ID > out[j].ID })
		return nil
	})
	return out, err
}

func (s *Store) DeleteToken(id int64) error {
	return s.tx(func(st *state, _ time.Time) error {
		if _, ok := st.tokens[id]; !ok {
			return domain.ErrNotFound("token", id)
		}
		delete(st.tokens, id)
		return nil
	})
}

func (s *Store) DeleteSessionsExcept(keepID int64) error {
	return s.tx(func(st *state, _ time.Time) error {
		for id, t := range st.tokens {
			if t.Kind == domain.TokenSession && id != keepID {
				delete(st.tokens, id)
			}
		}
		return nil
	})
}
