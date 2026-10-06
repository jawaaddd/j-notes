// Package auth implements the single-user password, session tokens, and API
// tokens described under Auth in backend-api-spec.md.
package auth

import (
	"log/slog"
	"math"
	"strings"
	"sync"
	"time"

	"notes-app/internal/domain"
	"notes-app/internal/store"
)

const (
	SessionTTL     = 30 * 24 * time.Hour
	MinPasswordLen = 8
)

type Config struct {
	// EnvPassword is NOTES_PASSWORD. Empty means "not configured": the server
	// uses the stored password, or runs first-run setup if there is none.
	EnvPassword string
	Now         func() time.Time
	Log         *slog.Logger
}

type Service struct {
	store           store.Auth
	now             func() time.Time
	log             *slog.Logger
	passwordFromEnv bool

	mu        sync.Mutex // guards setupCode and serializes setup
	setupCode string
	lim       limiter
}

func NewService(st store.Auth, cfg Config) (*Service, error) {
	s := &Service{store: st, now: cfg.Now, log: cfg.Log}
	if s.now == nil {
		s.now = time.Now
	}
	if s.log == nil {
		s.log = slog.Default()
	}
	if cfg.EnvPassword != "" {
		if len(cfg.EnvPassword) < MinPasswordLen {
			s.log.Warn("NOTES_PASSWORD is shorter than 8 characters; fine for local testing, weak anywhere else")
		}
		hash, err := HashPassword(cfg.EnvPassword)
		if err != nil {
			return nil, err
		}
		if err := st.SetPasswordHash(hash); err != nil {
			return nil, err
		}
		s.passwordFromEnv = true
		return s, nil
	}
	if _, ok, err := st.PasswordHash(); err != nil {
		return nil, err
	} else if !ok {
		code, err := NewSetupCode()
		if err != nil {
			return nil, err
		}
		s.setupCode = code
		s.log.Info("no password set yet; finish setup in the app with this one-time code", "setupCode", code)
	}
	return s, nil
}

func (s *Service) clock() time.Time { return s.now().UTC().Truncate(time.Second) }

type Status struct {
	SetupRequired   bool `json:"setupRequired"`
	PasswordFromEnv bool `json:"passwordFromEnv"`
}

func (s *Service) Status() (Status, error) {
	_, ok, err := s.store.PasswordHash()
	return Status{SetupRequired: !ok, PasswordFromEnv: s.passwordFromEnv}, err
}

// SetupCode is the current one-time code, or "" once setup is done.
func (s *Service) SetupCode() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.setupCode
}

type Session struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expiresAt"`
}

func (s *Service) Setup(code, password, deviceName string) (Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok, err := s.store.PasswordHash(); err != nil {
		return Session{}, err
	} else if ok {
		return Session{}, domain.ErrAlreadySetUp()
	}
	if err := s.checkWait(); err != nil {
		return Session{}, err
	}
	if s.setupCode == "" || !strings.EqualFold(strings.TrimSpace(code), s.setupCode) {
		s.lim.fail(s.clock())
		return Session{}, domain.ErrInvalidSetupCode()
	}
	if err := checkNewPassword("password", password); err != nil {
		return Session{}, err
	}
	hash, err := HashPassword(password)
	if err != nil {
		return Session{}, err
	}
	if err := s.store.SetPasswordHash(hash); err != nil {
		return Session{}, err
	}
	s.setupCode = ""
	s.lim.reset()
	return s.newSession(deviceName)
}

func (s *Service) Login(password, deviceName string) (Session, error) {
	hash, ok, err := s.store.PasswordHash()
	if err != nil {
		return Session{}, err
	}
	if !ok {
		return Session{}, domain.ErrSetupRequired()
	}
	if err := s.checkPassword(password, hash); err != nil {
		return Session{}, err
	}
	return s.newSession(deviceName)
}

