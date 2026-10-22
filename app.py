import socket
from flask import Flask, jsonify, request
from sqlalchemy import text
from db import engine

app = Flask(__name__)

@app.get("/health")
def health():
    """Shallow check used by the ELB target group (no DB dependency)."""
    return jsonify(status="ok", instance=socket.gethostname())

@app.get("/health/deep")
def health_deep():
    with engine.connect() as c:
        c.execute(text("SELECT 1"))
    return jsonify(status="ok", db="reachable")

@app.get("/api/products")
def products():
    category = request.args.get("category")
    max_price = request.args.get("max_price", type=float)
    limit = min(request.args.get("limit", 20, type=int), 100)
    sql = "SELECT id, name, category, price FROM products WHERE 1=1"
    params = {"limit": limit}
    if category:
        sql += " AND category = :category"; params["category"] = category
    if max_price is not None:
        sql += " AND price <= :max_price"; params["max_price"] = max_price
    sql += " ORDER BY price LIMIT :limit"
    with engine.connect() as c:
        rows = c.execute(text(sql), params).mappings().all()
    return jsonify([dict(r) for r in rows])

@app.get("/api/customers/<int:customer_id>/orders")
def customer_orders(customer_id):
    sql = """SELECT o.id, o.total, o.status, o.created_at
             FROM orders o WHERE o.customer_id = :cid
             ORDER BY o.created_at DESC LIMIT 50"""
    with engine.connect() as c:
        rows = c.execute(text(sql), {"cid": customer_id}).mappings().all()
    return jsonify([{**dict(r), "created_at": r["created_at"].isoformat()} for r in rows])

@app.post("/api/orders")
def create_order():
    body = request.get_json(force=True)
    with engine.begin() as c:
        res = c.execute(
            text("INSERT INTO orders (customer_id, total, status) VALUES (:c, :t, 'NEW')"),
            {"c": body["customer_id"], "t": body["total"]})
    return jsonify(id=res.lastrowid), 201

@app.get("/")
def index():
    return jsonify(service="scalable-webapp", instance=socket.gethostname())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
