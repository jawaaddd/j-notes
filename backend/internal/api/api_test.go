package api_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"notes-app/internal/api"
	"notes-app/internal/auth"
	"notes-app/internal/store/memory"
)

// Seed ids (see memory/seed.go): Fall 2026 = board 1 with lists 11 To Do,
// 12 In Progress, 13 Done and tags 21 Urgent, 22 DiffEq, 23 Robotics,
// 24 AI Policy, 25 Exam prep, 26 Waiting on someone, 27 Group work.
// Personal = board 2 (lists 14–16, tags 28 Urgent, 29 Home, 30 Errands,
// 31 Money, 32 expensive). Projects = board 3 (lists 17–19, tags 33–35).
// Cards: 101 HW 5, 102 HW 6, 103 Lab 4, 104 Policy memo, 105 Lab 3 (In
// Progress), 106 Reading response (Done). Inbox: 201–204.

var now = time.Date(2026, 10, 6, 16, 0, 0, 0, time.UTC)

type client struct {
	t     *testing.T
	h     http.Handler
	token string
	svc   *auth.Service
}

type resp struct {
	status int
	body   map[string]any
	list   []any
}

func newClient(t *testing.T, envPassword string) *client {
	t.Helper()
	gin.SetMode(gin.TestMode)
	clock := func() time.Time { return now }
	st := memory.New(clock, time.UTC)
	if err := st.Seed(); err != nil {
		t.Fatal(err)
	}
	svc, err := auth.NewService(st, auth.Config{EnvPassword: envPassword, Now: clock})
	if err != nil {
		t.Fatal(err)
	}
	c := &client{t: t, h: api.New(st, svc), svc: svc}
	if envPassword != "" {
		r := c.do("POST", "/api/auth/login", map[string]any{"password": envPassword})
		c.token = r.str("token")
	}
	return c
}

func (c *client) do(method, path string, body any) resp {
	c.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, rd)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	w := httptest.NewRecorder()
	c.h.ServeHTTP(w, req)
	r := resp{status: w.Code}
	if w.Body.Len() > 0 {
		var v any
		if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
			c.t.Fatalf("%s %s: bad JSON %q", method, path, w.Body.String())
		}
		switch v := v.(type) {
		case map[string]any:
			r.body = v
		case []any:
			r.list = v
		}
	}
	return r
}

// want fails the test unless the response has the given status.
func (r resp) want(t *testing.T, status int) resp {
	t.Helper()
	if r.status != status {
		t.Fatalf("status = %d, want %d; body %v", r.status, status, r.body)
	}
	return r
}

// wantErr fails unless the response is an error with this status and code.
func (r resp) wantErr(t *testing.T, status int, code string) resp {
	t.Helper()
	r.want(t, status)
	e, _ := r.body["error"].(map[string]any)
	if e == nil || e["code"] != code {
		t.Fatalf("error code = %v, want %s", r.body["error"], code)
	}
	return r
}

func (r resp) str(key string) string { s, _ := r.body[key].(string); return s }

func (r resp) num(key string) float64 { n, _ := r.body[key].(float64); return n }

func ids(v any) []float64 {
	var out []float64
	for _, x := range v.([]any) {
		out = append(out, x.(float64))
	}
	return out
}

func findByID(list []any, id float64) map[string]any {
	for _, x := range list {
		if m := x.(map[string]any); m["id"] == id {
			return m
		}
	}
	return nil
}

// ---- auth ----

func TestAuthRequiredAndHealthOpen(t *testing.T) {
	c := newClient(t, "correct horse")
	c.do("GET", "/healthz", nil).want(t, 200)
	tok := c.token
	c.token = ""
	c.do("GET", "/api/boards", nil).wantErr(t, 401, "UNAUTHORIZED")
	c.token = "nts_not-a-real-token"
	c.do("GET", "/api/boards", nil).wantErr(t, 401, "UNAUTHORIZED")
	c.token = tok
	c.do("GET", "/api/boards", nil).want(t, 200)
}

func TestLoginRateLimit(t *testing.T) {
	c := newClient(t, "correct horse")
	for i := 0; i < 5; i++ {
		c.do("POST", "/api/auth/login", map[string]any{"password": "wrong"}).wantErr(t, 401, "INVALID_PASSWORD")
	}
	r := c.do("POST", "/api/auth/login", map[string]any{"password": "correct horse"}).wantErr(t, 429, "RATE_LIMITED")
	if d := r.body["error"].(map[string]any)["details"].(map[string]any); d["retryAfterSeconds"].(float64) < 1 {
		t.Fatalf("retryAfterSeconds = %v", d["retryAfterSeconds"])
	}
}

