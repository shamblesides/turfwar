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

server.com: redbean-asan-2.0.19.com $(shell find src)
	cp redbean-asan-2.0.19.com server.com
	cd src && zip -r ../server.com .

redbean-asan-2.0.19.com:
	wget https://redbean.dev/redbean-asan-2.0.19.com -O redbean-asan-2.0.19.com && chmod +x redbean-asan-2.0.19.com

sqlite3.com:
	wget https://redbean.dev/sqlite3.com -O sqlite3.com && chmod +x sqlite3.com

db.sqlite3: sqlite3.com
	./sqlite3.com db.sqlite3 < schema.sql
