// Command server runs the notes-app API. Data is saved to a SQLite file, or
// with NOTES_MOCK=1 kept in memory with the Figma sample data and reset on
// restart.
//
// Environment:
//
//	NOTES_ADDR         listen address (default 127.0.0.1:8080)
//	NOTES_DB           SQLite database file (default notes.db), created if missing
//	NOTES_SAMPLE_DATA  1 to fill a new database with the sample data instead of
//	                   one empty board
//	NOTES_MOCK         1 to keep everything in memory with the sample data
//	NOTES_PASSWORD     the password, replacing any set in the app. Unset, the
//	                   server uses the stored password or runs first-run setup.
//	                   In the mock it defaults to "dev"; set it to an empty
//	                   string there to try first-run setup.
//	NOTES_BACKUPS      folder for daily backups (default: "backups" next to the
//	                   database), keeping the newest 14; "off" turns them off
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"

	"notes-app/internal/api"
	"notes-app/internal/auth"
	"notes-app/internal/backup"
	"notes-app/internal/store/memory"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func run() error {
	addr := envOr("NOTES_ADDR", "127.0.0.1:8080")
	mock := os.Getenv("NOTES_MOCK") == "1"
	password, set := os.LookupEnv("NOTES_PASSWORD")

	var st *memory.Store
	var where, backups string
	if mock {
		if !set {
			password = "dev"
			slog.Warn(`mock mode: NOTES_PASSWORD not set, using password "dev"`)
		}
		st = memory.New(nil, nil)
		if err := st.Seed(); err != nil {
			return err
		}
		where = "mock data, in memory"
	} else {
		where = envOr("NOTES_DB", "notes.db")
		var err error
		if st, err = memory.Open(where, os.Getenv("NOTES_SAMPLE_DATA") == "1", nil, nil); err != nil {
			return err
		}
		defer st.Close()
		backups = envOr("NOTES_BACKUPS", filepath.Join(filepath.Dir(where), "backups"))
	}
	authSvc, err := auth.NewService(st, auth.Config{EnvPassword: password})
	if err != nil {
		return err
	}

	gin.SetMode(gin.ReleaseMode)
	srv := &http.Server{
		Addr:              addr,
		Handler:           api.New(st, authSvc),
		ReadHeaderTimeout: 10 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if backups != "" && backups != "off" {
		go backup.Daily(ctx, backups, 14, st.Backup, time.Now)
	}
	errCh := make(chan error, 1)
	go func() {
		slog.Info("notes-app API listening", "addr", "http://"+addr, "data", where)
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		slog.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
	return nil
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