func TestFirstRunSetup(t *testing.T) {
	c := newClient(t, "")
	r := c.do("GET", "/api/auth/status", nil).want(t, 200)
	if r.body["setupRequired"] != true {
		t.Fatal("setupRequired should be true with no password")
	}
	c.do("POST", "/api/auth/login", map[string]any{"password": "anything1"}).wantErr(t, 409, "SETUP_REQUIRED")
	c.do("POST", "/api/auth/setup", map[string]any{"setupCode": "WRONG-CODE", "password": "longenough"}).wantErr(t, 401, "INVALID_SETUP_CODE")
	code := c.svc.SetupCode()
	c.do("POST", "/api/auth/setup", map[string]any{"setupCode": code, "password": "short"}).wantErr(t, 422, "VALIDATION")
	r = c.do("POST", "/api/auth/setup", map[string]any{"setupCode": code, "password": "longenough"}).want(t, 200)
	c.token = r.str("token")
	c.do("GET", "/api/boards", nil).want(t, 200)
	c.do("POST", "/api/auth/setup", map[string]any{"setupCode": code, "password": "longenough"}).wantErr(t, 409, "ALREADY_SET_UP")

	// Password change signs out other sessions but keeps this one.
	other := c.do("POST", "/api/auth/login", map[string]any{"password": "longenough"}).want(t, 200).str("token")
	c.do("PUT", "/api/auth/password", map[string]any{"currentPassword": "longenough", "newPassword": "evenlonger"}).want(t, 204)
	c.do("GET", "/api/boards", nil).want(t, 200)
	mine := c.token
	c.token = other
	c.do("GET", "/api/boards", nil).wantErr(t, 401, "UNAUTHORIZED")
	c.token = mine
	c.do("POST", "/api/auth/logout", nil).want(t, 204)
	c.do("GET", "/api/boards", nil).wantErr(t, 401, "UNAUTHORIZED")
}

func TestPasswordFromEnvCantChange(t *testing.T) {
	c := newClient(t, "correct horse")
	c.do("PUT", "/api/auth/password", map[string]any{"currentPassword": "correct horse", "newPassword": "new password"}).
		wantErr(t, 409, "PASSWORD_FROM_ENV")
}

func TestAPITokens(t *testing.T) {
	c := newClient(t, "correct horse")
	r := c.do("POST", "/api/tokens", map[string]any{"name": "autolab scraper"}).want(t, 201)
	apiTok := r.str("token")
	id := r.body["apiToken"].(map[string]any)["id"].(float64)
	list := c.do("GET", "/api/tokens", nil).want(t, 200).list
	if len(list) != 2 {
		t.Fatalf("want session + api token, got %d", len(list))
	}
	session := c.token
	c.token = apiTok
	c.do("GET", "/api/sources", nil).want(t, 200)
	c.token = session
	c.do("DELETE", "/api/tokens/"+itoa(id), nil).want(t, 204)
	c.token = apiTok
	c.do("GET", "/api/sources", nil).wantErr(t, 401, "UNAUTHORIZED")
}

// ---- boards ----

func TestCreateBoardDefaults(t *testing.T) {
	c := newClient(t, "correct horse")
	b := c.do("POST", "/api/boards", map[string]any{"name": "Spring 2027"}).want(t, 201)
	if b.str("itemNoun") != "Cards" || b.str("specialTagLabel") != "Tags" || b.num("position") != 3 {
		t.Fatalf("defaults wrong: %v", b.body)
	}
	d := c.do("GET", "/api/boards/"+itoa(b.num("id")), nil).want(t, 200)
	lists := d.body["lists"].([]any)
	if len(lists) != 3 || lists[0].(map[string]any)["name"] != "To Do" || lists[2].(map[string]any)["kind"] != "done" {
		t.Fatalf("default lists wrong: %v", lists)
	}
	tags := d.body["tags"].([]any)
	if len(tags) != 1 || tags[0].(map[string]any)["systemKey"] != "urgent" {
		t.Fatalf("want only the Urgent tag, got %v", tags)
	}
}

