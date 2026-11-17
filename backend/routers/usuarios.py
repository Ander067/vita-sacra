import hashlib
import secrets
import smtplib

from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import (
    generar_hash,
    verificar_contrasena,
    obtener_usuario_actual,
    verificar_roles
)
from services.email_service import enviar_correo


router = APIRouter(
    prefix="/usuarios",
    tags=["Usuarios"]
)

DURACION_TOKEN_VERIFICACION_HORAS = 24


class UsuarioRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    nom_usr: str = Field(min_length=3, max_length=100)
    mail: EmailStr
    contrasena: str = Field(min_length=8, max_length=128)
    dir_usr: str | None = Field(default=None, max_length=255)


class SolicitudVerificacionCorreo(BaseModel):
    mail: EmailStr


class VerificarCorreo(BaseModel):
    token: str = Field(min_length=30, max_length=256)


class UsuarioActualizacion(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    nom_usr: str = Field(min_length=3, max_length=100)
    dir_usr: str | None = Field(default=None, max_length=255)


class CambioContrasena(BaseModel):
    contrasena_actual: str
    contrasena_nueva: str = Field(min_length=8, max_length=128)


class EstadoUsuario(BaseModel):
    estatus: Literal["activo", "suspendido", "inactivo"]


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _crear_y_enviar_verificacion(
    db: Session,
    usuario_id: int,
    nombre: str,
    correo: str
) -> None:
    token = secrets.token_urlsafe(32)
    token_hash = _hash_token(token)

    expira_en = (
        datetime.now(timezone.utc)
        + timedelta(hours=DURACION_TOKEN_VERIFICACION_HORAS)
    ).replace(tzinfo=None)

    db.execute(
        text("""
            delete from verificaciones_email
            where usr_id = :usuario_id
                and usada_en is null
        """),
        {"usuario_id": usuario_id}
    )

    db.execute(
        text("""
            insert into verificaciones_email (
                usr_id,
                token_hash,
                expira_en
            )
            values (
                :usuario_id,
                :token_hash,
                :expira_en
            )
        """),
        {
            "usuario_id": usuario_id,
            "token_hash": token_hash,
            "expira_en": expira_en
        }
    )

    db.commit()

    mensaje = (
        f"Hola {nombre},\n\n"
        "Tu cuenta de Vita Sacra está pendiente de verificación.\n"
        "Ingresa este código en la aplicación:\n\n"
        f"{token}\n\n"
        f"El código vence en {DURACION_TOKEN_VERIFICACION_HORAS} horas.\n"
        "Si no solicitaste esta cuenta, puedes ignorar este mensaje."
    )

    try:
        enviar_correo(
            correo,
            "Verifica tu correo de Vita Sacra",
            mensaje
        )
    except (RuntimeError, smtplib.SMTPException, OSError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "La cuenta quedó pendiente de verificación, "
                "pero no se pudo enviar el correo. "
                "Solicita un nuevo código más tarde."
            )
        ) from error


def obtener_usuario(db: Session, usuario_id: int):
    resultado = db.execute(
        text("""
            select
                id_usr,
                nom_usr,
                mail,
                dir_usr,
                foto_perfil_url,
                tip_usu,
                estatus,
                fecha_registro
            from usuario
            where id_usr = :usuario_id
        """),
        {"usuario_id": usuario_id}
    ).mappings().first()

    if resultado is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Usuario no encontrado"
        )

    return dict(resultado)


