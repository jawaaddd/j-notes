package backup

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestOnceAndPrune(t *testing.T) {
	dir := t.TempDir()
	copies := 0
	copyTo := func(path string) error {
		copies++
		return os.WriteFile(path, []byte("db"), 0o600)
	}
	day := time.Date(2026, 10, 1, 3, 0, 0, 0, time.UTC)
	for i := range 5 {
		if _, err := Once(dir, 3, copyTo, day.AddDate(0, 0, i)); err != nil {
			t.Fatal(err)
		}
	}
	// A second run on the same day does nothing.
	if made, err := Once(dir, 3, copyTo, day.AddDate(0, 0, 4).Add(time.Hour)); err != nil || made != "" {
		t.Fatalf("made %q, err %v", made, err)
	}
	if copies != 5 {
		t.Fatalf("copies = %d, want 5", copies)
	}
	got, _ := filepath.Glob(filepath.Join(dir, "*"))
	want := []string{"notes-2026-10-03.db", "notes-2026-10-04.db", "notes-2026-10-05.db"}
	if len(got) != len(want) {
		t.Fatalf("files = %v", got)
	}
	for i, w := range want {
		if filepath.Base(got[i]) != w {
			t.Fatalf("files = %v, want %v", got, want)
		}
	}
}