func TestDeleteBoard(t *testing.T) {
	c := newClient(t, "correct horse")
	c.do("DELETE", "/api/boards/3", nil).wantErr(t, 409, "BOARD_HAS_CARDS")
	c.do("DELETE", "/api/boards/3", map[string]any{"cards": "move"}).wantErr(t, 422, "VALIDATION")
	// Tags apply from the target board; a Projects tag would be cross-board.
	c.do("DELETE", "/api/boards/3", map[string]any{"cards": "move", "toBoardId": 2, "applyTagIds": []int{33}}).wantErr(t, 422, "CROSS_BOARD")
	c.do("DELETE", "/api/boards/3", map[string]any{"cards": "move", "toBoardId": 2, "applyTagIds": []int{29, 32}}).want(t, 204)
	c.do("GET", "/api/boards/3", nil).wantErr(t, 404, "NOT_FOUND")

	cards := c.do("GET", "/api/boards/2/cards", nil).want(t, 200).list
	if len(cards) != 9 {
		t.Fatalf("Personal should have 6 + 3 moved cards, got %d", len(cards))
	}
	for _, x := range cards {
		card := x.(map[string]any)
		if card["id"].(float64) >= 113 { // the moved Projects cards
			if card["specialTagId"] != 29.0 || len(ids(card["tagIds"])) != 1 {
				t.Fatalf("moved card tags wrong: %v", card)
			}
		}
	}
	// "Build the mock backend" was In Progress on Projects; same-named list on Personal is 15.
	if findByID(cards, 115)["listId"] != 15.0 {
		t.Fatalf("list should map by name: %v", findByID(cards, 115))
	}

	// An empty board deletes without a choice; positions close up.
	b := c.do("POST", "/api/boards", map[string]any{"name": "Empty"}).want(t, 201)
	c.do("DELETE", "/api/boards/"+itoa(b.num("id")), nil).want(t, 204)
	c.do("DELETE", "/api/boards/2", map[string]any{"cards": "delete"}).want(t, 204)
	boards := c.do("GET", "/api/boards", nil).want(t, 200).list
	if len(boards) != 1 || boards[0].(map[string]any)["position"] != 0.0 {
		t.Fatalf("boards after delete: %v", boards)
	}
	c.do("DELETE", "/api/boards/1", map[string]any{"cards": "delete"}).wantErr(t, 422, "LAST_BOARD")
}

// ---- lists ----

func TestListRules(t *testing.T) {
	c := newClient(t, "correct horse")
	c.do("DELETE", "/api/lists/13", nil).wantErr(t, 422, "LAST_OF_KIND")
	c.do("PATCH", "/api/lists/13", map[string]any{"kind": "open"}).wantErr(t, 422, "LAST_OF_KIND")
	c.do("POST", "/api/boards/1/lists", map[string]any{"name": "To Do"}).wantErr(t, 422, "VALIDATION")

	// A second done list can be added, then the original re-kinded to open:
	// its card loses completedAt.
	c.do("POST", "/api/boards/1/lists", map[string]any{"name": "Shipped", "kind": "done", "position": 1}).want(t, 201)
	c.do("PATCH", "/api/lists/13", map[string]any{"kind": "open"}).want(t, 200)
	if card := c.do("GET", "/api/cards/106", nil).want(t, 200); card.body["completedAt"] != nil {
		t.Fatalf("completedAt should clear when its list becomes open: %v", card.body["completedAt"])
	}

	c.do("DELETE", "/api/lists/12", nil).wantErr(t, 409, "LIST_HAS_CARDS")
	c.do("DELETE", "/api/lists/12", map[string]any{"moveToListId": 14}).wantErr(t, 422, "CROSS_BOARD")
	c.do("DELETE", "/api/lists/12", map[string]any{"moveToListId": 11}).want(t, 204)
	if card := c.do("GET", "/api/cards/105", nil).want(t, 200); card.num("listId") != 11 {
		t.Fatalf("card should have moved to To Do: %v", card.body["listId"])
	}

	c.do("PUT", "/api/boards/1/lists/order", map[string]any{"listIds": []int{11}}).wantErr(t, 422, "VALIDATION")
	lists := c.do("GET", "/api/boards/1/lists", nil).want(t, 200).list
	var order []int
	for i := len(lists) - 1; i >= 0; i-- {
		order = append(order, int(lists[i].(map[string]any)["id"].(float64)))
	}
	got := c.do("PUT", "/api/boards/1/lists/order", map[string]any{"listIds": order}).want(t, 200).list
	if int(got[0].(map[string]any)["id"].(float64)) != order[0] {
		t.Fatalf("reorder not applied: %v", got)
	}
}

