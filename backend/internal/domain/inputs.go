package domain

import "time"

// Request bodies. Create inputs use pointers for optional fields; PATCH inputs
// use Opt so a field sent as null can be told apart from one left out.

type BoardCreate struct {
	Name            string  `json:"name"`
	ItemNoun        *string `json:"itemNoun"`
	SpecialTagLabel *string `json:"specialTagLabel"`
}

type BoardPatch struct {
	Name            Opt[string] `json:"name"`
	ItemNoun        Opt[string] `json:"itemNoun"`
	SpecialTagLabel Opt[string] `json:"specialTagLabel"`
	Position        Opt[int]    `json:"position"`
}

type BoardDelete struct {
	Cards       *string `json:"cards"` // "delete" | "move"
	ToBoardID   *int64  `json:"toBoardId"`
	ApplyTagIDs []int64 `json:"applyTagIds"`
}

type ListCreate struct {
	Name     string    `json:"name"`
	Kind     *ListKind `json:"kind"`
	Position *int      `json:"position"`
}

type ListPatch struct {
	Name Opt[string]   `json:"name"`
	Kind Opt[ListKind] `json:"kind"`
}

type ListOrder struct {
	ListIDs []int64 `json:"listIds"`
}

type ListDelete struct {
	MoveToListID *int64 `json:"moveToListId"`
}

type TagCreate struct {
	Name      string `json:"name"`
	Color     string `json:"color"`
	IsSpecial *bool  `json:"isSpecial"`
}

type TagPatch struct {
	Name      Opt[string] `json:"name"`
	Color     Opt[string] `json:"color"`
	IsSpecial Opt[bool]   `json:"isSpecial"`
	Position  Opt[int]    `json:"position"`
}

type CardCreate struct {
	Title        string     `json:"title"`
	ListID       *int64     `json:"listId"`
	DueAt        *time.Time `json:"dueAt"`
	DueAllDay    *bool      `json:"dueAllDay"`
	SpecialTagID *int64     `json:"specialTagId"`
	TagIDs       []int64    `json:"tagIds"`
}

type CardPatch struct {
	Title        Opt[string]    `json:"title"`
	ListID       Opt[int64]     `json:"listId"`
	Position     Opt[int]       `json:"position"`
	DueAt        Opt[time.Time] `json:"dueAt"`
	DueAllDay    Opt[bool]      `json:"dueAllDay"`
	SpecialTagID Opt[int64]     `json:"specialTagId"`
	TagIDs       Opt[[]int64]   `json:"tagIds"`
	Archived     Opt[bool]      `json:"archived"`
}

type CardSort string

const (
	SortPosition CardSort = "position" // hand-arranged order (Custom)
	SortDue      CardSort = "due"
	SortCreated  CardSort = "created"
	SortTitle    CardSort = "title"
)

type CardQuery struct {
	ListID   *int64
	DueFrom  *time.Time // inclusive
	DueTo    *time.Time // exclusive
	Archived bool
	Sort     CardSort
}

type NotesPut struct {
	Blocks []NoteBlock `json:"blocks"`
}

type CardMove struct {
	CardIDs     []int64 `json:"cardIds"`
	ToBoardID   int64   `json:"toBoardId"`
	ApplyTagIDs []int64 `json:"applyTagIds"`
}

type InboxEdits struct {
	Title        Opt[string]    `json:"title"`
	BoardID      Opt[int64]     `json:"boardId"`
	SpecialTagID Opt[int64]     `json:"specialTagId"`
	DueAt        Opt[time.Time] `json:"dueAt"`
	DueAllDay    Opt[bool]      `json:"dueAllDay"`
}

type InboxResolve struct {
	Action string      `json:"action"`
	Edits  *InboxEdits `json:"edits"`
}

type IngestItem struct {
	ExternalID     *string    `json:"externalId"`
	BoardID        *int64     `json:"boardId"`
	Title          *string    `json:"title"`
	DueAt          *time.Time `json:"dueAt"`
	DueAllDay      bool       `json:"dueAllDay"`
	SpecialTagName *string    `json:"specialTagName"`
	URL            *string    `json:"url"`
	RawText        *string    `json:"rawText"`
}

type IngestBatch struct {
	Source string       `json:"source"`
	Items  []IngestItem `json:"items"`
}

type Heartbeat struct {
	Health  string  `json:"health"`
	Message *string `json:"message"`
}
