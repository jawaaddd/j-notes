package classify

import (
	"testing"
	"time"
)

func TestParseVoice(t *testing.T) {
	loc := time.UTC
	tue := time.Date(2026, 10, 6, 12, 0, 0, 0, loc) // a Tuesday
	boards := []Board{
		{ID: 1, Name: "Fall 2026", TagLabel: "Classes", SpecialTags: []Tag{{22, "DiffEq"}, {23, "Robotics"}, {24, "AI Policy"}}},
		{ID: 2, Name: "Personal", TagLabel: "Areas", SpecialTags: []Tag{{29, "Home"}}},
	}
	endOf := func(y int, m time.Month, d int) time.Time { return time.Date(y, m, d, 23, 59, 0, 0, loc) }

	cases := []struct {
		raw          string
		title        string
		board, tag   int64
		due          time.Time
		uncertainKey string
	}{
		{"uh robotics, start reading the particle filter chapter before thursday", "Start reading the particle filter chapter",
			1, 23, endOf(2026, 10, 7), "dueAt"},
		{"policy memo due the fourteenth, around two pages", "Policy memo, around two pages",
			1, 0, endOf(2026, 10, 14), "specialTagId"},
		{"home: hang the shelf tomorrow", "Hang the shelf", 2, 29, endOf(2026, 10, 7), ""},
		{"diffeq quiz on tuesday", "Quiz", 1, 22, endOf(2026, 10, 13), ""},
		{"pay rent by the 3rd", "Pay rent", 1, 0, endOf(2026, 11, 3), "specialTagId"},
	}
	for _, tc := range cases {
		v := ParseVoice(tc.raw, boards, tue, loc)
		if v.Title != tc.title {
			t.Errorf("%q: title = %q, want %q", tc.raw, v.Title, tc.title)
		}
		if v.BoardID == nil || *v.BoardID != tc.board {
			t.Errorf("%q: board = %v, want %d", tc.raw, v.BoardID, tc.board)
		}
		if (tc.tag == 0) != (v.SpecialTagID == nil) || (v.SpecialTagID != nil && *v.SpecialTagID != tc.tag) {
			t.Errorf("%q: tag = %v, want %d", tc.raw, v.SpecialTagID, tc.tag)
		}
		if v.DueAt == nil || !v.DueAt.Equal(tc.due) || !v.DueAllDay {
			t.Errorf("%q: due = %v, want %v", tc.raw, v.DueAt, tc.due)
		}
		if tc.uncertainKey != "" && v.Uncertain[tc.uncertainKey] == "" {
			t.Errorf("%q: want %s marked uncertain, got %v", tc.raw, tc.uncertainKey, v.Uncertain)
		}
		if v.Confident {
			t.Errorf("%q: the mock is never confident", tc.raw)
		}
	}
	if got := ParseVoice("policy memo", boards, tue, loc).Uncertain["specialTagId"]; got != "no class named" {
		t.Errorf("reason = %q", got)
	}
}

func TestSameTitle(t *testing.T) {
	for _, tc := range []struct {
		a, b string
		want bool
	}{
		{"HW 6: Laplace transforms", "hw 6 laplace transforms", true},
		{"HW 6: Laplace transforms", "Laplace transforms", true},
		{"HW 6: Laplace transforms", "HW 7: Systems", false},
		{"Lab", "Lab 3: A* path planner", false}, // too short to count as contained
	} {
		if got := SameTitle(tc.a, tc.b); got != tc.want {
			t.Errorf("SameTitle(%q, %q) = %v", tc.a, tc.b, got)
		}
	}
}