// ---- tags ----

func TestTagRules(t *testing.T) {
	c := newClient(t, "correct horse")
	c.do("DELETE", "/api/tags/21", nil).wantErr(t, 422, "SYSTEM_TAG")
	c.do("PATCH", "/api/tags/21", map[string]any{"isSpecial": true}).wantErr(t, 422, "SYSTEM_TAG")
	c.do("PATCH", "/api/tags/21", map[string]any{"color": "orange"}).wantErr(t, 422, "SYSTEM_TAG")
	c.do("PATCH", "/api/tags/21", map[string]any{"name": "ASAP", "color": "yellow"}).want(t, 200)
	c.do("POST", "/api/boards/1/tags", map[string]any{"name": "Lab", "color": "yellow"}).wantErr(t, 422, "VALIDATION")
	c.do("PATCH", "/api/tags/24", map[string]any{"color": "yellow"}).wantErr(t, 422, "VALIDATION")
	c.do("POST", "/api/boards/1/tags", map[string]any{"name": "Lab", "color": "green"}).wantErr(t, 422, "VALIDATION")
	c.do("POST", "/api/boards/1/tags", map[string]any{"name": "DiffEq", "color": "blue"}).wantErr(t, 422, "VALIDATION")

	// Turning Robotics (special on cards 103, 105) into a regular tag keeps the label.
	c.do("PATCH", "/api/tags/23", map[string]any{"isSpecial": false}).want(t, 200)
	card := c.do("GET", "/api/cards/105", nil).want(t, 200)
	if card.body["specialTagId"] != nil || !contains(ids(card.body["tagIds"]), 23) {
		t.Fatalf("Robotics should move to regular tags: %v", card.body)
	}
	// And back: cards with no special tag take it as special again.
	c.do("PATCH", "/api/tags/23", map[string]any{"isSpecial": true}).want(t, 200)
	card = c.do("GET", "/api/cards/105", nil).want(t, 200)
	if card.body["specialTagId"] != 23.0 || contains(ids(card.body["tagIds"]), 23) {
		t.Fatalf("Robotics should be special again: %v", card.body)
	}

	c.do("DELETE", "/api/tags/22", nil).want(t, 204)
	if card := c.do("GET", "/api/cards/101", nil).want(t, 200); card.body["specialTagId"] != nil {
		t.Fatal("deleting a special tag should clear it from cards")
	}
	tags := c.do("GET", "/api/boards/1/tags", nil).want(t, 200).list
	if tags[0].(map[string]any)["isSpecial"] != true {
		t.Fatal("special tags list first")
	}
}

// ---- cards ----

