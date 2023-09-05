package main

import (
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"log/slog"
	"math/rand"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"
)

var (
	addr      = flag.String("addr", envOr("ADDR", ":8080"), "listen address")
	slogLevel = flag.String("slog-level", envOr("SLOG_LEVEL", "INFO"), "log level")

	//go:embed static
	staticFiles embed.FS // your static assets

	//go:embed tmpl/*.html
	templateFiles embed.FS // your template files

	//go:embed quotes.json
	quotesJSON []byte
)

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

type Quote struct {
	Quote  string `json:"quote"`
	Person string `json:"person"`
	Source string `json:"source"`
	ID     int    `json:"id"`
}

func main() {
	flag.Parse()

	// Set log level, configure logger
	var programLevel slog.Level
	if err := (&programLevel).UnmarshalText([]byte(*slogLevel)); err != nil {
		fmt.Fprintf(os.Stderr, "invalid log level %s: %v, using INFO\n", *slogLevel, err)
		programLevel = slog.LevelInfo
	}
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		AddSource: true,
		Level:     programLevel,
	})))

	tmpls := template.Must(template.ParseFS(templateFiles, "tmpl/*.html"))
	mux := http.NewServeMux()

	var quotes []Quote
	if err := json.Unmarshal(quotesJSON, &quotes); err != nil {
		slog.Error("can't unmarshal quotes", "err", err)
	}

	for i, q := range quotes {
		q.ID = i
		quotes[i] = q
	}

	mux.Handle("/static/", http.FileServer(http.FS(staticFiles)))

	mux.HandleFunc("/quote.json", func(w http.ResponseWriter, r *http.Request) {
		id := rand.Intn(len(quotes))
		json.NewEncoder(w).Encode(quotes[id])
	})

	mux.HandleFunc("/quotes/", func(w http.ResponseWriter, r *http.Request) {
		id := r.URL.Path[len("/quotes/"):]
		if id == "" {
			http.Error(w, "quote not found, no ID", http.StatusNotFound)
			return
		}

		idInt, err := strconv.Atoi(id)
		if err != nil {
			http.Error(w, "quote not found, invalid ID", http.StatusNotFound)
			return
		}

		if idInt < 0 || idInt >= len(quotes) {
			http.Error(w, "quote not found, ID out of range", http.StatusNotFound)
			return
		}
		q := quotes[idInt]

		if err := tmpls.ExecuteTemplate(w, "index.html", map[string]any{
			"Title": "douglas-adams-quotes/quote/",
			"Quote": q,
		}); err != nil {
			slog.Error("can't execute template", "err", err, "remoteAddr", r.RemoteAddr, "path", r.URL.Path)
			return
		}
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			w.WriteHeader(http.StatusNotFound)
			if err := tmpls.ExecuteTemplate(w, "404.html", map[string]any{
				"Title": "douglas-adams-quotes/",
				"Path":  r.URL.Path,
			}); err != nil {
				slog.Error("can't execute template", "err", err, "remoteAddr", r.RemoteAddr, "path", r.URL.Path)
				return
			}
			return
		}

		id := rand.Intn(len(quotes))

		if err := tmpls.ExecuteTemplate(w, "index.html", map[string]any{
			"Title": "douglas-adams-quotes/",
			"Quote": quotes[id],
		}); err != nil {
			slog.Error("can't execute template", "err", err, "remoteAddr", r.RemoteAddr, "path", r.URL.Path)
			return
		}
	})

	slog.Info("listening", "addr", *addr)
	if err := http.ListenAndServe(*addr, HTTPLog(mux)); err != nil {
		slog.Error("can't listen and serve", "err", err)
		os.Exit(1)
	}
}

type statusResponseWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusResponseWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// HTTPLog automagically logs HTTP traffic.
func HTTPLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, _ := net.SplitHostPort(r.RemoteAddr)

		st := time.Now()
		srw := &statusResponseWriter{
			ResponseWriter: w,
		}

		next.ServeHTTP(srw, r)

		if srw.status == 0 {
			srw.status = http.StatusOK
		}
		dur := time.Since(st)

		attrs := slog.GroupValue(
			slog.String("remote_addr", host),
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.String("user_agent", r.UserAgent()),
			slog.Int("status", srw.status),
			slog.String("request_duration", dur.String()),
			slog.Int64("request_duration_ns", dur.Nanoseconds()),
			slog.String("referer", r.Referer()),
		)

		slog.Debug("http request", "data", attrs)
	})
}
