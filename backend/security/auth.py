import os

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


# Cargar las variables de entorno.
load_dotenv()


# Configuracion de autenticacion JWT.
SECRET_KEY = os.getenv("JWT_SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30


# Configurar el algoritmo de hash para contrasenas.
password_hash = PasswordHash.recommended()


# Configurar la autenticacion mediante tokens Bearer.
bearer_scheme = HTTPBearer(auto_error=False)


# Funcion para generar un hash seguro.
def generar_hash(contrasena: str) -> str:
    if not isinstance(contrasena, str) or not contrasena:
        raise ValueError(
            "La contrasena debe ser una cadena no vacia"
        )

    return password_hash.hash(contrasena)


# Funcion para verificar una contrasena.
def verificar_contrasena(
    contrasena: str,
    hash_guardado: str
) -> bool:
    if not isinstance(contrasena, str):
        return False

    if not isinstance(hash_guardado, str):
        return False

    if not hash_guardado:
        return False

    try:
        return password_hash.verify(
            contrasena,
            hash_guardado
        )

    except (ValueError, TypeError):
        # Un hash invalido no debe permitir el acceso.
        return False


# Funcion para generar un token JWT.
def crear_token(id_usuario: int) -> str:
    if not SECRET_KEY:
        raise RuntimeError(
            "Falta configurar JWT_SECRET_KEY en .env"
        )

    if (
        not isinstance(id_usuario, int)
        or isinstance(id_usuario, bool)
        or id_usuario <= 0
    ):
        raise ValueError(
            "El identificador del usuario debe ser un entero positivo"
        )

    ahora = datetime.now(timezone.utc)

    datos = {
        "sub": str(id_usuario),
        "iat": ahora,
        "exp": ahora + timedelta(
            minutes=ACCESS_TOKEN_EXPIRE_MINUTES
        )
    }

    return jwt.encode(
        datos,
        SECRET_KEY,
        algorithm=ALGORITHM
    )


# Funcion para generar una excepcion de autenticacion.
def error_autenticacion() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudo validar la autenticacion",
        headers={
            "WWW-Authenticate": "Bearer"
        }
    )


# Funcion para validar el token y obtener al usuario.
def obtener_usuario_actual(
    credenciales: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme)
    ],
    db: Session = Depends(get_db)
) -> dict:

    # Comprobar que se haya proporcionado un token.
    if credenciales is None:
        raise error_autenticacion()

    # Comprobar el esquema de autenticacion.
    if credenciales.scheme.lower() != "bearer":
        raise error_autenticacion()

    # Verificar la configuracion del servidor.
    if not SECRET_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="La autenticacion no esta configurada"
        )

    try:
        # Decodificar y validar el token JWT.
        datos = jwt.decode(
            credenciales.credentials,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            options={
                "require": [
                    "sub",
                    "exp",
                    "iat"
                ]
            }
        )

        # Obtener el identificador almacenado en el token.
        identificador = datos["sub"]

        # Exigir que el identificador sea una cadena numerica.
        if (
            not isinstance(identificador, str)
            or not identificador.isdecimal()
        ):
            raise error_autenticacion()

        id_usuario = int(identificador)

        if id_usuario <= 0:
            raise error_autenticacion()

    except (InvalidTokenError, ValueError, TypeError, KeyError):
        raise error_autenticacion()

    # Consultar al usuario directamente en la base de datos.
    usuario = db.execute(
        text("""
            select
                id_usr,
                nom_usr,
                mail,
                tip_usu,
                estatus
            from usuario
            where id_usr = :id_usuario
        """),
        {
            "id_usuario": id_usuario
        }
    ).mappings().first()

    # Impedir el acceso a usuarios inexistentes.
    if usuario is None:
        raise error_autenticacion()

    # Comprobar que la cuenta este activa.
    if usuario["estatus"] != "activo":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="La cuenta no se encuentra activa"
        )

    # Devolver los datos necesarios del usuario autenticado.
    return dict(usuario)


# Funcion para comprobar los permisos del usuario.
def verificar_roles(*roles_permitidos: str):

    # Exigir al menos un rol para proteger la operacion.
    if not roles_permitidos:
        raise ValueError(
            "Debes indicar al menos un rol permitido"
        )

    # Normalizar los nombres de los roles permitidos.
    roles_validos = {
        rol.strip().lower()
        for rol in roles_permitidos
        if isinstance(rol, str) and rol.strip()
    }

    if not roles_validos:
        raise ValueError(
            "Debes indicar nombres de roles validos"
        )

    # Dependencia utilizada por los endpoints protegidos.
    def comprobar_rol(
        usuario: Annotated[
            dict,
            Depends(obtener_usuario_actual)
        ],
        db: Session = Depends(get_db)
    ) -> dict:

        # Consultar el rol principal y los roles adicionales.
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

        # Normalizar los roles obtenidos de MariaDB.
        roles_usuario = {
            rol.strip().lower()
            for rol in roles
            if isinstance(rol, str) and rol.strip()
        }

        # Verificar si el usuario posee un rol autorizado.
        if not roles_usuario.intersection(roles_validos):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tienes permisos para realizar esta operacion"
            )

        # Devolver el usuario cuando tiene permisos.
        return usuario

    return comprobar_rol
