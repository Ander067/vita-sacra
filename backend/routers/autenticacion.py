import hashlib
import secrets
import uuid

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    crear_token,
    obtener_usuario_actual,
    verificar_contrasena
)


router = APIRouter(
    prefix="/autenticacion",
    tags=["Autenticacion"]
)

REFRESH_TOKEN_EXPIRE_DAYS = 30


class InicioSesion(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    mail: EmailStr
    contrasena: str = Field(min_length=1)


class RespuestaToken(BaseModel):
    access_token: str
    token_type: str
    refresh_token: str
    expires_in: int


class SolicitudRefresh(BaseModel):
    refresh_token: str = Field(min_length=40, max_length=256)


class RegistroBiometrico(BaseModel):
    id_dispositivo: str = Field(min_length=1, max_length=128)


class InicioBiometrico(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    mail: EmailStr
    id_dispositivo: str = Field(min_length=1, max_length=128)
    credencial: str = Field(min_length=20, max_length=200)


class RespuestaBiometrica(BaseModel):
    credencial: str


def generar_hash_credencial(credencial: str) -> str:
    return hashlib.sha256(credencial.encode("utf-8")).hexdigest()


def _crear_sesion(
    db: Session,
    usuario: dict
) -> RespuestaToken:
    id_sesion = str(uuid.uuid4())
    refresh_token = secrets.token_urlsafe(48)
    refresh_token_hash = generar_hash_credencial(refresh_token)

    ahora = datetime.now(timezone.utc)
    expira_en = (
        ahora + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    ).replace(tzinfo=None)

    access_token = crear_token(
        usuario["id_usr"],
        usuario["version_sesion"],
        id_sesion
    )

    db.execute(
        text("""
            insert into sesiones_auth (
                id_sesion,
                usr_id,
                refresh_token_hash,
                expira_en
            )
            values (
                :id_sesion,
                :usr_id,
                :refresh_token_hash,
                :expira_en
            )
        """),
        {
            "id_sesion": id_sesion,
            "usr_id": usuario["id_usr"],
            "refresh_token_hash": refresh_token_hash,
            "expira_en": expira_en
        }
    )

    db.commit()

    return RespuestaToken(
        access_token=access_token,
        token_type="bearer",
        refresh_token=refresh_token,
        expires_in=ACCESS_TOKEN_EXPIRE_MINUTES * 60
    )


@router.post(
    "/login",
    response_model=RespuestaToken
)
def iniciar_sesion(
    datos: InicioSesion,
    db: Session = Depends(get_db)
):
    correo = str(datos.mail).strip().lower()

    try:
        usuario = db.execute(
            text("""
                select
                    id_usr,
                    nom_usr,
                    mail,
                    pass,
                    tip_usu,
                    estatus,
                    version_sesion
                from usuario
                where lower(mail) = :correo
                limit 1
            """),
            {"correo": correo}
        ).mappings().first()

        error_credenciales = HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contrasena incorrectos",
            headers={"WWW-Authenticate": "Bearer"}
        )

        if usuario is None:
            raise error_credenciales

        if not verificar_contrasena(datos.contrasena, usuario["pass"]):
            raise error_credenciales

        if usuario["estatus"] != "activo":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="La cuenta no se encuentra activa"
            )

        return _crear_sesion(db, usuario)

    except HTTPException:
        db.rollback()
        raise

    except RuntimeError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="La autenticacion no esta configurada"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al iniciar la sesion"
        ) from error


@router.post(
    "/refresh",
    response_model=RespuestaToken
)
def renovar_sesion(
    datos: SolicitudRefresh,
    db: Session = Depends(get_db)
):
    token_hash = generar_hash_credencial(datos.refresh_token)

    try:
        sesion = db.execute(
            text("""
                select
                    s.id_sesion,
                    s.usr_id,
                    u.version_sesion,
                    u.estatus
                from sesiones_auth s
                inner join usuario u
                    on u.id_usr = s.usr_id
                where s.refresh_token_hash = :token_hash
                    and s.revocada_en is null
                    and s.expira_en > UTC_TIMESTAMP()
                limit 1
                for update
            """),
            {"token_hash": token_hash}
        ).mappings().first()

        if sesion is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="El refresh token no es valido o ya fue utilizado"
            )

        if sesion["estatus"] != "activo":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="La cuenta no se encuentra activa"
            )

        nuevo_refresh_token = secrets.token_urlsafe(48)
        nuevo_refresh_hash = generar_hash_credencial(nuevo_refresh_token)

        ahora = datetime.now(timezone.utc)
        expira_en = (
            ahora + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
        ).replace(tzinfo=None)

        access_token = crear_token(
            sesion["usr_id"],
            sesion["version_sesion"],
            sesion["id_sesion"]
        )

        db.execute(
            text("""
                update sesiones_auth
                set
                    refresh_token_hash = :nuevo_hash,
                    expira_en = :expira_en,
                    ultimo_uso = UTC_TIMESTAMP()
                where id_sesion = :id_sesion
                    and revocada_en is null
            """),
            {
                "nuevo_hash": nuevo_refresh_hash,
                "expira_en": expira_en,
                "id_sesion": sesion["id_sesion"]
            }
        )

        db.commit()

        return RespuestaToken(
            access_token=access_token,
            token_type="bearer",
            refresh_token=nuevo_refresh_token,
            expires_in=ACCESS_TOKEN_EXPIRE_MINUTES * 60
        )

    except HTTPException:
        db.rollback()
        raise

    except RuntimeError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="La autenticacion no esta configurada"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al renovar la sesion"
        ) from error


