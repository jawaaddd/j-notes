// Package backup keeps daily copies of the database: one file per day,
// named notes-YYYY-MM-DD.db, with the oldest removed past a limit.
package backup

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// Copier writes a consistent copy of the database to path, which must not
// exist yet.
type Copier func(path string) error

// Daily makes today's backup if it's missing, then checks again every hour
// until ctx ends. It keeps the newest keep backups.
func Daily(ctx context.Context, dir string, keep int, copyTo Copier, now func() time.Time) {
	for {
		if _, err := Once(dir, keep, copyTo, now()); err != nil {
			slog.Error("backup failed", "dir", dir, "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Hour):
		}
	}
}

// Once makes the backup for day t unless it exists, then prunes. It returns
// the new file's path, or "" if there was nothing to do.
func Once(dir string, keep int, copyTo Copier, t time.Time) (string, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "notes-"+t.Format("2006-01-02")+".db")
	made := ""
	if _, err := os.Stat(path); os.IsNotExist(err) {
		// Copy under a temporary name so a crash never leaves a partial
		// file that looks like a finished backup.
		tmp := path + ".partial"
		os.Remove(tmp)
		if err := copyTo(tmp); err != nil {
			os.Remove(tmp)
			return "", err
		}
		if err := os.Rename(tmp, path); err != nil {
			return "", err
		}
		made = path
		slog.Info("backup written", "path", path)
	}
	return made, prune(dir, keep)
}

func prune(dir string, keep int) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	var names []string
	for _, e := range entries {
		if n := e.Name(); strings.HasPrefix(n, "notes-") && strings.HasSuffix(n, ".db") {
			names = append(names, n)
		}
	}
	slices.Sort(names) // dates sort as text
	for len(names) > keep {
		if err := os.Remove(filepath.Join(dir, names[0])); err != nil {
			return err
		}
		names = names[1:]
	}
	return nil
}
