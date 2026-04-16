package main

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
	"time"
)

type response struct {
	Timestamp string `json:"timestamp"`
	IP        string `json:"ip"`
}

func getClientIP(r *http.Request) string {
	if ip := r.Header.Get("X-Forwarded-For"); ip != "" {
		// X-Forwarded-For can contain a comma-separated list; take the first
		host, _, err := net.SplitHostPort(ip)
		if err == nil {
			return host
		}
		return ip
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func handler(w http.ResponseWriter, r *http.Request) {
	ip := getClientIP(r)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response{
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		IP:        ip,
	})
	log.Printf("request from %s", ip)
}

func main() {
	http.HandleFunc("/", handler)
	log.Println("Listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

