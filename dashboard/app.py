from flask import Flask
from db import get_db, close_db, init_db

app = Flask(__name__)

app.teardown_appcontext(close_db)

with app.app_context():
    init_db()

@app.get('/')
def index(): ## LEFT JOIN to pull each URL alongside its most recent check only
    db = get_db()
    urls = db.execute('''
        SELECT u.id, u.name, u.url, 
                      c.checked_at, c.status_code, c.response_time_ms, c.is_up
        FROM urls u
        LEFT JOIN (
            SELECT * FROM checks
            WHERE id IN (
                SELECT MAX(id) FROM checks GROUP BY url_id
            )
        ) c ON c.url_id = u.id
        ORDER BY u.name
    ''').fetchall()
    return urls

if __name__ == '__main__':
    app.run(debug=True)


