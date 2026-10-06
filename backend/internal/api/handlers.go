package api

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"notes-app/internal/domain"
)

// ---- auth ----

func (h *handlers) authStatus(c *gin.Context) {
	st, err := h.auth.Status()
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, st)
}

func (h *handlers) authSetup(c *gin.Context) {
	var in struct {
		SetupCode  string `json:"setupCode"`
		Password   string `json:"password"`
		DeviceName string `json:"deviceName"`
	}
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	sess, err := h.auth.Setup(in.SetupCode, in.Password, in.DeviceName)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, sess)
}

func (h *handlers) authLogin(c *gin.Context) {
	var in struct {
		Password   string `json:"password"`
		DeviceName string `json:"deviceName"`
	}
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	sess, err := h.auth.Login(in.Password, in.DeviceName)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, sess)
}

func (h *handlers) authLogout(c *gin.Context) {
	if err := h.auth.Logout(currentToken(c)); err != nil {
		fail(c, err)
		return
	}
	noContent(c)
}

func (h *handlers) authPassword(c *gin.Context) {
	var in struct {
		CurrentPassword string `json:"currentPassword"`
		NewPassword     string `json:"newPassword"`
	}
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	if err := h.auth.ChangePassword(currentToken(c), in.CurrentPassword, in.NewPassword); err != nil {
		fail(c, err)
		return
	}
	noContent(c)
}

func (h *handlers) listTokens(c *gin.Context) {
	toks, err := h.auth.ListTokens(currentToken(c))
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, toks)
}

func (h *handlers) createToken(c *gin.Context) {
	var in struct {
		Name string `json:"name"`
	}
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	t, err := h.auth.CreateAPIToken(in.Name)
	if err != nil {
		fail(c, err)
		return
	}
	created(c, t)
}

func (h *handlers) deleteToken(c *gin.Context) {
	id, err := idParam(c, "tokenId", "token")
	if err == nil {
		err = h.auth.DeleteToken(id)
	}
	if err != nil {
		fail(c, err)
		return
	}
	noContent(c)
}

// ---- boards ----

func (h *handlers) listBoards(c *gin.Context) {
	bs, err := h.store.ListBoards()
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, bs)
}

func (h *handlers) createBoard(c *gin.Context) {
	var in domain.BoardCreate
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	b, err := h.store.CreateBoard(in)
	if err != nil {
		fail(c, err)
		return
	}
	created(c, b)
}

func (h *handlers) getBoard(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	d, err := h.store.GetBoardDetail(id)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, d)
}

func (h *handlers) updateBoard(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.BoardPatch
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	b, err := h.store.UpdateBoard(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, b)
}

func (h *handlers) deleteBoard(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.BoardDelete
	if err := bind(c, &in, true); err != nil {
		fail(c, err)
		return
	}
	if err := h.store.DeleteBoard(id, in); err != nil {
		fail(c, err)
		return
	}
	noContent(c)
}

// ---- lists ----

func (h *handlers) listLists(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	ls, err := h.store.ListLists(id)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, ls)
}

func (h *handlers) createList(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.ListCreate
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	l, err := h.store.CreateList(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	created(c, l)
}

func (h *handlers) reorderLists(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.ListOrder
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	ls, err := h.store.ReorderLists(id, in.ListIDs)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, ls)
}

func (h *handlers) updateList(c *gin.Context) {
	id, err := idParam(c, "listId", "list")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.ListPatch
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	l, err := h.store.UpdateList(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, l)
}

func (h *handlers) deleteList(c *gin.Context) {
	id, err := idParam(c, "listId", "list")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.ListDelete
	if err := bind(c, &in, true); err != nil {
		fail(c, err)
		return
	}
	if err := h.store.DeleteList(id, in); err != nil {
		fail(c, err)
		return
	}
	noContent(c)
}

// ---- tags ----

func (h *handlers) listTags(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	ts, err := h.store.ListTags(id)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, ts)
}

func (h *handlers) createTag(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.TagCreate
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	t, err := h.store.CreateTag(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	created(c, t)
}

func (h *handlers) updateTag(c *gin.Context) {
	id, err := idParam(c, "tagId", "tag")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.TagPatch
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	t, err := h.store.UpdateTag(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, t)
}

func (h *handlers) deleteTag(c *gin.Context) {
	id, err := idParam(c, "tagId", "tag")
	if err == nil {
		err = h.store.DeleteTag(id)
	}
	if err != nil {
		fail(c, err)
		return
	}
	noContent(c)
}

// ---- cards ----

func (h *handlers) listCards(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	q, err := cardQuery(c)
	if err != nil {
		fail(c, err)
		return
	}
	cs, err := h.store.ListCards(id, q)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, cs)
}

