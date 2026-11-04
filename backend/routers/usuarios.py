from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field, ConfigDict
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


router = APIRouter(
    prefix="/usuarios",
    tags=["Usuarios"]
)


# Modelo para registrar un usuario.
class UsuarioRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    nom_usr: str = Field(min_length=3, max_length=100)
    mail: EmailStr
    contrasena: str = Field(min_length=8, max_length=128)
    dir_usr: str | None = Field(default=None, max_length=255)


# Modelo para actualizar el perfil.
class UsuarioActualizacion(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    nom_usr: str = Field(min_length=3, max_length=100)
    dir_usr: str | None = Field(default=None, max_length=255)


# Modelo para cambiar la contraseña.
class CambioContrasena(BaseModel):
    contrasena_actual: str
    contrasena_nueva: str = Field(min_length=8, max_length=128)


# Modelo para modificar el estado de una cuenta.
class EstadoUsuario(BaseModel):
    estatus: Literal["activo", "suspendido", "inactivo"]


# Funcion para consultar un usuario.
def obtener_usuario(db: Session, usuario_id: int):
    resultado = db.execute(
        text("""
            select
                id_usr,
                nom_usr,
                mail,
                dir_usr,
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
            status_code=404,
            detail="Usuario no encontrado"
        )

    return dict(resultado)


# Endpoint para registrar un usuario.
@router.post(
    "/registro",
    status_code=status.HTTP_201_CREATED
)
def registrar_usuario(
    datos: UsuarioRegistro,
    db: Session = Depends(get_db)
):
    correo = str(datos.mail).lower()

    try:
        existente = db.execute(
            text("""
                select id_usr
                from usuario
                where mail = :correo
            """),
            {"correo": correo}
        ).first()

        if existente is not None:
            raise HTTPException(
                status_code=409,
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
                status_code=500,
                detail="El rol de usuario no esta configurado"
            )

        contrasena_segura = generar_hash(
            datos.contrasena
        )

        resultado = db.execute(
            text("""
                insert into usuario (
                    nom_usr,
                    mail,
                    pass,
                    dir_usr,
                    tip_usu,
                    estatus
                )
                values (
                    :nombre,
                    :correo,
                    :contrasena,
                    :direccion,
                    :rol,
                    'activo'
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

        db.commit()

        return {
            "mensaje": "Usuario registrado correctamente",
            "id_usr": resultado.lastrowid,
            "nom_usr": datos.nom_usr,
            "mail": correo,
            "rol": "usuario",
            "estatus": "activo"
        }

    except IntegrityError:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar el usuario"
        )

    except SQLAlchemyError:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al registrar el usuario"
        )


# Endpoint para consultar el perfil propio.
@router.get("/mi-perfil")
def consultar_mi_perfil(
    usuario: Annotated[
        dict,
        Depends(obtener_usuario_actual)
    ],
    db: Session = Depends(get_db)
):
    try:
        return obtener_usuario(
            db,
            usuario["id_usr"]
        )

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar el perfil"
        )


# Endpoint para actualizar el perfil propio.
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
            "usuario": obtener_usuario(
                db,
                usuario["id_usr"]
            )
        }

    except SQLAlchemyError:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al actualizar el perfil"
        )


# Endpoint para cambiar la contraseña propia.
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
                status_code=404,
                detail="Usuario no encontrado"
            )

        if not verificar_contrasena(
            datos.contrasena_actual,
            resultado["pass"]
        ):
            raise HTTPException(
                status_code=400,
                detail="La contraseña actual es incorrecta"
            )

        if datos.contrasena_actual == datos.contrasena_nueva:
            raise HTTPException(
                status_code=400,
                detail="La nueva contraseña debe ser diferente"
            )

        nueva_contrasena = generar_hash(
            datos.contrasena_nueva
        )

        db.execute(
            text("""
                update usuario
                set pass = :contrasena
                where id_usr = :usuario_id
            """),
            {
                "contrasena": nueva_contrasena,
                "usuario_id": usuario["id_usr"]
            }
        )

        db.commit()

        return {
            "mensaje": "Contraseña actualizada correctamente"
        }

    except SQLAlchemyError:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al actualizar la contraseña"
        )


# Endpoint administrativo para consultar usuarios.
@router.get("/administracion")
def consultar_usuarios(
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
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

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los usuarios"
        )


# Endpoint administrativo para consultar un usuario.
@router.get("/administracion/{usuario_id}")
def consultar_usuario_administracion(
    usuario_id: int,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        return obtener_usuario(
            db,
            usuario_id
        )

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar el usuario"
        )


# Endpoint administrativo para cambiar el estado.
@router.patch("/administracion/{usuario_id}/estado")
def actualizar_estado_usuario(
    usuario_id: int,
    datos: EstadoUsuario,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        usuario_objetivo = obtener_usuario(
            db,
            usuario_id
        )

        if usuario_id == usuario["id_usr"]:
            raise HTTPException(
                status_code=409,
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
                set estatus = :estatus
                where id_usr = :usuario_id
            """),
            {
                "estatus": datos.estatus,
                "usuario_id": usuario_id
            }
        )

        db.commit()

        return {
            "mensaje": "Estado del usuario actualizado",
            "usuario_id": usuario_id,
            "estatus": datos.estatus
        }

    except SQLAlchemyError:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al actualizar el estado del usuario"
        )
