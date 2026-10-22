from urllib.parse import quote_plus
from sqlalchemy import create_engine
import config

def build_engine(pooled: bool = True):
    url = (f"mysql+pymysql://{config.DB_USER}:{quote_plus(config.DB_PASSWORD)}"
           f"@{config.DB_HOST}/{config.DB_NAME}")
    if not pooled:  # used by benchmarks to show pooling impact
        from sqlalchemy.pool import NullPool
        return create_engine(url, poolclass=NullPool)
    return create_engine(
        url,
        pool_size=config.POOL_SIZE,
        max_overflow=config.MAX_OVERFLOW,
        pool_recycle=config.POOL_RECYCLE,   # avoid stale connections after RDS failover
        pool_timeout=config.POOL_TIMEOUT,
        pool_pre_ping=True,
    )

engine = build_engine()