@router.post(
    "/registro",
    status_code=status.HTTP_201_CREATED
)
def registrar_usuario(
    datos: UsuarioRegistro,
    db: Session = Depends(get_db)
):
    correo = str(datos.mail).strip().lower()

    try:
        existente = db.execute(
            text("""
                select id_usr
                from usuario
                where lower(mail) = :correo
                limit 1
            """),
            {"correo": correo}
        ).first()

        if existente is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="El correo electronico ya esta registrado"
            )

        rol = db.execute(
            text("""
                select id_rol
                from roles
                where nombre = 'usuario'
            """)
        ).scalar_one_or_none()

        if rol is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="El rol de usuario no esta configurado"
            )

        contrasena_segura = generar_hash(datos.contrasena)

        resultado = db.execute(
            text("""
                insert into usuario (
                    nom_usr,
                    mail,
                    pass,
                    dir_usr,
                    tip_usu,
                    estatus,
                    correo_verificado
                )
                values (
                    :nombre,
                    :correo,
                    :contrasena,
                    :direccion,
                    :rol,
                    'inactivo',
                    0
                )
            """),
            {
                "nombre": datos.nom_usr,
                "correo": correo,
                "contrasena": contrasena_segura,
                "direccion": datos.dir_usr,
                "rol": rol
            }
        )

        usuario_id = resultado.lastrowid

        _crear_y_enviar_verificacion(
            db,
            usuario_id,
            datos.nom_usr,
            correo
        )

        return {
            "mensaje": (
                "Cuenta creada. Revisa tu correo e ingresa "
                "el codigo de verificacion para activarla."
            ),
            "id_usr": usuario_id,
            "nom_usr": datos.nom_usr,
            "mail": correo,
            "rol": "usuario",
            "estatus": "inactivo",
            "correo_verificado": False
        }

    except HTTPException:
        db.rollback()
        raise

    except IntegrityError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No fue posible registrar el usuario"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al registrar el usuario"
        ) from error


@router.post("/verificar-email")
def verificar_correo(
    datos: VerificarCorreo,
    db: Session = Depends(get_db)
):
    token_hash = _hash_token(datos.token.strip())

    try:
        verificacion = db.execute(
            text("""
                select
                    id_verificacion,
                    usr_id
                from verificaciones_email
                where token_hash = :token_hash
                    and usada_en is null
                    and expira_en > UTC_TIMESTAMP()
                limit 1
                for update
            """),
            {"token_hash": token_hash}
        ).mappings().first()

        if verificacion is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El codigo es invalido o ya vencio"
            )

        resultado = db.execute(
            text("""
                update usuario
                set
                    correo_verificado = 1,
                    estatus = 'activo'
                where id_usr = :usuario_id
                    and correo_verificado = 0
                    and estatus = 'inactivo'
            """),
            {"usuario_id": verificacion["usr_id"]}
        )

        if resultado.rowcount != 1:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="La cuenta ya fue verificada o no puede activarse"
            )

        db.execute(
            text("""
                update verificaciones_email
                set usada_en = UTC_TIMESTAMP()
                where id_verificacion = :id_verificacion
            """),
            {"id_verificacion": verificacion["id_verificacion"]}
        )

        db.commit()

        return {
            "mensaje": "Correo verificado. Ya puedes iniciar sesion."
        }

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al verificar el correo"
        ) from error


