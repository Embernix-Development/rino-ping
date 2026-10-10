package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

type Message struct {
	Type string `json:"type"`
	ID   string `json:"id,omitempty"`
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func pingHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	defer conn.Close()

	conn.SetReadLimit(1024)

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			return
		}

		var message Message

		if err := json.Unmarshal(raw, &message); err != nil {
			continue
		}

		if message.Type != "ping" {
			continue
		}

		response := Message{
			Type: "pong",
			ID:   message.ID,
		}

		if err := conn.WriteJSON(response); err != nil {
			return
		}
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set(
		"Content-Type",
		"application/json",
	)

	w.WriteHeader(
		http.StatusOK,
	)

	_, _ = w.Write(
		[]byte(`{"status":"ok"}`),
	)
}

func main() {
	port := flag.String(
		"port",
		"8443",
		"Port to listen on",
	)

	flag.Parse()

	mux := http.NewServeMux()

	mux.HandleFunc(
		"/ping",
		pingHandler,
	)

	mux.HandleFunc(
		"/health",
		healthHandler,
	)

	server := &http.Server{
		Addr: ":" + *port,
		Handler: mux,
		ReadHeaderTimeout:
			5 * time.Second,
	}

	go func() {
		log.Printf(
			"Rino Ping Agent listening on :%s",
			*port,
		)

		if err := server.ListenAndServe(); err != nil &&
			err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	stop := make(
		chan os.Signal,
		1,
	)

	signal.Notify(
		stop,
		syscall.SIGINT,
		syscall.SIGTERM,
	)

	<-stop

	log.Println(
		"Rino Ping Agent shutting down",
	)
}