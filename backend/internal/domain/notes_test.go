package domain

import (
	"encoding/json"
	"testing"
)

func TestTodoTitleRoundTrip(t *testing.T) {
	in := `[{"id":"a","type":"todo","text":"Milk","done":false,"title":"Groceries"},{"id":"b","type":"todo","text":"Eggs","done":true}]`
	var blocks []NoteBlock
	if err := json.Unmarshal([]byte(in), &blocks); err != nil {
		t.Fatal(err)
	}
	out, err := json.Marshal(blocks)
	if err != nil {
		t.Fatal(err)
	}
	if string(out) != in {
		t.Fatalf("got  %s\nwant %s", out, in)
	}
}
