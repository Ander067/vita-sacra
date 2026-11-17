import os
import uuid

from datetime import datetime, timedelta, timezone
from typing import Annotated

import jwt

from dotenv import load_dotenv
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt.exceptions import InvalidTokenError
from pwdlib import PasswordHash
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import get_db


load_dotenv()

SECRET_KEY = os.getenv("JWT_SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

password_hash = PasswordHash.recommended()
bearer_scheme = HTTPBearer(auto_error=False)


def generar_hash(contrasena: str) -> str:
    if not isinstance(contrasena, str) or not contrasena:
        raise ValueError("La contrasena debe ser una cadena no vacia")

    return password_hash.hash(contrasena)


def verificar_contrasena(
    contrasena: str,
    hash_guardado: str
) -> bool:
    if not isinstance(contrasena, str):
        return False

    if not isinstance(hash_guardado, str) or not hash_guardado:
        return False

    try:
        return password_hash.verify(contrasena, hash_guardado)
    except (ValueError, TypeError):
        return False


def crear_token(
    id_usuario: int,
    version_sesion: int,
    id_sesion: str
) -> str:
    if not SECRET_KEY:
        raise RuntimeError("Falta configurar JWT_SECRET_KEY en .env")

    if (
        not isinstance(id_usuario, int)
        or isinstance(id_usuario, bool)
        or id_usuario <= 0
    ):
        raise ValueError(
            "El identificador del usuario debe ser un entero positivo"
        )

    if (
        not isinstance(version_sesion, int)
        or isinstance(version_sesion, bool)
        or version_sesion <= 0
    ):
        raise ValueError("La version de sesion debe ser un entero positivo")

    try:
        uuid.UUID(id_sesion)
    except (ValueError, TypeError, AttributeError) as error:
        raise ValueError("El identificador de sesion no es valido") from error

    ahora = datetime.now(timezone.utc)

    datos = {
        "sub": str(id_usuario),
        "ver": version_sesion,
        "sid": id_sesion,
        "iat": ahora,
        "exp": ahora + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    }

    return jwt.encode(datos, SECRET_KEY, algorithm=ALGORITHM)


def error_autenticacion() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudo validar la autenticacion",
        headers={"WWW-Authenticate": "Bearer"}
    )


def obtener_usuario_actual(
    credenciales: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme)
    ],
    db: Session = Depends(get_db)
) -> dict:
    if credenciales is None:
        raise error_autenticacion()

    if credenciales.scheme.lower() != "bearer":
        raise error_autenticacion()

    if not SECRET_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="La autenticacion no esta configurada"
        )

    try:
        datos = jwt.decode(
            credenciales.credentials,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            options={"require": ["sub", "ver", "sid", "exp", "iat"]}
        )

        identificador = datos["sub"]
        version_token = datos["ver"]
        id_sesion = datos["sid"]

        if (
            not isinstance(identificador, str)
            or not identificador.isdecimal()
        ):
            raise error_autenticacion()

        id_usuario = int(identificador)

        if id_usuario <= 0:
            raise error_autenticacion()

        if (
            not isinstance(version_token, int)
            or isinstance(version_token, bool)
            or version_token <= 0
        ):
            raise error_autenticacion()

        if not isinstance(id_sesion, str):
            raise error_autenticacion()

        uuid.UUID(id_sesion)

    except (InvalidTokenError, ValueError, TypeError, KeyError):
        raise error_autenticacion()

    usuario = db.execute(
        text("""
            select
                u.id_usr,
                u.nom_usr,
                u.mail,
                u.tip_usu,
                u.estatus,
                u.version_sesion,
                s.id_sesion
            from usuario u
            inner join sesiones_auth s
                on s.usr_id = u.id_usr
            where u.id_usr = :id_usuario
                and s.id_sesion = :id_sesion
                and s.revocada_en is null
                and s.expira_en > UTC_TIMESTAMP()
            limit 1
        """),
        {
            "id_usuario": id_usuario,
            "id_sesion": id_sesion
        }
    ).mappings().first()

    if usuario is None:
        raise error_autenticacion()

    if usuario["version_sesion"] != version_token:
        raise error_autenticacion()

    if usuario["estatus"] != "activo":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="La cuenta no se encuentra activa"
        )

    return dict(usuario)


def verificar_roles(*roles_permitidos: str):
    if not roles_permitidos:
        raise ValueError("Debes indicar al menos un rol permitido")

    roles_validos = {
        rol.strip().lower()
        for rol in roles_permitidos
        if isinstance(rol, str) and rol.strip()
    }

    if not roles_validos:
        raise ValueError("Debes indicar nombres de roles validos")

    def comprobar_rol(
        usuario: Annotated[
            dict,
            Depends(obtener_usuario_actual)
        ],
        db: Session = Depends(get_db)
    ) -> dict:
        roles = db.execute(
            text("""
                select r.nombre
                from roles r
                where r.id_rol = :rol_principal

                union

                select r.nombre
                from usuario_roles ur
                inner join roles r
                    on ur.rol_id = r.id_rol
                where ur.usr_id = :id_usuario
            """),
            {
                "rol_principal": usuario["tip_usu"],
                "id_usuario": usuario["id_usr"]
            }
        ).scalars().all()

        roles_usuario = {
            rol.strip().lower()
            for rol in roles
            if isinstance(rol, str) and rol.strip()
        }

        if not roles_usuario.intersection(roles_validos):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tienes permisos para realizar esta operacion"
            )

        return usuario

    return comprobar_rol