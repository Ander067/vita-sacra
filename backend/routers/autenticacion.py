from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import (
    verificar_contrasena,
    crear_token,
    obtener_usuario_actual
)


router = APIRouter(
    prefix="/autenticacion",
    tags=["Autenticacion"]
)


# Modelo para recibir los datos del inicio de sesion.
class InicioSesion(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    mail: EmailStr
    contrasena: str = Field(min_length=1)


# Modelo para devolver el token de autenticacion.
class RespuestaToken(BaseModel):
    access_token: str
    token_type: str


# Endpoint para iniciar sesion.
@router.post(
    "/login",
    response_model=RespuestaToken,
    responses={
        401: {
            "description": "Credenciales incorrectas"
        },
        403: {
            "description": "Cuenta inactiva"
        },
        503: {
            "description": "Autenticacion no configurada"
        }
    }
)
def iniciar_sesion(
    datos: InicioSesion,
    db: Session = Depends(get_db)
):
    # Normalizar el correo electronico.
    correo = str(datos.mail).strip().lower()

    try:
        # Consultar las credenciales del usuario.
        usuario = db.execute(
            text("""
                select
                    id_usr,
                    nom_usr,
                    mail,
                    pass,
                    tip_usu,
                    estatus
                from usuario
                where lower(mail) = :correo
                limit 1
            """),
            {
                "correo": correo
            }
        ).mappings().first()

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar las credenciales"
        ) from error

    # Preparar la respuesta para credenciales incorrectas.
    error_credenciales = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Correo o contrasena incorrectos",
        headers={
            "WWW-Authenticate": "Bearer"
        }
    )

    # Comprobar que el usuario exista.
    if usuario is None:
        raise error_credenciales

    # Verificar la contrasena mediante el hash almacenado.
    if not verificar_contrasena(
        datos.contrasena,
        usuario["pass"]
    ):
        raise error_credenciales

    # Comprobar que la cuenta se encuentre activa.
    if usuario["estatus"] != "activo":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="La cuenta no se encuentra activa"
        )

    try:
        # Generar el token JWT del usuario autenticado.
        token = crear_token(
            usuario["id_usr"]
        )

    except RuntimeError as error:
        # Evitar que un problema de configuracion se exponga al cliente.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="La autenticacion no esta configurada"
        ) from error

    # Devolver el token para acceder a los endpoints protegidos.
    return {
        "access_token": token,
        "token_type": "bearer"
    }


# Endpoint para consultar la sesion actual.
@router.get("/mi-sesion")
def consultar_sesion(
    usuario: dict = Depends(obtener_usuario_actual)
):
    # Los datos proceden de un token JWT validado.
    return {
        "mensaje": "Sesion autenticada correctamente",
        "id_usr": usuario["id_usr"],
        "nom_usr": usuario["nom_usr"],
        "mail": usuario["mail"],
        "tip_usu": usuario["tip_usu"],
        "estatus": usuario["estatus"]
    }
