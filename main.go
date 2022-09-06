package main

import (
	"database/sql"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/netip"
	"regexp"
	"strings"
	"time"

	_ "embed"

	_ "github.com/mattn/go-sqlite3"
)

var factionRegexp = regexp.MustCompile("^[0-9a-zA-Z]{8}$")

type app struct {
	db *sql.DB
}

//go:embed migration.sql
var migrations string

func (s *app) initOrPanic() {
	_, err := s.db.Exec(migrations)
	if err != nil {
		log.Fatalln("migrations: ", err)
	}
}

func (s *app) claimRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Add("Access-Control-Allow-Origin", "*")
	if !strings.HasPrefix(r.URL.Path, "/claim/") {
		w.WriteHeader(500)
		w.Write([]byte("Internal error: Unexpected path"))
	} else {
		name := strings.TrimPrefix(r.URL.Path, "/claim/")
		if len(name) != 8 {
			w.WriteHeader(400)
			w.Write([]byte("Name must be exactly 8 characters"))
		} else if !factionRegexp.MatchString(name) {
			w.WriteHeader(400)
			w.Write([]byte("Name must be ASCII alphanumeric"))
		} else {
			addr, err := netip.ParseAddrPort(r.RemoteAddr)
			if err != nil {
				w.WriteHeader(500)
				w.Write([]byte("Internal error: couldn't understand remote address"))
			} else if !addr.Addr().Is4() {
				w.WriteHeader(500)
				w.Write([]byte("Internal error: address was not IPv4"))
			} else {
				ip := addr.Addr()
				ip_bytes := ip.As4()
				ip_uint := binary.BigEndian.Uint32(ip_bytes[:])
				_, err := s.db.Exec("INSERT INTO land (ip, nick) VALUES (?1, ?2) ON CONFLICT (ip) DO UPDATE SET (nick) = (?2)", ip_uint, name)
				if err != nil {
					w.WriteHeader(500)
					w.Write([]byte("Internal error: error while inserting into DB"))
				} else {
					w.Header().Add("Content-Type", "application/json")
					msg := fmt.Sprintf("[%s] = \"%s\"", ip, name)
					log.Println(msg)
					w.WriteHeader(200)
					w.Write(([]byte(msg)))
				}
			}
		}
	}
}

func (s *app) summaryRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Add("Access-Control-Allow-Origin", "*")
	res := make(map[string]uint)
	rows, err := s.db.Query("SELECT nick, COUNT(ip) FROM land GROUP BY ip;")
	if err != nil {
		w.WriteHeader(500)
		w.Write([]byte("Internal error: could not query DB for summary."))
		return
	}
	defer rows.Close()
	for rows.Next() {
		var nick string
		var count uint
		if err := rows.Scan(&nick, &count); err != nil {
			w.WriteHeader(500)
			w.Write([]byte("Internal error: error scanning rows for summary"))
			return
		}
		res[nick] = count
	}
	w.Header().Add("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(res)
}

func main() {
	db, err := sql.Open("sqlite3", "./db.sqlite3")
	if err != nil {
		log.Fatalln("open: ", err)
	}
	a := app{db}
	a.initOrPanic()

	mux := http.NewServeMux()
	mux.HandleFunc("/claim/", a.claimRoute)
	mux.HandleFunc("/summary", a.summaryRoute)
	mux.Handle("/", http.FileServer(http.Dir("./static")))

	serve := &http.Server{
		Addr:           ":8081",
		Handler:        mux,
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		MaxHeaderBytes: 1 << 20,
	}
	log.Println("Serving on", serve.Addr)
	log.Fatalln(serve.ListenAndServe())
}
