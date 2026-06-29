"""
Camada de acesso ao banco MariaDB (sugu_financeiro).

Usa PyMySQL com DictCursor. As credenciais sao lidas de variaveis de
ambiente (com defaults para o ambiente local: root sem senha em localhost),
permitindo configurar via arquivo .env sem alterar o codigo.
"""
import os
from contextlib import contextmanager

import pymysql
from pymysql.cursors import DictCursor
from dotenv import load_dotenv

load_dotenv()

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "sugu_financeiro"),
    "charset": "utf8mb4",
    "cursorclass": DictCursor,
    "autocommit": False,
}


def get_connection():
    """Abre uma nova conexao com o banco."""
    return pymysql.connect(**DB_CONFIG)


@contextmanager
def db_cursor(commit: bool = False):
    """
    Context manager que entrega um cursor pronto e cuida de
    commit/rollback e fechamento da conexao.
    """
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            yield cur
        if commit:
            conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
