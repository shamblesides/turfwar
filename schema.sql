CREATE TABLE "land" (
    ip INTEGER PRIMARY KEY,
    nick TEXT NOT NULL,
    created_at TEXT DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'))
);

CREATE INDEX "land_by_name" ON "land" (nick);
