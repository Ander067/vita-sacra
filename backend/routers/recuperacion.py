import hashlib
import secrets
import smtplib

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import generar_hash, verificar_contrasena
from services.email_service import enviar_correo


router = APIRouter(
    prefix="/usuarios",
    tags=["Recuperación de contraseña"]
)

DURACION_TOKEN_RECUPERACION_HORAS = 1


class SolicitudRecuperacion(BaseModel):
    mail: EmailStr


class RestablecerContrasena(BaseModel):
    token: str = Field(min_length=30, max_length=256)
    contrasena_nueva: str = Field(min_length=8, max_length=128)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


@router.post(
    "/solicitar-recuperacion",
    status_code=status.HTTP_202_ACCEPTED
)
def solicitar_recuperacion(
    datos: SolicitudRecuperacion,
    db: Session = Depends(get_db)
):
    correo = str(datos.mail).strip().lower()

    respuesta = {
        "mensaje": (
            "Si existe una cuenta activa con ese correo, "
            "recibiras instrucciones para recuperar la contraseña."
        )
    }

    try:
        usuario = db.execute(
            text("""
                select
                    id_usr,
                    nom_usr,
                    mail
                from usuario
                where lower(mail) = :correo
                    and correo_verificado = 1
                    and estatus = 'activo'
                limit 1
            """),
            {"correo": correo}
        ).mappings().first()

        if usuario is None:
            return respuesta

        token = secrets.token_urlsafe(32)
        token_hash = _hash_token(token)
        expira_en = (
            datetime.now(timezone.utc)
            + timedelta(hours=DURACION_TOKEN_RECUPERACION_HORAS)
        ).replace(tzinfo=None)

        db.execute(
            text("""
                delete from recuperacion_cuenta
                where usr_id = :usuario_id
                    and usado_en is null
            """),
            {"usuario_id": usuario["id_usr"]}
        )

        db.execute(
            text("""
                insert into recuperacion_cuenta (
                    usr_id,
                    token_hash,
                    vence_en
                )
                values (
                    :usuario_id,
                    :token_hash,
                    :vence_en
                )
            """),
            {
                "usuario_id": usuario["id_usr"],
                "token_hash": token_hash,
                "vence_en": expira_en
            }
        )

        db.commit()

        mensaje = (
            f"Hola {usuario['nom_usr']},\n\n"
            "Recibimos una solicitud para cambiar la contraseña "
            "de tu cuenta de Vita Sacra.\n"
            "Ingresa este código en la aplicación:\n\n"
            f"{token}\n\n"
            f"El código vence en "
            f"{DURACION_TOKEN_RECUPERACION_HORAS} hora.\n"
            "Si no solicitaste el cambio, puedes ignorar este mensaje."
        )

        try:
            enviar_correo(
                usuario["mail"],
                "Recuperación de contraseña de Vita Sacra",
                mensaje
            )
        except (RuntimeError, smtplib.SMTPException, OSError) as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="No fue posible enviar el correo de recuperación."
            ) from error

        return respuesta

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al solicitar la recuperación de contraseña"
        ) from error


@router.post("/restablecer-contrasena")
def restablecer_contrasena(
    datos: RestablecerContrasena,
    db: Session = Depends(get_db)
):
    token_hash = _hash_token(datos.token.strip())

    try:
        recuperacion = db.execute(
            text("""
                select
                    r.id_recuperacion,
                    r.usr_id,
                    u.pass
                from recuperacion_cuenta r
                inner join usuario u
                    on u.id_usr = r.usr_id
                where r.token_hash = :token_hash
                    and r.usado_en is null
                    and r.vence_en > UTC_TIMESTAMP()
                    and u.correo_verificado = 1
                    and u.estatus = 'activo'
                limit 1
                for update
            """),
            {"token_hash": token_hash}
        ).mappings().first()

        if recuperacion is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El código es inválido, ya fue usado o venció."
            )

        if verificar_contrasena(
            datos.contrasena_nueva,
            recuperacion["pass"]
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La nueva contraseña debe ser diferente."
            )

        nueva_contrasena = generar_hash(datos.contrasena_nueva)

        db.execute(
            text("""
                update usuario
                set
                    pass = :contrasena,
                    version_sesion = version_sesion + 1
                where id_usr = :usuario_id
            """),
            {
                "contrasena": nueva_contrasena,
                "usuario_id": recuperacion["usr_id"]
            }
        )

        db.execute(
            text("""
                update sesiones_auth
                set revocada_en = UTC_TIMESTAMP()
                where usr_id = :usuario_id
                    and revocada_en is null
            """),
            {"usuario_id": recuperacion["usr_id"]}
        )

        db.execute(
            text("""
                update recuperacion_cuenta
                set usado_en = UTC_TIMESTAMP()
                where usr_id = :usuario_id
                    and usado_en is null
            """),
            {"usuario_id": recuperacion["usr_id"]}
        )

        db.commit()

        return {
            "mensaje": (
                "Contraseña actualizada. Inicia sesión nuevamente."
            )
        }

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al restablecer la contraseña"
        ) from error