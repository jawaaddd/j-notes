// Package api is the Gin HTTP layer: routing, auth middleware, request
// parsing, and response shapes. Business rules live behind store.Store.
package api

import (
	"fmt"
	"strings"

	"github.com/gin-gonic/gin"

	"notes-app/internal/auth"
	"notes-app/internal/domain"
	"notes-app/internal/store"
)

type handlers struct {
	store store.Store
	auth  *auth.Service
}

const tokenKey = "authToken"

// New builds the router. Every /api route except the auth entry points
// requires a bearer token.
func New(st store.Store, authSvc *auth.Service) *gin.Engine {
	h := &handlers{store: st, auth: authSvc}
	r := gin.New()
	if gin.Mode() != gin.TestMode {
		r.Use(gin.Logger())
	}
	r.Use(gin.CustomRecovery(func(c *gin.Context, rec any) {
		fail(c, fmt.Errorf("panic: %v", rec))
	}))
	r.HandleMethodNotAllowed = true
	r.NoRoute(func(c *gin.Context) { fail(c, domain.ErrNotFound("route", c.Request.URL.Path)) })
	r.NoMethod(func(c *gin.Context) { fail(c, domain.ErrNotFound("route", c.Request.Method+" "+c.Request.URL.Path)) })

	r.GET("/healthz", func(c *gin.Context) { ok(c, gin.H{"ok": true}) })

	open := r.Group("/api/auth")
	open.GET("/status", h.authStatus)
	open.POST("/setup", h.authSetup)
	open.POST("/login", h.authLogin)

	a := r.Group("/api", h.requireAuth)
	a.POST("/auth/logout", h.authLogout)
	a.PUT("/auth/password", h.authPassword)
	a.GET("/tokens", h.listTokens)
	a.POST("/tokens", h.createToken)
	a.DELETE("/tokens/:tokenId", h.deleteToken)

	a.GET("/boards", h.listBoards)
	a.POST("/boards", h.createBoard)
	a.GET("/boards/:boardId", h.getBoard)
	a.PATCH("/boards/:boardId", h.updateBoard)
	a.DELETE("/boards/:boardId", h.deleteBoard)

	a.GET("/boards/:boardId/lists", h.listLists)
	a.POST("/boards/:boardId/lists", h.createList)
	a.PUT("/boards/:boardId/lists/order", h.reorderLists)
	a.PATCH("/lists/:listId", h.updateList)
	a.DELETE("/lists/:listId", h.deleteList)
	a.POST("/lists/:listId/archive", h.archiveList)

	a.GET("/boards/:boardId/tags", h.listTags)
	a.POST("/boards/:boardId/tags", h.createTag)
	a.PATCH("/tags/:tagId", h.updateTag)
	a.DELETE("/tags/:tagId", h.deleteTag)

	a.GET("/boards/:boardId/cards", h.listCards)
	a.POST("/boards/:boardId/cards", h.createCard)
	a.POST("/cards/move", h.moveCards)
	a.GET("/cards/:cardId", h.getCard)
	a.PATCH("/cards/:cardId", h.updateCard)
	a.POST("/cards/:cardId/done", h.markDone)
	a.DELETE("/cards/:cardId", h.deleteCard)
	a.PUT("/cards/:cardId/notes", h.saveNotes)

	a.GET("/inbox", h.listInbox)
	a.POST("/inbox/:itemId/resolve", h.resolveInbox)

	a.POST("/ingest", h.ingest)
	a.GET("/sources", h.listSources)
	a.POST("/sources/:name/heartbeat", h.heartbeat)

	return r
}

func (h *handlers) requireAuth(c *gin.Context) {
	scheme, tok, found := strings.Cut(c.GetHeader("Authorization"), " ")
	if !found || !strings.EqualFold(scheme, "Bearer") || strings.TrimSpace(tok) == "" {
		fail(c, domain.ErrUnauthorized())
		return
	}
	t, err := h.auth.Authenticate(strings.TrimSpace(tok))
	if err != nil {
		fail(c, err)
		return
	}
	c.Set(tokenKey, t)
	c.Next()
}

func currentToken(c *gin.Context) domain.AuthToken {
	return c.MustGet(tokenKey).(domain.AuthToken)
}
