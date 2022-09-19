CREATE TABLE "land" (
    ip INTEGER PRIMARY KEY,
    nick TEXT NOT NULL
);

CREATE INDEX "land_by_name" ON "land" (nick);

CREATE TABLE cache (
    key TEXT PRIMARY KEY,
    val TEXT NOT NULL
);
