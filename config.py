"""Configuration. On AWS the DB password comes from Secrets Manager (via the
instance's IAM role). Locally, set DB_PASSWORD in the environment."""
import json, os
import boto3

def _load_credentials():
    secret_arn = os.getenv("DB_SECRET_ARN")
    if secret_arn:
        client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "ap-south-1"))
        secret = json.loads(client.get_secret_value(SecretId=secret_arn)["SecretString"])
        return secret["username"], secret["password"]
    return os.getenv("DB_USER", "root"), os.getenv("DB_PASSWORD", "")

DB_USER, DB_PASSWORD = _load_credentials()
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_NAME = os.getenv("DB_NAME", "appdb")

# Connection pooling (one pool per gunicorn worker)
POOL_SIZE = int(os.getenv("DB_POOL_SIZE", 10))
MAX_OVERFLOW = int(os.getenv("DB_MAX_OVERFLOW", 5))
POOL_RECYCLE = int(os.getenv("DB_POOL_RECYCLE", 1800))
POOL_TIMEOUT = int(os.getenv("DB_POOL_TIMEOUT", 10))