func TestCardRules(t *testing.T) {
	c := newClient(t, "correct horse")
	r := c.do("POST", "/api/boards/1/cards", map[string]any{"title": "New thing", "specialTagId": 22, "tagIds": []int{25}}).want(t, 201)
	if r.num("listId") != 11 || r.body["source"].(map[string]any)["name"] != "manual" {
		t.Fatalf("new card defaults wrong: %v", r.body)
	}
	id := itoa(r.num("id"))
	c.do("POST", "/api/boards/1/cards", map[string]any{"title": " "}).wantErr(t, 422, "VALIDATION")
	c.do("PATCH", "/api/cards/"+id, map[string]any{"specialTagId": 25}).wantErr(t, 422, "NOT_SPECIAL")
	c.do("PATCH", "/api/cards/"+id, map[string]any{"specialTagId": 29}).wantErr(t, 422, "CROSS_BOARD")
	c.do("PATCH", "/api/cards/"+id, map[string]any{"tagIds": []int{22}}).wantErr(t, 422, "VALIDATION")
	c.do("PATCH", "/api/cards/"+id, map[string]any{"listId": 14}).wantErr(t, 422, "CROSS_BOARD")

	done := c.do("PATCH", "/api/cards/"+id, map[string]any{"listId": 13}).want(t, 200)
	if done.body["completedAt"] == nil {
		t.Fatal("entering a done list sets completedAt")
	}
	open := c.do("PATCH", "/api/cards/"+id, map[string]any{"listId": 12, "specialTagId": nil}).want(t, 200)
	if open.body["completedAt"] != nil || open.body["specialTagId"] != nil {
		t.Fatalf("leaving done clears completedAt; null clears specialTagId: %v", open.body)
	}
	if open.str("title") != "New thing" || !contains(ids(open.body["tagIds"]), 25) {
		t.Fatal("fields left out of a PATCH must not change")
	}
	marked := c.do("POST", "/api/cards/"+id+"/done", nil).want(t, 200)
	if marked.num("listId") != 13 {
		t.Fatal("mark done moves to the first done list")
	}

	c.do("PATCH", "/api/cards/"+id, map[string]any{"archived": true}).want(t, 200)
	if n := len(c.do("GET", "/api/boards/1/cards", nil).list); n != 6 {
		t.Fatalf("archived cards are hidden by default, got %d", n)
	}
	if n := len(c.do("GET", "/api/boards/1/cards?archived=true", nil).list); n != 7 {
		t.Fatalf("archived=true includes them, got %d", n)
	}
	c.do("DELETE", "/api/cards/"+id, nil).want(t, 204)
	c.do("GET", "/api/cards/"+id, nil).wantErr(t, 404, "NOT_FOUND")
}

func TestCardListQuery(t *testing.T) {
	c := newClient(t, "correct horse")
	cards := c.do("GET", "/api/boards/1/cards", nil).want(t, 200).list
	var got []float64
	for _, x := range cards {
		got = append(got, x.(map[string]any)["id"].(float64))
	}
	// To Do by due date, then In Progress, then Done.
	want := []float64{101, 102, 103, 104, 105, 106}
	if !equal(got, want) {
		t.Fatalf("order = %v, want %v", got, want)
	}
	// HW 5 (Oct 5 23:59) through Lab 3 (Oct 8 23:59), dates in UTC.
	inRange := c.do("GET", "/api/boards/1/cards?dueFrom=2026-10-05&dueTo=2026-10-07", nil).want(t, 200).list
	if len(inRange) != 2 {
		t.Fatalf("due range: got %d cards", len(inRange))
	}
	c.do("GET", "/api/boards/1/cards?sort=priority", nil).wantErr(t, 422, "VALIDATION")
	byList := c.do("GET", "/api/boards/1/cards?listId=12", nil).want(t, 200).list
	if len(byList) != 1 {
		t.Fatalf("listId filter: got %d", len(byList))
	}
}

func TestNotes(t *testing.T) {
	c := newClient(t, "correct horse")
	card := c.do("GET", "/api/cards/105", nil).want(t, 200)
	if n := len(card.body["notes"].([]any)); n != 7 {
		t.Fatalf("Lab 3 should have 7 seeded blocks, got %d", n)
	}
	blocks := []map[string]any{
		{"id": "a", "type": "text", "text": "hello"},
		{"id": "b", "type": "todo", "text": "do it", "done": true},
		{"id": "c", "type": "link", "title": "site", "url": "https://example.com"},
	}
	r := c.do("PUT", "/api/cards/105/notes", map[string]any{"blocks": blocks}).want(t, 200)
	if len(r.body["blocks"].([]any)) != 3 || r.str("updatedAt") == "" {
		t.Fatalf("notes save: %v", r.body)
	}
	got := c.do("GET", "/api/cards/105", nil).body["notes"].([]any)
	if got[1].(map[string]any)["done"] != true || got[2].(map[string]any)["url"] != "https://example.com" {
		t.Fatalf("notes round trip: %v", got)
	}
	if _, has := got[0].(map[string]any)["done"]; has {
		t.Fatal("text blocks carry only id, type, text")
	}
	c.do("PUT", "/api/cards/105/notes", map[string]any{"blocks": []map[string]any{{"id": "a", "type": "text"}, {"id": "a", "type": "text"}}}).
		wantErr(t, 422, "VALIDATION")
	c.do("PUT", "/api/cards/105/notes", map[string]any{"blocks": []map[string]any{{"id": "x", "type": "image"}}}).
		wantErr(t, 422, "VALIDATION")
}

