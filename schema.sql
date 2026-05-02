CREATE TABLE IF NOT EXISTS urls(
    id          INTEGER   PRIMARY KEY AUTOINCREMENT,
    name        TEXT      NOT NULL,
    url         TEXT      NOT NULL UNIQUE,
    created_at  DATETIME  DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE IF NOT EXISTS checks(
    id                  INTEGER   PRIMARY KEY AUTOINCREMENT,
    url_id              INTEGER   NOT NULL REFERENCES urls(id) ON DELETE CASCADE,
    checked_at          DATETIME  DEFAULT CURRENT_TIMESTAMP,
    status_code         INTEGER,
    response_time_ms    INTEGER,
    is_up               INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS incidents(
    id                  INTEGER   PRIMARY KEY AUTOINCREMENT,
    url_id              INTEGER   NOT NULL REFERENCES urls(id) ON DELETE CASCADE,
    started_at          DATETIME  DEFAULT CURRENT_TIMESTAMP,
    resolved_at         DATETIME,
    duration_seconds    INTEGER,
    alert_fired_at      DATETIME,
    alert_resolved_at   DATETIME
);





