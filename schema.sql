CREATE TABLE "land" (
    ip INTEGER PRIMARY KEY,
    nick TEXT NOT NULL
);

CREATE INDEX "land_by_name" ON "land" (nick);

CREATE TABLE cache (
    id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    val TEXT NOT NULL
);

CREATE UNIQUE INDEX cache_by_key ON cache (key);
