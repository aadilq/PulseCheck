from flask import Flask
from db import get_db, close_db, init_db

app = Flask(__name__)

app.teardown_appcontext(close_db)

with app.app_context():
    init_db()

if __name__ == '__main__':
    app.run()


