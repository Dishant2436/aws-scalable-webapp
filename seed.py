"""Seed ~200k orders so index impact is measurable.
Usage: DB_HOST=... DB_PASSWORD=... python db/seed.py"""
import os, random, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
from sqlalchemy import text
from db import engine

CATS = ["books", "electronics", "home", "toys", "sports", "fashion"]
with engine.begin() as c:
    c.execute(text("INSERT INTO customers (name,email) VALUES " +
        ",".join(f"('User{i}','u{i}@example.com')" for i in range(1, 5001))))
    c.execute(text("INSERT INTO products (name,category,price) VALUES " +
        ",".join(f"('Item{i}','{random.choice(CATS)}',{round(random.uniform(5,500),2)})" for i in range(1, 20001))))
    for _ in range(200):  # 200 batches x 1000 = 200k orders
        vals = ",".join(f"({random.randint(1,5000)},{round(random.uniform(10,900),2)},'DONE')" for _ in range(1000))
        c.execute(text(f"INSERT INTO orders (customer_id,total,status) VALUES {vals}"))
print("Seed complete")
