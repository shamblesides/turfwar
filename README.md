# IPv4 Turf War

It's a game. There's a little webserver. The goal is to access it from
as many IP addresses as you can.

Get creative!

Canonical instance is here: http://ipv4.games

### How it works

It's a Go server that uses SQLite as a glorified key-value store.
Serves up a fairly plain HTML frontend.

```sh
make dev
```
