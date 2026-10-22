"""Load test to trigger Auto Scaling.
  pip install locust
  locust -f loadtest/locustfile.py --host http://<ALB_DNS> -u 300 -r 20 -t 10m --headless
Baseline: run at ~100 users, then spike to 300 (3x) and watch the ASG in the console."""
import random
from locust import HttpUser, task, between

class Shopper(HttpUser):
    wait_time = between(0.1, 0.5)

    @task(5)
    def browse(self):
        self.client.get(f"/api/products?category={random.choice(['books','toys','home'])}&max_price=100")

    @task(3)
    def history(self):
        self.client.get(f"/api/customers/{random.randint(1,5000)}/orders", name="/api/customers/[id]/orders")

    @task(1)
    def order(self):
        self.client.post("/api/orders", json={"customer_id": random.randint(1,5000), "total": 49.99})
