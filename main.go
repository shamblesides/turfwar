package main

import (
	"database/sql"
	"embed"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"html"
	"io/fs"
	"log"
	"math"
	"net/http"
	"net/netip"
	"os"
	"path"
	"regexp"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

var invalidNameRegexp = regexp.MustCompile("[^!-~]")

type app struct {
	db         *sql.DB
	claims_log *os.File
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

func (s *app) boardRoute(w http.ResponseWriter, r *http.Request) {
	type leader struct {
		Name  string `json:"name"`
		Count uint   `json:"count"`
	}
	type board struct {
		Leaders []*leader `json:"leaders"`
	}
	w.Header().Add("Access-Control-Allow-Origin", "*")
	stmt, err := s.db.Prepare("SELECT nick AS name, COUNT(ip) AS count FROM land WHERE ip >= ?1 AND ip <= ?2 GROUP BY nick ORDER BY count DESC LIMIT 1")
	if err != nil {
		w.WriteHeader(500)
		w.Write([]byte("Internal error: prepared statement failed"))
		return
	}
	leaders := make([]*leader, 0, 256)
	for smallest := 0; smallest < 0x1_0000_0000; smallest += 0x100_0000 {
		res := stmt.QueryRow(smallest, smallest+0xFF_FFFF)
		var record leader
		if err := res.Scan(&record.Name, &record.Count); err != nil {
			if err == sql.ErrNoRows {
				leaders = append(leaders, nil)
			} else {
				w.WriteHeader(500)
				w.Write([]byte("Internal error: error scanning rows for board"))
				return
			}
		} else {
			leaders = append(leaders, &record)
		}
	}

	out := board{leaders}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(out)
}

func (s *app) claimRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Add("Access-Control-Allow-Origin", "*")
	name := r.URL.Query().Get("name")
	if name == "" {
		w.WriteHeader(400)
		w.Write([]byte("Name query param was blank"))
	} else if len(name) > 40 {
		w.WriteHeader(400)
		w.Write([]byte("Name must be no more than 40 characters"))
	} else if invalid := invalidNameRegexp.FindString(name); invalid != "" {
		w.WriteHeader(400)
		w.Write([]byte(fmt.Sprintf("Invalid character in name: \"%s\"", invalid)))
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
				now := time.Now().UTC()
				timestamp_partial := now.Format("2006-01-02T15:04:05")
				millis := now.Nanosecond() / 1000000
				log_line := fmt.Sprintf("%s.%.3dZ\t%s\t%s\n", timestamp_partial, millis, ip, name)
				s.claims_log.WriteString(log_line)

				w.Header().Add("Content-Type", "text/html")
				w.WriteHeader(200)
				escaped_name := html.EscapeString(name)
				page := fmt.Sprintf(`
					<!doctype html>
					<title>The land at %s was claimed for %s.</title>
					<meta name="viewport" content="width=device-width, initial-scale=1">
					The land at %s was claimed for %s.
					<p>
					<a href=/>Back to homepage</a>`, ip, escaped_name, ip, escaped_name)
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
	tls_dir := flag.String("tls", "", "Path to directory containing fullchain.pem and privkey.pem. Optional")
	http_addr := flag.String("bind", ":80", "Address to bind HTTP server")
	flag.Parse()

	db, err := sql.Open("sqlite3", "./db.sqlite3")
	if err != nil {
		log.Fatalln("open db: ", err)
	}
	claims_log, err := os.OpenFile("claims.log", os.O_WRONLY|os.O_APPEND|os.O_CREATE, os.FileMode(0644))
	if err != nil {
		log.Fatalln("open claims log: ", err)
	}
	staticDir, err := fs.Sub(staticContent, "static")
	if err != nil {
		log.Fatalln("fs.sub: ", err)
	}
	a := app{db, claims_log}

	mux := http.NewServeMux()
	mux.HandleFunc("/board", a.boardRoute)
	mux.HandleFunc("/claim", a.claimRoute)
	mux.HandleFunc("/summary", a.summaryRoute)
	mux.HandleFunc("/ip", a.myIpRoute)
	mux.Handle("/", http.FileServer(http.FS(staticDir)))

	if *tls_dir != "" {
		serve := &http.Server{
			Addr:           ":443",
			Handler:        mux,
			ReadTimeout:    10 * time.Second,
			WriteTimeout:   10 * time.Second,
			MaxHeaderBytes: 32 << 10,
		}
		cert_path := path.Join(*tls_dir, "fullchain.pem")
		priv_path := path.Join(*tls_dir, "privkey.pem")
		go func() {
			log.Println("Serving HTTPS on", serve.Addr)
			log.Fatalln(serve.ListenAndServeTLS(cert_path, priv_path))
		}()
	}

	serve := &http.Server{
		Addr:           *http_addr,
		Handler:        mux,
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		MaxHeaderBytes: 32 << 10,
	}
	log.Println("Serving HTTP on", serve.Addr)
	log.Fatalln(serve.ListenAndServe())
}
