CREATE TABLE "land" (
    ip INTEGER PRIMARY KEY,
    nick TEXT NOT NULL
);

CREATE INDEX "land_by_name" ON "land" (nick);
