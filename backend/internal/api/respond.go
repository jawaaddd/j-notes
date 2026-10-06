package api

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"notes-app/internal/domain"
)

// fail writes err in the API's error shape. Anything that isn't a
// *domain.Error is logged and reported as a plain 500.
func fail(c *gin.Context, err error) {
	var de *domain.Error
	if !errors.As(err, &de) {
		slog.Error("request failed", "method", c.Request.Method, "path", c.FullPath(), "err", err)
		de = domain.ErrInternal()
	}
	c.AbortWithStatusJSON(de.Status, gin.H{"error": de})
}

// bind decodes the JSON body into dst. An empty body is allowed when
// optional is true and leaves dst untouched.
func bind(c *gin.Context, dst any, optional bool) error {
	dec := json.NewDecoder(c.Request.Body)
	if err := dec.Decode(dst); err != nil {
		if errors.Is(err, io.EOF) {
			if optional {
				return nil
			}
			return domain.ErrValidation("body", "request body is required")
		}
		var typeErr *json.UnmarshalTypeError
		if errors.As(err, &typeErr) {
			return domain.ErrValidation(typeErr.Field, typeErr.Field+" has the wrong type")
		}
		if strings.Contains(err.Error(), "parsing time") {
			return domain.ErrValidation("body", "timestamps must be ISO 8601, e.g. 2026-10-09T03:59:00Z")
		}
		return domain.ErrValidation("body", "request body is not valid JSON")
	}
	return nil
}

// idParam reads a numeric path parameter; anything else is an unknown id.
func idParam(c *gin.Context, name, what string) (int64, error) {
	raw := c.Param(name)
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || id <= 0 {
		return 0, domain.ErrNotFound(what, raw)
	}
	return id, nil
}

func ok(c *gin.Context, v any)      { c.JSON(http.StatusOK, v) }
func created(c *gin.Context, v any) { c.JSON(http.StatusCreated, v) }
func noContent(c *gin.Context)      { c.Status(http.StatusNoContent) }
