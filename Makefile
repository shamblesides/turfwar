default: server.com

.PHONY: clean
clean:
	rm -f *.com db.sqlite3* *.log

.PHONY: dev
dev: server.com db.sqlite3
	./server.com -D src

.PHONY: update
update:
	cd src && zip -r ../server.com .

server.com: redbean-2.0.18.com $(shell find src)
	cp redbean-2.0.18.com server.com
	cd src && zip -r ../server.com .

redbean-2.0.18.com:
	curl https://redbean.dev/redbean-2.0.18.com > redbean-2.0.18.com && chmod +x redbean-2.0.18.com

sqlite3.com:
	curl https://redbean.dev/sqlite3.com > sqlite3.com && chmod +x sqlite3.com

db.sqlite3: sqlite3.com
	./sqlite3.com db.sqlite3 < schema.sql
