// Command served is the Oversea API server binary.
//
// Usage:
//
//	LOCK_SERVER_KEY=<...> JWT_SECRET=<...> go run ./cmd/served
//
// See internal/config for the full list of environment variables and defaults.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"oversea/server/internal/api"
	"oversea/server/internal/config"
	"oversea/server/internal/store"
)

func main() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	cfg := config.Load()

	st, err := store.Open(cfg.DBPath)
	if err != nil {
		log.Fatalf("store: %v", err)
	}
	defer st.Close()

	srv := api.New(cfg, st)

	httpServer := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Run in a goroutine so we can shut down on SIGINT/SIGTERM.
	errCh := make(chan error, 1)
	go func() {
		log.Printf("oversea server listening on %s", cfg.ListenAddr)
		errCh <- httpServer.ListenAndServe()
	}()

	// Graceful shutdown on signal.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-errCh:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server: %v", err)
		}
	case <-stop:
		log.Println("shutting down...")
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(ctx); err != nil {
			log.Printf("shutdown: %v", err)
		}
	}
}
