package domain

import (
	"fmt"
	"net/http"
)

// Error is the one error shape the API returns:
// {"error": {"code": "...", "message": "...", "details": {...}}}.
type Error struct {
	Status  int            `json:"-"`
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details"`
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

func newErr(status int, code, msg string, details map[string]any) *Error {
	if details == nil {
		details = map[string]any{}
	}
	return &Error{Status: status, Code: code, Message: msg, Details: details}
}

func ErrUnauthorized() *Error {
	return newErr(http.StatusUnauthorized, "UNAUTHORIZED", "missing or invalid bearer token", nil)
}

func ErrInvalidPassword() *Error {
	return newErr(http.StatusUnauthorized, "INVALID_PASSWORD", "wrong password", nil)
}

func ErrInvalidSetupCode() *Error {
	return newErr(http.StatusUnauthorized, "INVALID_SETUP_CODE", "wrong setup code; it is printed in the server log", nil)
}

func ErrSetupRequired() *Error {
	return newErr(http.StatusConflict, "SETUP_REQUIRED", "no password is set yet; finish first-run setup", nil)
}

func ErrAlreadySetUp() *Error {
	return newErr(http.StatusConflict, "ALREADY_SET_UP", "a password is already set", nil)
}

func ErrPasswordFromEnv() *Error {
	return newErr(http.StatusConflict, "PASSWORD_FROM_ENV", "the password comes from NOTES_PASSWORD; change it there", nil)
}

func ErrRateLimited(retryAfterSeconds int) *Error {
	return newErr(http.StatusTooManyRequests, "RATE_LIMITED",
		fmt.Sprintf("too many failed attempts; try again in %ds", retryAfterSeconds),
		map[string]any{"retryAfterSeconds": retryAfterSeconds})
}

// ErrNotFound reports an unknown id, e.g. ErrNotFound("card", 7).
func ErrNotFound(what string, id any) *Error {
	return newErr(http.StatusNotFound, "NOT_FOUND", fmt.Sprintf("%s %v not found", what, id),
		map[string]any{"resource": what, "id": id})
}

// ErrValidation reports a bad or missing field; details.field names it.
func ErrValidation(field, msg string) *Error {
	return newErr(http.StatusUnprocessableEntity, "VALIDATION", msg, map[string]any{"field": field})
}

func ErrCrossBoard(field string, id int64) *Error {
	return newErr(http.StatusUnprocessableEntity, "CROSS_BOARD",
		fmt.Sprintf("%s %d belongs to a different board", field, id),
		map[string]any{"field": field, "id": id})
}

func ErrNotSpecial(tagID int64) *Error {
	return newErr(http.StatusUnprocessableEntity, "NOT_SPECIAL",
		fmt.Sprintf("tag %d is not a special tag", tagID), map[string]any{"field": "specialTagId", "id": tagID})
}

func ErrLastOfKind(kind ListKind) *Error {
	return newErr(http.StatusUnprocessableEntity, "LAST_OF_KIND",
		fmt.Sprintf("a board must keep at least one %s list", kind), map[string]any{"kind": kind})
}

func ErrSystemTag(msg string) *Error {
	return newErr(http.StatusUnprocessableEntity, "SYSTEM_TAG", msg, nil)
}

func ErrInvalidAction(msg string) *Error {
	return newErr(http.StatusUnprocessableEntity, "INVALID_ACTION", msg, nil)
}

func ErrBoardHasCards(n int) *Error {
	return newErr(http.StatusConflict, "BOARD_HAS_CARDS",
		fmt.Sprintf("board has %d cards; choose to delete or move them", n), map[string]any{"cardCount": n})
}

func ErrListHasCards(n int) *Error {
	return newErr(http.StatusConflict, "LIST_HAS_CARDS",
		fmt.Sprintf("list has %d cards; give a moveToListId", n), map[string]any{"cardCount": n})
}

func ErrInternal() *Error {
	return newErr(http.StatusInternalServerError, "INTERNAL", "internal server error", nil)
}
