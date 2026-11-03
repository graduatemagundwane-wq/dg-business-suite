import os
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

DATABASE_URL=os.getenv('DATABASE_URL', 'sqlite:///./pash_dev.db')
if DATABASE_URL.startswith('postgres://'): DATABASE_URL='postgresql+psycopg://'+DATABASE_URL.split('://',1)[1]
if DATABASE_URL.startswith('postgresql://'): DATABASE_URL='postgresql+psycopg://'+DATABASE_URL.split('://',1)[1]
engine=create_engine(DATABASE_URL,connect_args={'check_same_thread':False} if DATABASE_URL.startswith('sqlite:') else {},pool_pre_ping=True)
if DATABASE_URL.startswith('sqlite:'):
    @event.listens_for(engine,'connect')
    def foreign_keys(conn,record): conn.execute('PRAGMA foreign_keys=ON')
SessionLocal=sessionmaker(bind=engine,autoflush=False,expire_on_commit=False)
def get_db():
    with SessionLocal() as db: yield db
