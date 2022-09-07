default: server.com

.PHONY: clean
clean:
	rm -f *.com

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

db.sqlite3:
	sqlite3 db.sqlite3 < schema.sql
