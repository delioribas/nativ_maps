// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

// Command proxy is a standalone server around package nativproxy, with
// nothing but net/http.
//
//	PROXY_TOKEN=… AWS_REGION=us-east-1 go run .
//
// The variables are the same in every reference proxy; see doc/PROXY.md.
package main

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/delioribas/nativ_maps/proxies/go/nativproxy"
)

func main() {
	port := getenv("PORT", "8080")
	basePath := getenv("PROXY_BASE_PATH", "/geo")
	token := os.Getenv("PROXY_TOKEN")
	region := os.Getenv("AWS_REGION")
	if token == "" || region == "" {
		fmt.Fprintln(os.Stderr, "PROXY_TOKEN and AWS_REGION are required.")
		os.Exit(1)
	}

	// Ctrl-C locally, SIGTERM from Docker or Kubernetes: finish the requests
	// in flight, then stop.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	proxy, err := nativproxy.New(ctx, nativproxy.Options{
		Region:    region,
		Authorize: bearerToken(token),
		APIKey:    os.Getenv("ALS_API_KEY"),
		PublicURL: os.Getenv("PROXY_PUBLIC_URL"),
	})
	if err != nil {
		log.Fatal(err)
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           proxy.Handler(basePath),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()

	log.Printf("nativ_maps proxy on :%s%s", port, basePath)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

// bearerToken is a shared token, to try the proxy. In production, check your
// own session here: your JWT, your cookie, whatever your backend already uses.
func bearerToken(token string) func(context.Context, http.Header) bool {
	expected := []byte("Bearer " + token)
	return func(_ context.Context, header http.Header) bool {
		given := []byte(header.Get("Authorization"))
		// Constant time, so the comparison doesn't leak how much matched.
		return subtle.ConstantTimeCompare(given, expected) == 1
	}
}

func getenv(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
