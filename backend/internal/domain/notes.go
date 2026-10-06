package domain

import (
	"encoding/json"
	"fmt"
	"strings"
)

type BlockType string

const (
	BlockText    BlockType = "text"
	BlockSubtask BlockType = "subtask"
	BlockLink    BlockType = "link"
)

// NoteBlock is one block of a card's notes. Which fields apply depends on Type:
// text {id, type, text}; subtask {id, type, text, done}; link {id, type, title, url}.
type NoteBlock struct {
	ID    string
	Type  BlockType
	Text  string
	Done  bool
	Title string
	URL   string
}

func (b NoteBlock) MarshalJSON() ([]byte, error) {
	switch b.Type {
	case BlockSubtask:
		return json.Marshal(struct {
			ID   string    `json:"id"`
			Type BlockType `json:"type"`
			Text string    `json:"text"`
			Done bool      `json:"done"`
		}{b.ID, b.Type, b.Text, b.Done})
	case BlockLink:
		return json.Marshal(struct {
			ID    string    `json:"id"`
			Type  BlockType `json:"type"`
			Title string    `json:"title"`
			URL   string    `json:"url"`
		}{b.ID, b.Type, b.Title, b.URL})
	default:
		return json.Marshal(struct {
			ID   string    `json:"id"`
			Type BlockType `json:"type"`
			Text string    `json:"text"`
		}{b.ID, b.Type, b.Text})
	}
}

func (b *NoteBlock) UnmarshalJSON(data []byte) error {
	var raw struct {
		ID    *string   `json:"id"`
		Type  BlockType `json:"type"`
		Text  *string   `json:"text"`
		Done  *bool     `json:"done"`
		Title *string   `json:"title"`
		URL   *string   `json:"url"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	*b = NoteBlock{Type: raw.Type}
	if raw.ID != nil {
		b.ID = *raw.ID
	}
	if raw.Text != nil {
		b.Text = *raw.Text
	}
	if raw.Done != nil {
		b.Done = *raw.Done
	}
	if raw.Title != nil {
		b.Title = *raw.Title
	}
	if raw.URL != nil {
		b.URL = *raw.URL
	}
	return nil
}

// ValidateBlocks checks each block's shape and that ids are present and unique.
func ValidateBlocks(blocks []NoteBlock) error {
	seen := make(map[string]bool, len(blocks))
	for i, b := range blocks {
		field := fmt.Sprintf("blocks[%d]", i)
		if strings.TrimSpace(b.ID) == "" {
			return ErrValidation(field+".id", "block id is required")
		}
		if seen[b.ID] {
			return ErrValidation(field+".id", "block ids must be unique")
		}
		seen[b.ID] = true
		switch b.Type {
		case BlockText, BlockSubtask:
		case BlockLink:
			if strings.TrimSpace(b.URL) == "" {
				return ErrValidation(field+".url", "link blocks need a url")
			}
		default:
			return ErrValidation(field+".type", "type must be text, subtask, or link")
		}
	}
	return nil
}
