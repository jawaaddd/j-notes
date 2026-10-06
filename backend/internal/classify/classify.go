// Package classify is the mock-phase stand-in for the voice classifier and the
// duplicate detector. Both are open decisions in the spec; these keyword
// heuristics only exist so ingest produces believable Inbox items.
package classify

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
)

type Tag struct {
	ID   int64
	Name string
}

type Board struct {
	ID          int64
	Name        string
	TagLabel    string // e.g. "Classes"
	SpecialTags []Tag
}

type Voice struct {
	BoardID      *int64
	Title        string
	SpecialTagID *int64
	DueAt        *time.Time
	DueAllDay    bool
	Uncertain    map[string]string
	// Confident is always false in the mock, so every voice entry goes to the
	// Inbox until a real classifier and threshold are chosen.
	Confident bool
}

var (
	fillers   = regexp.MustCompile(`(?i)\b(uh+|um+|erm|like,)\s*`)
	weekdays  = []string{"sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"}
	ordinals  = map[string]int{"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20, "twenty-first": 21, "twenty-second": 22, "twenty-third": 23, "twenty-fourth": 24, "twenty-fifth": 25, "twenty-sixth": 26, "twenty-seventh": 27, "twenty-eighth": 28, "twenty-ninth": 29, "thirtieth": 30, "thirty-first": 31}
	dayPhrase = regexp.MustCompile(`(?i)\b(?:(due|by|before|on)\s+)?(?:the\s+)?(today|tonight|tomorrow|sunday|monday|tuesday|wednesday|thursday|friday|saturday|(\d{1,2})(?:st|nd|rd|th)|` + ordinalAlternation() + `)\b`)
)

func ordinalAlternation() string {
	keys := make([]string, 0, len(ordinals))
	for k := range ordinals {
		keys = append(keys, k)
	}
	// Longest first so "twenty-first" wins over "first".
	for i := range keys {
		for j := i + 1; j < len(keys); j++ {
			if len(keys[j]) > len(keys[i]) {
				keys[i], keys[j] = keys[j], keys[i]
			}
		}
	}
	return strings.Join(keys, "|")
}

// ParseVoice guesses a card from a transcript. Dates are "all day": the end of
// the named day (23:59) in loc, stored in UTC.
func ParseVoice(raw string, boards []Board, now time.Time, loc *time.Location) Voice {
	v := Voice{Uncertain: map[string]string{}}
	text := strings.TrimSpace(fillers.ReplaceAllString(raw, ""))
	lower := strings.ToLower(text)

	// Special tag (and with it, the board): first tag named in the text.
	var label string
search:
	for _, b := range boards {
		for _, t := range b.SpecialTags {
			if containsWord(lower, strings.ToLower(t.Name)) {
				v.BoardID, v.SpecialTagID = ptr(b.ID), ptr(t.ID)
				text = removeWord(text, t.Name)
				break search
			}
		}
	}
	if v.BoardID == nil {
		for _, b := range boards {
			if containsWord(lower, strings.ToLower(b.Name)) {
				v.BoardID = ptr(b.ID)
				label = b.TagLabel
				break
			}
		}
		if v.BoardID == nil && len(boards) > 0 {
			v.BoardID = ptr(boards[0].ID)
			label = boards[0].TagLabel
			v.Uncertain["boardId"] = "no board named"
		}
		if label == "" {
			label = "special tag"
		}
		v.Uncertain["specialTagId"] = "no " + singular(strings.ToLower(label)) + " named"
	}

	// Due date.
	if m := dayPhrase.FindStringSubmatchIndex(text); m != nil {
		prep := strings.ToLower(group(text, m, 1))
		word := strings.ToLower(group(text, m, 2))
		if day, ok := resolveDay(word, group(text, m, 3), now.In(loc)); ok {
			if prep == "before" {
				day = day.AddDate(0, 0, -1)
				v.Uncertain["dueAt"] = fmt.Sprintf("from %q", "before "+word)
			}
			due := time.Date(day.Year(), day.Month(), day.Day(), 23, 59, 0, 0, loc).UTC()
			v.DueAt, v.DueAllDay = &due, true
			text = text[:m[0]] + text[m[1]:]
		}
	}

	v.Title = tidyTitle(text)
	return v
}

func resolveDay(word, digits string, today time.Time) (time.Time, bool) {
	switch word {
	case "today", "tonight":
		return today, true
	case "tomorrow":
		return today.AddDate(0, 0, 1), true
	}
	for i, d := range weekdays {
		if word == d {
			ahead := (i - int(today.Weekday()) + 7) % 7
			if ahead == 0 {
				ahead = 7
			}
			return today.AddDate(0, 0, ahead), true
		}
	}
	n := ordinals[word]
	if digits != "" {
		n, _ = strconv.Atoi(digits)
	}
	if n < 1 || n > 31 {
		return time.Time{}, false
	}
	// Next occurrence of that day of the month, today included.
	for i := 0; i < 3; i++ {
		d := time.Date(today.Year(), today.Month()+time.Month(i), n, 0, 0, 0, 0, today.Location())
		if d.Day() == n && !d.Before(dateOnly(today)) {
			return d, true
		}
	}
	return time.Time{}, false
}

// singular turns a board's special tag label ("Classes", "Areas") into the
// word used in reasons ("class", "area").
func singular(s string) string {
	for _, end := range []string{"sses", "xes", "ches", "shes"} {
		if strings.HasSuffix(s, end) {
			return strings.TrimSuffix(s, "es")
		}
	}
	return strings.TrimSuffix(s, "s")
}

func dateOnly(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

// tidyTitle drops leftover punctuation and connective words and capitalizes.
func tidyTitle(s string) string {
	s = regexp.MustCompile(`\s+`).ReplaceAllString(s, " ")
	s = regexp.MustCompile(`\s+([,.;:])`).ReplaceAllString(s, "$1")
	s = strings.Trim(s, " ,.;:-")
	s = regexp.MustCompile(`(?i)\s+(due|by|on|around|before)$`).ReplaceAllString(s, "")
	s = strings.Trim(s, " ,.;:-")
	if s == "" {
		return "Untitled"
	}
	r := []rune(s)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

// SameTitle reports whether two titles likely name the same thing: equal after
// normalizing, or one contains the other.
func SameTitle(a, b string) bool {
	na, nb := normalize(a), normalize(b)
	if na == "" || nb == "" {
		return false
	}
	if na == nb {
		return true
	}
	short, long := na, nb
	if len(short) > len(long) {
		short, long = long, short
	}
	return len(short) >= 6 && strings.Contains(long, short)
}

// SameDay reports whether two due dates fall on the same day in loc. A missing
// date on either side doesn't rule out a match.
func SameDay(a, b *time.Time, loc *time.Location) bool {
	if a == nil || b == nil {
		return true
	}
	return dateOnly(a.In(loc)).Equal(dateOnly(b.In(loc)))
}

func normalize(s string) string {
	var b strings.Builder
	space := false
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
			space = false
		} else if !space && b.Len() > 0 {
			b.WriteByte(' ')
			space = true
		}
	}
	return strings.TrimSpace(b.String())
}

func containsWord(haystack, word string) bool {
	return regexp.MustCompile(`\b` + regexp.QuoteMeta(word) + `\b`).MatchString(haystack)
}

func removeWord(s, word string) string {
	return regexp.MustCompile(`(?i)\b`+regexp.QuoteMeta(word)+`\b[,:]?`).ReplaceAllString(s, "")
}

func group(s string, m []int, i int) string {
	if m[2*i] < 0 {
		return ""
	}
	return s[m[2*i]:m[2*i+1]]
}

func ptr[T any](v T) *T { return &v }
