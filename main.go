package main

import (
	"database/sql"
	"embed"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"math"
	"net/http"
	"net/netip"
	"os"
	"regexp"
	"time"

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

func (s *app) myIpRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Add("Access-Control-Allow-Origin", "*")
	addr, err := netip.ParseAddrPort(r.RemoteAddr)
	if err != nil {
		w.WriteHeader(500)
		w.Write([]byte("Internal error: couldn't understand remote address"))
	} else if !addr.Addr().Is4() {
		w.WriteHeader(500)
		w.Write([]byte("Internal error: address was not IPv4"))
	} else {
		ip := addr.Addr()
		ip_str := fmt.Sprint(ip)
		w.Write([]byte(ip_str))
	}
}

func (s *app) claimRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Add("Access-Control-Allow-Origin", "*")
	name := r.URL.Query().Get("name")
	if name == "" {
		w.WriteHeader(400)
		w.Write([]byte("Name query param was blank"))
	} else if len(name) != 8 {
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
				log.Printf("[%s] = \"%s\"\n", ip, name)
				w.Header().Add("Content-Type", "text/html")
				w.WriteHeader(200)
				page := fmt.Sprintf(`
					<!doctype html>
					<meta name="viewport" content="width=device-width, initial-scale=1">
					The land at %s was claimed for %s.
					<p>
					<a href=/>Back to homepage</a>`, ip, name)
				w.Write([]byte(page))
			}
		}
	}
}

func (s *app) summaryRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Add("Access-Control-Allow-Origin", "*")
	var smallest uint32
	var biggest uint32
	if subnet := r.URL.Query().Get("subnet"); subnet != "" {
		prefix, err := netip.ParsePrefix(subnet)
		if err != nil {
			w.WriteHeader(400)
			w.Write([]byte("Invalid CIDR"))
			return
		}
		if !prefix.Addr().Is4() {
			w.WriteHeader(400)
			w.Write([]byte("We only do IPv4 here"))
			return
		}
		prefix = prefix.Masked()
		smallest_bytes := prefix.Addr().As4()
		smallest = binary.BigEndian.Uint32(smallest_bytes[:])
		biggest = smallest + (math.MaxUint32 >> prefix.Bits())
	} else {
		smallest = 0
		biggest = math.MaxUint32
	}
	res := make(map[string]uint)
	rows, err := s.db.Query("SELECT nick, COUNT(ip) FROM land WHERE ip >= ?1 AND ip <= ?2 GROUP BY nick;", smallest, biggest)
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

//go:embed static/*
var staticContent embed.FS

func main() {
	db, err := sql.Open("sqlite3", "./db.sqlite3")
	if err != nil {
		log.Fatalln("open: ", err)
	}
	staticDir, err := fs.Sub(staticContent, "static")
	if err != nil {
		log.Fatalln("open: ", err)
	}
	a := app{db}
	a.initOrPanic()

	mux := http.NewServeMux()
	mux.HandleFunc("/claim/", a.claimRoute)
	mux.HandleFunc("/summary", a.summaryRoute)
	mux.HandleFunc("/ip", a.myIpRoute)
	// mux.Handle("/", http.FileServer(http.Dir("./static")))
	mux.Handle("/", http.FileServer(http.FS(staticDir)))

	addr := ":80"
	if env_bind := os.Getenv("BIND"); env_bind != "" {
		addr = env_bind
	}

	serve := &http.Server{
		Addr:           addr,
		Handler:        mux,
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		MaxHeaderBytes: 1 << 20,
	}
	log.Println("Serving on", serve.Addr)
	log.Fatalln(serve.ListenAndServe())
}
