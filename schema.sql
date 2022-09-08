CREATE TABLE "land" (
    ip INTEGER PRIMARY KEY,
    nick TEXT NOT NULL CHECK,
    created_at TEXT DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'))
);