// Authenticate resolves a bearer token, sliding a session's expiry forward.
func (s *Service) Authenticate(tok string) (domain.AuthToken, error) {
	t, ok, err := s.store.TokenByHash(HashToken(tok))
	if err != nil {
		return domain.AuthToken{}, err
	}
	now := s.clock()
	if !ok || (t.ExpiresAt != nil && !now.Before(*t.ExpiresAt)) {
		return domain.AuthToken{}, domain.ErrUnauthorized()
	}
	if t.Kind == domain.TokenSession {
		t.ExpiresAt = ptr(now.Add(SessionTTL))
	}
	t.LastUsedAt = &now
	if err := s.store.TouchToken(t.ID, now, t.ExpiresAt); err != nil {
		return domain.AuthToken{}, err
	}
	return t, nil
}

func (s *Service) Logout(current domain.AuthToken) error {
	return s.store.DeleteToken(current.ID)
}

// ChangePassword sets a new password and signs out every other session.
// API tokens keep working.
func (s *Service) ChangePassword(current domain.AuthToken, currentPassword, newPassword string) error {
	if s.passwordFromEnv {
		return domain.ErrPasswordFromEnv()
	}
	hash, ok, err := s.store.PasswordHash()
	if err != nil {
		return err
	}
	if !ok {
		return domain.ErrSetupRequired()
	}
	if err := s.checkPassword(currentPassword, hash); err != nil {
		return err
	}
	if err := checkNewPassword("newPassword", newPassword); err != nil {
		return err
	}
	newHash, err := HashPassword(newPassword)
	if err != nil {
		return err
	}
	if err := s.store.SetPasswordHash(newHash); err != nil {
		return err
	}
	return s.store.DeleteSessionsExcept(current.ID)
}

func (s *Service) ListTokens(current domain.AuthToken) ([]domain.AuthToken, error) {
	toks, err := s.store.ListTokens()
	for i := range toks {
		toks[i].Current = toks[i].ID == current.ID
	}
	return toks, err
}

type CreatedToken struct {
	Token    string           `json:"token"`
	APIToken domain.AuthToken `json:"apiToken"`
}

func (s *Service) CreateAPIToken(name string) (CreatedToken, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return CreatedToken{}, domain.ErrValidation("name", "name is required")
	}
	if len([]rune(name)) > 100 {
		return CreatedToken{}, domain.ErrValidation("name", "name is too long")
	}
	tok, hash, err := NewToken()
	if err != nil {
		return CreatedToken{}, err
	}
	t, err := s.store.CreateToken(domain.AuthToken{Kind: domain.TokenAPI, Name: name, Hash: hash, CreatedAt: s.clock()})
	if err != nil {
		return CreatedToken{}, err
	}
	return CreatedToken{Token: tok, APIToken: t}, nil
}

func (s *Service) DeleteToken(id int64) error { return s.store.DeleteToken(id) }

func (s *Service) newSession(deviceName string) (Session, error) {
	name := strings.TrimSpace(deviceName)
	if name == "" {
		name = "session"
	}
	if len([]rune(name)) > 100 {
		return Session{}, domain.ErrValidation("deviceName", "deviceName is too long")
	}
	tok, hash, err := NewToken()
	if err != nil {
		return Session{}, err
	}
	now := s.clock()
	exp := now.Add(SessionTTL)
	if _, err := s.store.CreateToken(domain.AuthToken{
		Kind: domain.TokenSession, Name: name, Hash: hash, CreatedAt: now, LastUsedAt: &now, ExpiresAt: &exp,
	}); err != nil {
		return Session{}, err
	}
	return Session{Token: tok, ExpiresAt: exp}, nil
}

func (s *Service) checkWait() error {
	if d := s.lim.wait(s.clock()); d > 0 {
		return domain.ErrRateLimited(int(math.Ceil(d.Seconds())))
	}
	return nil
}

func (s *Service) checkPassword(password, hash string) error {
	if err := s.checkWait(); err != nil {
		return err
	}
	ok, err := VerifyPassword(password, hash)
	if err != nil {
		return err
	}
	if !ok {
		s.lim.fail(s.clock())
		return domain.ErrInvalidPassword()
	}
	s.lim.reset()
	return nil
}

func checkNewPassword(field, pw string) error {
	if len([]rune(pw)) < MinPasswordLen {
		return domain.ErrValidation(field, "password must be at least 8 characters")
	}
	return nil
}

func ptr[T any](v T) *T { return &v }