func TestMoveCards(t *testing.T) {
	c := newClient(t, "correct horse")
	c.do("POST", "/api/cards/move", map[string]any{"cardIds": []int{105}, "toBoardId": 2, "applyTagIds": []int{29, 30}}).
		wantErr(t, 422, "VALIDATION") // two special tags
	moved := c.do("POST", "/api/cards/move", map[string]any{"cardIds": []int{105, 106}, "toBoardId": 2, "applyTagIds": []int{30, 32}}).
		want(t, 200).list
	lab3, rr := moved[0].(map[string]any), moved[1].(map[string]any)
	if lab3["boardId"] != 2.0 || lab3["listId"] != 15.0 || lab3["specialTagId"] != 30.0 || !equal(ids(lab3["tagIds"]), []float64{32}) {
		t.Fatalf("moved card: %v", lab3)
	}
	if rr["listId"] != 16.0 || rr["completedAt"] == nil {
		t.Fatalf("a done card stays done: %v", rr)
	}
	// Notes and source move unchanged.
	full := c.do("GET", "/api/cards/105", nil).want(t, 200)
	if len(full.body["notes"].([]any)) != 7 || full.body["externalId"] != "cse-lab3" {
		t.Fatal("notes and externalId should move with the card")
	}
}

// ---- inbox ----

func TestInboxVoiceAccept(t *testing.T) {
	c := newClient(t, "correct horse")
	r := c.do("GET", "/api/inbox", nil).want(t, 200)
	if r.body["counts"].(map[string]any)["all"] != 4.0 {
		t.Fatalf("seed inbox: %v", r.body["counts"])
	}
	voice := c.do("GET", "/api/inbox?type=voice", nil).want(t, 200)
	if len(voice.body["items"].([]any)) != 2 || voice.body["counts"].(map[string]any)["all"] != 4.0 {
		t.Fatal("type filter narrows items but not counts")
	}
	c.do("POST", "/api/inbox/201/resolve", map[string]any{"action": "merge"}).wantErr(t, 422, "INVALID_ACTION")
	res := c.do("POST", "/api/inbox/201/resolve", map[string]any{"action": "accept", "edits": map[string]any{"title": "Read ch. 4"}}).want(t, 200)
	card := res.body["card"].(map[string]any)
	if card["title"] != "Read ch. 4" || card["listId"] != 11.0 || card["specialTagId"] != 23.0 {
		t.Fatalf("accepted card: %v", card)
	}
	if res.body["item"].(map[string]any)["status"] != "accepted" {
		t.Fatal("item should be accepted")
	}
	c.do("POST", "/api/inbox/201/resolve", map[string]any{"action": "accept"}).wantErr(t, 422, "INVALID_ACTION")

	// Moving a voice entry to another board drops the guessed special tag.
	res = c.do("POST", "/api/inbox/202/resolve", map[string]any{"action": "accept", "edits": map[string]any{"boardId": 2}}).want(t, 200)
	if card := res.body["card"].(map[string]any); card["boardId"] != 2.0 || card["specialTagId"] != nil {
		t.Fatalf("card on new board: %v", card)
	}
}

func TestInboxDuplicateAndChange(t *testing.T) {
	c := newClient(t, "correct horse")
	res := c.do("POST", "/api/inbox/204/resolve", map[string]any{"action": "keep_both"}).want(t, 200)
	if res.body["card"].(map[string]any)["title"] != "Laplace homework" {
		t.Fatal("keep_both creates a card from parsed")
	}
	before := c.do("GET", "/api/cards/102", nil).body["dueAt"]
	res = c.do("POST", "/api/inbox/203/resolve", map[string]any{"action": "ignore"}).want(t, 200)
	if res.body["card"] != nil || c.do("GET", "/api/cards/102", nil).body["dueAt"] != before {
		t.Fatal("ignore leaves the card alone")
	}
}

// ---- ingest ----