@router.post(
    "/reenviar-verificacion",
    status_code=status.HTTP_202_ACCEPTED
)
def reenviar_verificacion(
    datos: SolicitudVerificacionCorreo,
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
                    correo_verificado,
                    estatus
                from usuario
                where lower(mail) = :correo
                limit 1
            """),
            {"correo": correo}
        ).mappings().first()

        respuesta = {
            "mensaje": (
                "Si existe una cuenta pendiente para ese correo, "
                "se enviara un nuevo codigo."
            )
        }

        if (
            usuario is None
            or usuario["correo_verificado"]
            or usuario["estatus"] != "inactivo"
        ):
            return respuesta

        _crear_y_enviar_verificacion(
            db,
            usuario["id_usr"],
            usuario["nom_usr"],
            usuario["mail"]
        )

        return respuesta

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al solicitar un nuevo codigo"
        ) from error


@router.get("/mi-perfil")
def consultar_mi_perfil(
    usuario: Annotated[
        dict,
        Depends(obtener_usuario_actual)
    ],
    db: Session = Depends(get_db)
):
    try:
        return obtener_usuario(db, usuario["id_usr"])

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar el perfil"
        ) from error


@router.put("/mi-perfil")
def actualizar_mi_perfil(
    datos: UsuarioActualizacion,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        db.execute(
            text("""
                update usuario
                set
                    nom_usr = :nombre,
                    dir_usr = :direccion
                where id_usr = :usuario_id
            """),
            {
                "nombre": datos.nom_usr,
                "direccion": datos.dir_usr,
                "usuario_id": usuario["id_usr"]
            }
        )

        db.commit()

        return {
            "mensaje": "Perfil actualizado correctamente",
            "usuario": obtener_usuario(db, usuario["id_usr"])
        }

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al actualizar el perfil"
        ) from error


@router.put("/mi-contrasena")
def cambiar_mi_contrasena(
    datos: CambioContrasena,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select pass
                from usuario
                where id_usr = :usuario_id
                for update
            """),
            {"usuario_id": usuario["id_usr"]}
        ).mappings().first()

        if resultado is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado"
            )

        if not verificar_contrasena(
            datos.contrasena_actual,
            resultado["pass"]
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La contraseña actual es incorrecta"
            )

        if datos.contrasena_actual == datos.contrasena_nueva:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La nueva contraseña debe ser diferente"
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
                "usuario_id": usuario["id_usr"]
            }
        )

        db.execute(
            text("""
                update sesiones_auth
                set revocada_en = UTC_TIMESTAMP()
                where usr_id = :usuario_id
                    and revocada_en is null
            """),
            {"usuario_id": usuario["id_usr"]}
        )

        db.commit()

        return {
            "mensaje": (
                "Contraseña actualizada. Inicia sesion nuevamente "
                "en tus dispositivos."
            )
        }

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al actualizar la contraseña"
        ) from error


@router.get("/administracion")
def consultar_usuarios(
    usuario: dict = Depends(verificar_roles("administrador")),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    u.id_usr,
                    u.nom_usr,
                    u.mail,
                    u.dir_usr,
                    u.estatus,
                    u.fecha_registro,
                    r.nombre as rol_principal
                from usuario u
                inner join roles r
                    on u.tip_usu = r.id_rol
                order by u.fecha_registro desc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar los usuarios"
        ) from error


@router.get("/administracion/{usuario_id}")
def consultar_usuario_administracion(
    usuario_id: int,
    usuario: dict = Depends(verificar_roles("administrador")),
    db: Session = Depends(get_db)
):
    try:
        return obtener_usuario(db, usuario_id)

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar el usuario"
        ) from error


@router.patch("/administracion/{usuario_id}/estado")
def actualizar_estado_usuario(
    usuario_id: int,
    datos: EstadoUsuario,
    usuario: dict = Depends(verificar_roles("administrador")),
    db: Session = Depends(get_db)
):
    try:
        usuario_objetivo = obtener_usuario(db, usuario_id)

        if usuario_id == usuario["id_usr"]:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="No puedes modificar el estado de tu propia cuenta"
            )

        if usuario_objetivo["estatus"] == datos.estatus:
            return {
                "mensaje": "El usuario ya tiene este estado",
                "usuario_id": usuario_id,
                "estatus": datos.estatus
            }

        db.execute(
            text("""
                update usuario
                set
                    estatus = :estatus,
                    version_sesion = version_sesion + 1
                where id_usr = :usuario_id
            """),
            {
                "estatus": datos.estatus,
                "usuario_id": usuario_id
            }
        )

        db.execute(
            text("""
                update sesiones_auth
                set revocada_en = UTC_TIMESTAMP()
                where usr_id = :usuario_id
                    and revocada_en is null
            """),
            {"usuario_id": usuario_id}
        )

        db.commit()

        return {
            "mensaje": "Estado del usuario actualizado",
            "usuario_id": usuario_id,
            "estatus": datos.estatus
        }

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al actualizar el estado del usuario"
        ) from error