REDBEAN_VERSION = redbean-asan-2.0.19.com

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

server.com: $(REDBEAN_VERSION) $(shell find src)
	cp $(REDBEAN_VERSION) server.com
	cd src && zip -r ../server.com .

$(REDBEAN_VERSION):
	wget https://redbean.dev/$(REDBEAN_VERSION) -O $(REDBEAN_VERSION) && chmod +x $(REDBEAN_VERSION)

sqlite3.com:
	wget https://redbean.dev/sqlite3.com -O sqlite3.com && chmod +x sqlite3.com

db.sqlite3: sqlite3.com
	./sqlite3.com db.sqlite3 < schema.sql
