// Package store defines the persistence interfaces the API handlers depend on.
// The mock phase uses the in-memory implementation in store/memory; a MySQL
// implementation will satisfy the same interfaces, so handlers don't change.
//
// Every method is atomic: it either applies all of its changes or none, and
// returns a *domain.Error for anything the caller did wrong.
package store

import (
	"time"

	"notes-app/internal/domain"
)

type Boards interface {
	ListBoards() ([]domain.Board, error)
	CreateBoard(in domain.BoardCreate) (domain.Board, error)
	GetBoardDetail(boardID int64) (domain.BoardDetail, error)
	UpdateBoard(boardID int64, in domain.BoardPatch) (domain.Board, error)
	DeleteBoard(boardID int64, in domain.BoardDelete) error
}

type Lists interface {
	ListLists(boardID int64) ([]domain.List, error)
	CreateList(boardID int64, in domain.ListCreate) (domain.List, error)
	UpdateList(listID int64, in domain.ListPatch) (domain.List, error)
	ReorderLists(boardID int64, listIDs []int64) ([]domain.List, error)
	DeleteList(listID int64, in domain.ListDelete) error
}

type Tags interface {
	ListTags(boardID int64) ([]domain.Tag, error)
	CreateTag(boardID int64, in domain.TagCreate) (domain.Tag, error)
	UpdateTag(tagID int64, in domain.TagPatch) (domain.Tag, error)
	DeleteTag(tagID int64) error
}

type Cards interface {
	ListCards(boardID int64, q domain.CardQuery) ([]domain.CardSummary, error)
	CreateCard(boardID int64, in domain.CardCreate) (domain.Card, error)
	GetCard(cardID int64) (domain.Card, error)
	UpdateCard(cardID int64, in domain.CardPatch) (domain.Card, error)
	MarkDone(cardID int64) (domain.Card, error)
	DeleteCard(cardID int64) error
	SaveNotes(cardID int64, blocks []domain.NoteBlock) (domain.NotesResult, error)
	MoveCards(in domain.CardMove) ([]domain.CardSummary, error)
}

type Inbox interface {
	ListInbox(typ *domain.InboxType) (domain.InboxList, error)
	ResolveInbox(itemID int64, in domain.InboxResolve) (domain.InboxResolution, error)
}

type Sources interface {
	Ingest(in domain.IngestBatch) ([]domain.IngestResult, error)
	ListSources() ([]domain.Source, error)
	Heartbeat(name string, in domain.Heartbeat) (domain.Source, error)
}

// Auth stores the password hash and tokens. Policy (hashing, expiry,
// rate limiting) lives in the auth package, not here.
type Auth interface {
	PasswordHash() (hash string, ok bool, err error)
	SetPasswordHash(hash string) error
	CreateToken(t domain.AuthToken) (domain.AuthToken, error)
	TokenByHash(hash [32]byte) (domain.AuthToken, bool, error)
	TouchToken(id int64, lastUsedAt time.Time, expiresAt *time.Time) error
	ListTokens() ([]domain.AuthToken, error)
	DeleteToken(id int64) error
	DeleteSessionsExcept(keepID int64) error
}

type Store interface {
	Boards
	Lists
	Tags
	Cards
	Inbox
	Sources
	Auth
}