func TestIngestScraper(t *testing.T) {
	c := newClient(t, "correct horse")
	item := map[string]any{"externalId": "webwork-mth306-hw7", "boardId": 1, "title": "HW 7: Systems of ODEs",
		"dueAt": "2026-10-20T03:59:00Z", "specialTagName": "diffeq", "url": "https://example.edu/hw7"}
	r := c.do("POST", "/api/ingest", map[string]any{"source": "webwork", "items": []any{item}}).want(t, 200)
	res := r.body["results"].([]any)[0].(map[string]any)
	if res["result"] != "created" {
		t.Fatalf("first run creates: %v", res)
	}
	cardID := itoa(res["cardId"].(float64))
	if card := c.do("GET", "/api/cards/"+cardID, nil).body; card["specialTagId"] != 22.0 || card["lastSyncedAt"] == nil {
		t.Fatalf("special tag matched by name, sync time set: %v", card)
	}
	r = c.do("POST", "/api/ingest", map[string]any{"source": "webwork", "items": []any{item}}).want(t, 200)
	if r.body["results"].([]any)[0].(map[string]any)["result"] != "unchanged" {
		t.Fatal("same item again is unchanged")
	}

	// Due date moves: a Change item, and the card keeps its value until accepted.
	item["dueAt"] = "2026-10-22T03:59:00Z"
	r = c.do("POST", "/api/ingest", map[string]any{"source": "webwork", "items": []any{item}}).want(t, 200)
	res = r.body["results"].([]any)[0].(map[string]any)
	if res["result"] != "inboxed" {
		t.Fatalf("changed due date goes to the Inbox: %v", res)
	}
	itemID := itoa(res["inboxItemId"].(float64))
	c.do("POST", "/api/inbox/"+itemID+"/resolve", map[string]any{"action": "ignore"}).want(t, 200)
	// Ignored: the same value isn't raised again...
	r = c.do("POST", "/api/ingest", map[string]any{"source": "webwork", "items": []any{item}}).want(t, 200)
	if r.body["results"].([]any)[0].(map[string]any)["result"] != "unchanged" {
		t.Fatal("an ignored change isn't raised again")
	}
	// ...until the source changes it again.
	item["dueAt"] = "2026-10-23T03:59:00Z"
	r = c.do("POST", "/api/ingest", map[string]any{"source": "webwork", "items": []any{item}}).want(t, 200)
	if r.body["results"].([]any)[0].(map[string]any)["result"] != "inboxed" {
		t.Fatal("a new value is raised")
	}

	// A new item that looks like an existing card becomes a Duplicate; merging
	// gives the card the external id so the next run recognizes it.
	dup := map[string]any{"externalId": "syl-hw5", "boardId": 1, "title": "hw 5 second order linear odes"}
	r = c.do("POST", "/api/ingest", map[string]any{"source": "syllabus", "items": []any{dup}}).want(t, 200)
	res = r.body["results"].([]any)[0].(map[string]any)
	if res["result"] != "inboxed" || res["cardId"] != 101.0 {
		t.Fatalf("duplicate: %v", res)
	}
	c.do("POST", "/api/inbox/"+itoa(res["inboxItemId"].(float64))+"/resolve", map[string]any{"action": "merge"}).want(t, 200)
	r = c.do("POST", "/api/ingest", map[string]any{"source": "syllabus", "items": []any{dup}}).want(t, 200)
	if res := r.body["results"].([]any)[0].(map[string]any); res["result"] == "inboxed" {
		t.Fatalf("after merge the item matches the card: %v", res)
	}

	// A bad item rejects the whole batch.
	bad := []any{map[string]any{"externalId": "x1", "boardId": 1, "title": "ok"}, map[string]any{"externalId": "x2", "title": "no board"}}
	c.do("POST", "/api/ingest", map[string]any{"source": "webwork", "items": bad}).wantErr(t, 422, "VALIDATION")
	r = c.do("POST", "/api/ingest", map[string]any{"source": "webwork", "items": []any{bad[0]}}).want(t, 200)
	if r.body["results"].([]any)[0].(map[string]any)["result"] != "created" {
		t.Fatal("the rolled-back batch must not have created x1")
	}
}

func TestIngestVoiceAndHeartbeat(t *testing.T) {
	c := newClient(t, "correct horse")
	r := c.do("POST", "/api/ingest", map[string]any{"source": "voice", "items": []any{
		map[string]any{"externalId": nil, "rawText": "uh robotics, start reading chapter 5 before thursday"},
	}}).want(t, 200)
	if r.body["results"].([]any)[0].(map[string]any)["result"] != "inboxed" {
		t.Fatal("mock voice entries always go to the Inbox")
	}
	src := c.do("POST", "/api/sources/autolab/heartbeat", map[string]any{"health": "ok"}).want(t, 200)
	if src.str("health") != "ok" || src.str("lastSyncAt") != now.Format(time.RFC3339) {
		t.Fatalf("heartbeat: %v", src.body)
	}
	c.do("POST", "/api/sources/nope/heartbeat", map[string]any{"health": "ok"}).wantErr(t, 404, "NOT_FOUND")
	c.do("POST", "/api/sources/autolab/heartbeat", map[string]any{"health": "meh"}).wantErr(t, 422, "VALIDATION")
}

