// Command server runs the notes-app API. In the mock phase all data lives in
// memory, seeded with the Figma sample data, and resets on restart.
//
// Environment:
//
//	NOTES_ADDR      listen address (default 127.0.0.1:8080)
//	NOTES_PASSWORD  the password; defaults to "dev" in the mock. Set it to an
//	                empty string to start with no password and try first-run setup.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"

	"notes-app/internal/api"
	"notes-app/internal/auth"
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
	password, set := os.LookupEnv("NOTES_PASSWORD")
	if !set {
		password = "dev"
		slog.Warn(`mock mode: NOTES_PASSWORD not set, using password "dev"`)
	}

	st := memory.New(nil, nil)
	if err := st.Seed(); err != nil {
		return err
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
	errCh := make(chan error, 1)
	go func() {
		slog.Info("notes-app API listening (mock data, in memory)", "addr", "http://"+addr)
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