// cardQuery parses listId, dueFrom, dueTo, archived, and sort. dueFrom and
// dueTo take a full timestamp, or a date (UTC); a date dueTo includes that
// whole day.
func cardQuery(c *gin.Context) (domain.CardQuery, error) {
	q := domain.CardQuery{Sort: domain.SortDue}
	if v := c.Query("listId"); v != "" {
		id, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			return q, domain.ErrValidation("listId", "listId must be a number")
		}
		q.ListID = &id
	}
	for _, p := range []struct {
		name  string
		dst   **time.Time
		isEnd bool
	}{{"dueFrom", &q.DueFrom, false}, {"dueTo", &q.DueTo, true}} {
		v := c.Query(p.name)
		if v == "" {
			continue
		}
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			if p.isEnd {
				t = t.Add(time.Second) // make a timestamp dueTo inclusive
			}
			*p.dst = &t
		} else if d, err := time.Parse(time.DateOnly, v); err == nil {
			if p.isEnd {
				d = d.AddDate(0, 0, 1)
			}
			*p.dst = &d
		} else {
			return q, domain.ErrValidation(p.name, p.name+" must be a date (2026-10-01) or ISO 8601 timestamp")
		}
	}
	if v := c.Query("archived"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return q, domain.ErrValidation("archived", "archived must be true or false")
		}
		q.Archived = b
	}
	if v := c.Query("sort"); v != "" {
		switch s := domain.CardSort(v); s {
		case domain.SortDue, domain.SortCreated, domain.SortTitle:
			q.Sort = s
		default:
			return q, domain.ErrValidation("sort", "sort must be due, created, or title")
		}
	}
	return q, nil
}

func (h *handlers) createCard(c *gin.Context) {
	id, err := idParam(c, "boardId", "board")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.CardCreate
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	card, err := h.store.CreateCard(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	created(c, card)
}

func (h *handlers) getCard(c *gin.Context) {
	id, err := idParam(c, "cardId", "card")
	if err != nil {
		fail(c, err)
		return
	}
	card, err := h.store.GetCard(id)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, card)
}

func (h *handlers) updateCard(c *gin.Context) {
	id, err := idParam(c, "cardId", "card")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.CardPatch
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	card, err := h.store.UpdateCard(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, card)
}

func (h *handlers) markDone(c *gin.Context) {
	id, err := idParam(c, "cardId", "card")
	if err != nil {
		fail(c, err)
		return
	}
	card, err := h.store.MarkDone(id)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, card)
}

func (h *handlers) deleteCard(c *gin.Context) {
	id, err := idParam(c, "cardId", "card")
	if err == nil {
		err = h.store.DeleteCard(id)
	}
	if err != nil {
		fail(c, err)
		return
	}
	noContent(c)
}

func (h *handlers) saveNotes(c *gin.Context) {
	id, err := idParam(c, "cardId", "card")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.NotesPut
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	res, err := h.store.SaveNotes(id, in.Blocks)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, res)
}

func (h *handlers) moveCards(c *gin.Context) {
	var in domain.CardMove
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	cs, err := h.store.MoveCards(in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, cs)
}

// ---- inbox ----

func (h *handlers) listInbox(c *gin.Context) {
	var typ *domain.InboxType
	if v := c.Query("type"); v != "" {
		switch t := domain.InboxType(v); t {
		case domain.InboxVoice, domain.InboxChange, domain.InboxDuplicate:
			typ = &t
		default:
			fail(c, domain.ErrValidation("type", "type must be voice, change, or duplicate"))
			return
		}
	}
	list, err := h.store.ListInbox(typ)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, list)
}

func (h *handlers) resolveInbox(c *gin.Context) {
	id, err := idParam(c, "itemId", "inbox item")
	if err != nil {
		fail(c, err)
		return
	}
	var in domain.InboxResolve
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	res, err := h.store.ResolveInbox(id, in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, res)
}

// ---- ingest and sources ----

func (h *handlers) ingest(c *gin.Context) {
	var in domain.IngestBatch
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	results, err := h.store.Ingest(in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, gin.H{"results": results})
}

func (h *handlers) listSources(c *gin.Context) {
	srcs, err := h.store.ListSources()
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, srcs)
}

func (h *handlers) heartbeat(c *gin.Context) {
	var in domain.Heartbeat
	if err := bind(c, &in, false); err != nil {
		fail(c, err)
		return
	}
	src, err := h.store.Heartbeat(c.Param("name"), in)
	if err != nil {
		fail(c, err)
		return
	}
	ok(c, src)
}