func TestErrorShapes(t *testing.T) {
	c := newClient(t, "correct horse")
	c.do("GET", "/api/cards/abc", nil).wantErr(t, 404, "NOT_FOUND")
	c.do("GET", "/api/nothing-here", nil).wantErr(t, 404, "NOT_FOUND")
	c.do("PATCH", "/api/cards/101", map[string]any{"dueAt": "next tuesday"}).wantErr(t, 422, "VALIDATION")
	c.do("PATCH", "/api/cards/101", map[string]any{"title": 5}).wantErr(t, 422, "VALIDATION")
}

func itoa(f float64) string { return strconv.FormatInt(int64(f), 10) }

func contains(xs []float64, x float64) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}

func equal(a, b []float64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestCustomOrder(t *testing.T) {
	c := newClient(t, "correct horse")
	order := func(listID float64) []float64 {
		var out []float64
		for _, x := range c.do("GET", "/api/boards/1/cards?listId="+itoa(listID), nil).want(t, 200).list {
			out = append(out, x.(map[string]any)["id"].(float64))
		}
		return out
	}
	// Default sort is position; the seed's To Do order is HW 5, HW 6, Lab 4, Policy memo.
	if got := order(11); !equal(got, []float64{101, 102, 103, 104}) {
		t.Fatalf("initial order %v", got)
	}
	// Move Policy memo to the top of To Do.
	c.do("PATCH", "/api/cards/104", map[string]any{"position": 0}).want(t, 200)
	if got := order(11); !equal(got, []float64{104, 101, 102, 103}) {
		t.Fatalf("after reorder %v", got)
	}
	// Move HW 5 into In Progress, above Lab 3.
	moved := c.do("PATCH", "/api/cards/101", map[string]any{"listId": 12, "position": 0}).want(t, 200)
	if moved.num("position") != 0 || !equal(order(12), []float64{101, 105}) || !equal(order(11), []float64{104, 102, 103}) {
		t.Fatalf("cross-list move: in progress %v, to do %v", order(12), order(11))
	}
	// Without a position, a card changing lists lands at the end.
	c.do("PATCH", "/api/cards/102", map[string]any{"listId": 12}).want(t, 200)
	if got := order(12); !equal(got, []float64{101, 105, 102}) {
		t.Fatalf("append %v", got)
	}
	// A position past the end also means the end; archived cards don't count.
	c.do("PATCH", "/api/cards/105", map[string]any{"archived": true}).want(t, 200)
	c.do("PATCH", "/api/cards/101", map[string]any{"position": 9}).want(t, 200)
	if got := order(12); !equal(got, []float64{102, 101}) {
		t.Fatalf("clamped %v", got)
	}
	c.do("PATCH", "/api/cards/101", map[string]any{"position": -1}).wantErr(t, 422, "VALIDATION")
	// New cards go to the end.
	r := c.do("POST", "/api/boards/1/cards", map[string]any{"title": "Last"}).want(t, 201)
	if got := order(11); got[len(got)-1] != r.num("id") {
		t.Fatalf("new card not last: %v", got)
	}
}

func TestArchiveList(t *testing.T) {
	c := newClient(t, "correct horse")
	if got := c.do("POST", "/api/lists/13/archive", nil).want(t, 200).body["archived"]; got != 1.0 {
		t.Fatalf("archived = %v, want 1 (Done on Fall 2026)", got)
	}
	if got := c.do("POST", "/api/lists/13/archive", nil).want(t, 200).body["archived"]; got != 0.0 {
		t.Fatalf("second run archived = %v, want 0", got)
	}
	for _, x := range c.do("GET", "/api/boards/1/cards", nil).want(t, 200).list {
		if x.(map[string]any)["listId"] == 13.0 {
			t.Fatalf("card still unarchived in Done: %v", x)
		}
	}
	c.do("POST", "/api/lists/999/archive", nil).wantErr(t, 404, "NOT_FOUND")
}
