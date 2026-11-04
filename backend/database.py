import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import sessionmaker


load_dotenv()


# Configuracion de la conexion a MariaDB.
DATABASE_URL = URL.create(
    drivername="mysql+pymysql",
    username=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    host=os.getenv("DB_HOST", "127.0.0.1"),
    port=int(os.getenv("DB_PORT", "3307")),
    database=os.getenv("DB_NAME", "VitaSacra_blog_db"),
    query={"charset": "utf8mb4"}
)


# Creacion del motor de conexion.
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    pool_size=5,
    max_overflow=10,
    pool_timeout=30
)


# Configuracion de las sesiones.
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)


# Dependencia para administrar sesiones.
def get_db():
    db = SessionLocal()

    try:
        yield db

    except Exception:
        db.rollback()
        raise

    finally:
        db.close()


# Funcion para comprobar la conexion a MariaDB.
def verificar_conexion() -> bool:
    try:
        with engine.connect() as conexion:
            resultado = conexion.execute(
                text("""
                    select
                        database() as base_datos,
                        version() as version
                """)
            ).mappings().first()

            print("Conexion exitosa con MariaDB")
            print(f"Base de datos: {resultado['base_datos']}")
            print(f"Version: {resultado['version']}")

            return True

    except SQLAlchemyError as error:
        print(f"Error de conexion con MariaDB: {error}")

        return False


# Ejecucion independiente para comprobar la conexion.
if __name__ == "__main__":
    verificar_conexion()
