// Package domain holds the API's resource shapes, request inputs, and errors.
// JSON tags here are the wire format described in backend-api-spec.md.
package domain

import "time"

type ListKind string

const (
	KindOpen ListKind = "open"
	KindDone ListKind = "done"
)

// Colors is the fixed tag palette.
var Colors = map[string]bool{"pink": true, "blue": true, "violet": true, "cyan": true, "orange": true, "yellow": true}

// UrgentColor is reserved: the Urgent tag always has it and no other tag can.
const UrgentColor = "yellow"

const UrgentKey = "urgent"

type Board struct {
	ID              int64     `json:"id"`
	Name            string    `json:"name"`
	ItemNoun        string    `json:"itemNoun"`
	SpecialTagLabel string    `json:"specialTagLabel"`
	Position        int       `json:"position"`
	OpenCount       int       `json:"openCount"`
	OverdueCount    int       `json:"overdueCount"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

type BoardDetail struct {
	Board Board  `json:"board"`
	Lists []List `json:"lists"`
	Tags  []Tag  `json:"tags"`
}

type List struct {
	ID        int64    `json:"id"`
	BoardID   int64    `json:"boardId"`
	Name      string   `json:"name"`
	Kind      ListKind `json:"kind"`
	Position  int      `json:"position"`
	CardCount int      `json:"cardCount"`
}

type Tag struct {
	ID            int64   `json:"id"`
	BoardID       int64   `json:"boardId"`
	Name          string  `json:"name"`
	Color         string  `json:"color"`
	IsSpecial     bool    `json:"isSpecial"`
	SystemKey     *string `json:"systemKey"`
	Position      int     `json:"position"`
	OpenCardCount int     `json:"openCardCount"`
}

type CardSummary struct {
	ID           int64      `json:"id"`
	BoardID      int64      `json:"boardId"`
	ListID       int64      `json:"listId"`
	Position     int        `json:"position"` // order within the list, for Custom sort
	Title        string     `json:"title"`
	DueAt        *time.Time `json:"dueAt"`
	DueAllDay    bool       `json:"dueAllDay"`
	SpecialTagID *int64     `json:"specialTagId"`
	TagIDs       []int64    `json:"tagIds"`
	CompletedAt  *time.Time `json:"completedAt"`
	ArchivedAt   *time.Time `json:"archivedAt"`
	CreatedAt    time.Time  `json:"createdAt"`
	UpdatedAt    time.Time  `json:"updatedAt"`
}

type CardSource struct {
	Name string  `json:"name"`
	URL  *string `json:"url"`
}

type Card struct {
	CardSummary
	Source       CardSource  `json:"source"`
	ExternalID   *string     `json:"externalId"`
	LastSyncedAt *time.Time  `json:"lastSyncedAt"`
	Notes        []NoteBlock `json:"notes"`
}

type NotesResult struct {
	Blocks    []NoteBlock `json:"blocks"`
	UpdatedAt time.Time   `json:"updatedAt"`
}

type InboxType string

const (
	InboxVoice     InboxType = "voice"
	InboxChange    InboxType = "change"
	InboxDuplicate InboxType = "duplicate"
)

// Parsed is what a source or the classifier made of an incoming entry.
// ExternalID and URL carry a scraped item's identity so resolving it can
// attach them to the card it creates or merges into.
type Parsed struct {
	Title        string            `json:"title"`
	SpecialTagID *int64            `json:"specialTagId"`
	DueAt        *time.Time        `json:"dueAt"`
	DueAllDay    bool              `json:"dueAllDay"`
	Uncertain    map[string]string `json:"uncertain"`
	ExternalID   *string           `json:"externalId"`
	URL          *string           `json:"url"`
}

type Change struct {
	Field    string  `json:"field"` // "title" or "dueAt"
	OldValue *string `json:"oldValue"`
	NewValue *string `json:"newValue"`
}

type InboxItem struct {
	ID         int64      `json:"id"`
	Type       InboxType  `json:"type"`
	Source     string     `json:"source"`
	BoardID    *int64     `json:"boardId"`
	RawText    string     `json:"rawText"`
	Parsed     Parsed     `json:"parsed"`
	CardID     *int64     `json:"cardId"`
	Change     *Change    `json:"change"`
	Status     string     `json:"status"`
	ReceivedAt time.Time  `json:"receivedAt"`
	ResolvedAt *time.Time `json:"resolvedAt"`
}

type InboxCounts struct {
	All       int `json:"all"`
	Voice     int `json:"voice"`
	Change    int `json:"change"`
	Duplicate int `json:"duplicate"`
}

type InboxList struct {
	Items  []InboxItem `json:"items"`
	Counts InboxCounts `json:"counts"`
}

type InboxResolution struct {
	Item InboxItem `json:"item"`
	Card *Card     `json:"card"`
}

type Source struct {
	Name          string     `json:"name"`
	Kind          string     `json:"kind"`
	Health        string     `json:"health"`
	StatusMessage *string    `json:"statusMessage"`
	LastSyncAt    *time.Time `json:"lastSyncAt"`
}

type IngestResult struct {
	ExternalID  *string `json:"externalId"`
	Result      string  `json:"result"` // created | updated | unchanged | inboxed
	CardID      *int64  `json:"cardId"`
	InboxItemID *int64  `json:"inboxItemId"`
}

type TokenKind string

const (
	TokenSession TokenKind = "session"
	TokenAPI     TokenKind = "api"
)

// AuthToken is a stored session or API token. Hash is never serialized.
type AuthToken struct {
	ID         int64      `json:"id"`
	Kind       TokenKind  `json:"kind"`
	Name       string     `json:"name"`
	Hash       [32]byte   `json:"-"`
	CreatedAt  time.Time  `json:"createdAt"`
	LastUsedAt *time.Time `json:"lastUsedAt"`
	ExpiresAt  *time.Time `json:"expiresAt"`
	Current    bool       `json:"current"`
}
