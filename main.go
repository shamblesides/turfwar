package main

import (
	"fmt"
	"log"
	"net/http"
	"net/netip"
	"regexp"
	"strings"
	"time"
)

var factionRegexp = regexp.MustCompile("^[0-9a-zA-Z]{8}$")

type app struct {
}

func (s *app) initOrPanic() {
}

func (s *app) listSavForRom(w http.ResponseWriter, r *http.Request) {
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
				msg := fmt.Sprintf("[%s] = \"%s\"", ip, name)
				log.Println(msg)
				w.WriteHeader(200)
				w.Write(([]byte(msg)))
			}
		}
	}
}

func main() {
	a := app{}
	a.initOrPanic()

	mux := http.NewServeMux()
	mux.HandleFunc("/claim/", a.listSavForRom)

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