@router.post("/logout")
def cerrar_sesion(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        db.execute(
            text("""
                update sesiones_auth
                set revocada_en = UTC_TIMESTAMP()
                where id_sesion = :id_sesion
                    and usr_id = :usr_id
                    and revocada_en is null
            """),
            {
                "id_sesion": usuario["id_sesion"],
                "usr_id": usuario["id_usr"]
            }
        )

        db.commit()

        return {"mensaje": "Sesion cerrada correctamente"}

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al cerrar la sesion"
        ) from error


@router.post("/logout-todos")
def cerrar_todas_las_sesiones(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        db.execute(
            text("""
                update usuario
                set version_sesion = version_sesion + 1
                where id_usr = :usr_id
            """),
            {"usr_id": usuario["id_usr"]}
        )

        db.execute(
            text("""
                update sesiones_auth
                set revocada_en = UTC_TIMESTAMP()
                where usr_id = :usr_id
                    and revocada_en is null
            """),
            {"usr_id": usuario["id_usr"]}
        )

        db.commit()

        return {"mensaje": "Se cerraron todas las sesiones"}

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al cerrar todas las sesiones"
        ) from error


@router.post(
    "/biometria/registrar",
    response_model=RespuestaBiometrica
)
def registrar_biometria(
    datos: RegistroBiometrico,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    credencial = secrets.token_urlsafe(32)
    token_hash = generar_hash_credencial(credencial)

    try:
        db.execute(
            text("""
                insert into credenciales_biometricas (
                    id_usr,
                    id_dispositivo,
                    token_hash,
                    activa
                )
                values (
                    :id_usr,
                    :id_dispositivo,
                    :token_hash,
                    1
                )
                on duplicate key update
                    token_hash = values(token_hash),
                    activa = 1,
                    fecha_creacion = current_timestamp,
                    fecha_ultimo_uso = null
            """),
            {
                "id_usr": usuario["id_usr"],
                "id_dispositivo": datos.id_dispositivo,
                "token_hash": token_hash
            }
        )

        db.commit()

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al registrar el acceso biometrico"
        ) from error

    return {"credencial": credencial}


@router.post(
    "/biometria/login",
    response_model=RespuestaToken
)
def iniciar_sesion_biometrica(
    datos: InicioBiometrico,
    db: Session = Depends(get_db)
):
    correo = str(datos.mail).strip().lower()
    token_hash = generar_hash_credencial(datos.credencial)

    try:
        usuario = db.execute(
            text("""
                select
                    u.id_usr,
                    u.nom_usr,
                    u.mail,
                    u.tip_usu,
                    u.estatus,
                    u.version_sesion
                from usuario u
                inner join credenciales_biometricas cb
                    on cb.id_usr = u.id_usr
                where lower(u.mail) = :correo
                    and cb.id_dispositivo = :id_dispositivo
                    and cb.token_hash = :token_hash
                    and cb.activa = 1
                limit 1
            """),
            {
                "correo": correo,
                "id_dispositivo": datos.id_dispositivo,
                "token_hash": token_hash
            }
        ).mappings().first()

        if usuario is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="No se pudo validar el acceso biometrico"
            )

        if usuario["estatus"] != "activo":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="La cuenta no se encuentra activa"
            )

        db.execute(
            text("""
                update credenciales_biometricas
                set fecha_ultimo_uso = current_timestamp
                where id_usr = :id_usr
                    and id_dispositivo = :id_dispositivo
            """),
            {
                "id_usr": usuario["id_usr"],
                "id_dispositivo": datos.id_dispositivo
            }
        )

        respuesta = _crear_sesion(db, usuario)
        return respuesta

    except HTTPException:
        db.rollback()
        raise

    except RuntimeError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="La autenticacion no esta configurada"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al validar el acceso biometrico"
        ) from error


@router.delete("/biometria/{id_dispositivo}")
def revocar_biometria(
    id_dispositivo: str,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        db.execute(
            text("""
                delete from credenciales_biometricas
                where id_usr = :id_usr
                    and id_dispositivo = :id_dispositivo
            """),
            {
                "id_usr": usuario["id_usr"],
                "id_dispositivo": id_dispositivo
            }
        )

        db.commit()

        return {"mensaje": "Acceso biometrico desactivado"}

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al desactivar el acceso biometrico"
        ) from error


@router.get("/mi-sesion")
def consultar_sesion(
    usuario: dict = Depends(obtener_usuario_actual)
):
    return {
        "mensaje": "Sesion autenticada correctamente",
        "id_usr": usuario["id_usr"],
        "nom_usr": usuario["nom_usr"],
        "mail": usuario["mail"],
        "tip_usu": usuario["tip_usu"],
        "estatus": usuario["estatus"]
    }