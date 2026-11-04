from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import obtener_usuario_actual


router = APIRouter(
    prefix="/roles",
    tags=["Roles y permisos"]
)


# Modelos de validacion.

class SolicitudRolRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    rol_id: int = Field(gt=0)
    motivo: str = Field(min_length=10)


class RevisionSolicitud(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    decision: Literal["aprobada", "rechazada"]
    observacion: str | None = None


class AsignacionRol(BaseModel):
    usr_id: int = Field(gt=0)
    rol_id: int = Field(gt=0)


class RevocacionRol(BaseModel):
    usr_id: int = Field(gt=0)
    rol_id: int = Field(gt=0)


# Funciones auxiliares.

def comprobar_administrador(
    db: Session,
    usuario_id: int
):
    resultado = db.execute(
        text("""
            select 1
            from usuario u
            where u.id_usr = :usuario_id
            and u.estatus = 'activo'
            and (
                u.tip_usu = (
                    select id_rol
                    from roles
                    where nombre = 'administrador'
                )
                or exists (
                    select 1
                    from usuario_roles ur
                    inner join roles r
                        on ur.rol_id = r.id_rol
                    where ur.usr_id = u.id_usr
                    and r.nombre = 'administrador'
                )
            )
        """),
        {"usuario_id": usuario_id}
    ).first()

    if resultado is None:
        raise HTTPException(
            status_code=403,
            detail="Se requieren permisos de administrador"
        )


def obtener_rol(db: Session, rol_id: int):
    rol = db.execute(
        text("""
            select
                id_rol,
                nombre
            from roles
            where id_rol = :rol_id
        """),
        {"rol_id": rol_id}
    ).mappings().first()

    if rol is None:
        raise HTTPException(
            status_code=404,
            detail="Rol no encontrado"
        )

    return dict(rol)


def obtener_usuario_bloqueado(
    db: Session,
    usuario_id: int
):
    usuario = db.execute(
        text("""
            select
                id_usr,
                nom_usr,
                tip_usu,
                estatus
            from usuario
            where id_usr = :usuario_id
            for update
        """),
        {"usuario_id": usuario_id}
    ).mappings().first()

    if usuario is None:
        raise HTTPException(
            status_code=404,
            detail="Usuario no encontrado"
        )

    return dict(usuario)


def comprobar_rol_asignable(rol: dict):
    if rol["nombre"] not in ("autor", "anunciante"):
        raise HTTPException(
            status_code=403,
            detail="Este rol no admite asignacion desde el modulo"
        )


def comprobar_rol_disponible(
    db: Session,
    usuario: dict,
    rol_id: int
):
    if usuario["estatus"] != "activo":
        raise HTTPException(
            status_code=409,
            detail="El usuario no se encuentra activo"
        )

    if usuario["tip_usu"] == rol_id:
        raise HTTPException(
            status_code=409,
            detail="El usuario ya tiene este rol como principal"
        )

    existente = db.execute(
        text("""
            select 1
            from usuario_roles
            where usr_id = :usr_id
            and rol_id = :rol_id
        """),
        {
            "usr_id": usuario["id_usr"],
            "rol_id": rol_id
        }
    ).first()

    if existente is not None:
        raise HTTPException(
            status_code=409,
            detail="El usuario ya tiene asignado este rol"
        )


def asignar_rol(
    db: Session,
    usuario_id: int,
    rol_id: int,
    administrador_id: int
):
    usuario = obtener_usuario_bloqueado(
        db,
        usuario_id
    )

    rol = obtener_rol(db, rol_id)
    comprobar_rol_asignable(rol)

    comprobar_rol_disponible(
        db,
        usuario,
        rol_id
    )

    db.execute(
        text("""
            insert into usuario_roles (
                usr_id,
                rol_id,
                asignado_por
            )
            values (
                :usr_id,
                :rol_id,
                :administrador_id
            )
        """),
        {
            "usr_id": usuario_id,
            "rol_id": rol_id,
            "administrador_id": administrador_id
        }
    )

    db.execute(
        text("""
            insert into historial_roles (
                usr_id,
                rol_id,
                accion,
                administrador_id
            )
            values (
                :usr_id,
                :rol_id,
                'asignar',
                :administrador_id
            )
        """),
        {
            "usr_id": usuario_id,
            "rol_id": rol_id,
            "administrador_id": administrador_id
        }
    )


def revocar_rol(
    db: Session,
    usuario_id: int,
    rol_id: int,
    administrador_id: int
):
    usuario = obtener_usuario_bloqueado(
        db,
        usuario_id
    )

    rol = obtener_rol(db, rol_id)
    comprobar_rol_asignable(rol)

    if usuario["tip_usu"] == rol_id:
        raise HTTPException(
            status_code=409,
            detail="No se puede revocar un rol principal"
        )

    resultado = db.execute(
        text("""
            delete from usuario_roles
            where usr_id = :usr_id
            and rol_id = :rol_id
        """),
        {
            "usr_id": usuario_id,
            "rol_id": rol_id
        }
    )

    if resultado.rowcount != 1:
        raise HTTPException(
            status_code=404,
            detail="El usuario no tiene este rol adicional"
        )

    db.execute(
        text("""
            insert into historial_roles (
                usr_id,
                rol_id,
                accion,
                administrador_id
            )
            values (
                :usr_id,
                :rol_id,
                'revocar',
                :administrador_id
            )
        """),
        {
            "usr_id": usuario_id,
            "rol_id": rol_id,
            "administrador_id": administrador_id
        }
    )


# Consulta publica del catalogo de roles.

@router.get("/")
def consultar_roles(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_rol,
                    nombre
                from roles
                order by id_rol
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los roles"
        )


# Consulta de roles propios.

@router.get("/mis-roles")
def consultar_mis_roles(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        principal = db.execute(
            text("""
                select
                    r.id_rol,
                    r.nombre
                from usuario u
                inner join roles r
                    on u.tip_usu = r.id_rol
                where u.id_usr = :usr_id
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().first()

        adicionales = db.execute(
            text("""
                select
                    r.id_rol,
                    r.nombre,
                    ur.fecha,
                    ur.asignado_por
                from usuario_roles ur
                inner join roles r
                    on ur.rol_id = r.id_rol
                where ur.usr_id = :usr_id
                order by r.nombre
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return {
            "rol_principal": (
                dict(principal)
                if principal is not None
                else None
            ),
            "roles_adicionales": [
                dict(fila)
                for fila in adicionales
            ]
        }

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tus roles"
        )


# Registro de una solicitud de rol.

@router.post(
    "/solicitudes",
    status_code=status.HTTP_201_CREATED
)
def solicitar_rol(
    datos: SolicitudRolRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        rol = obtener_rol(
            db,
            datos.rol_id
        )

        comprobar_rol_asignable(rol)

        usuario_db = obtener_usuario_bloqueado(
            db,
            usuario["id_usr"]
        )

        comprobar_rol_disponible(
            db,
            usuario_db,
            datos.rol_id
        )

        pendiente = db.execute(
            text("""
                select id_solicitud
                from solicitudes_rol
                where usr_id = :usr_id
                and rol_id = :rol_id
                and estatus = 'pendiente'
                limit 1
            """),
            {
                "usr_id": usuario["id_usr"],
                "rol_id": datos.rol_id
            }
        ).first()

        if pendiente is not None:
            raise HTTPException(
                status_code=409,
                detail="Ya tienes una solicitud pendiente para este rol"
            )

        resultado = db.execute(
            text("""
                insert into solicitudes_rol (
                    usr_id,
                    rol_id,
                    motivo,
                    estatus
                )
                values (
                    :usr_id,
                    :rol_id,
                    :motivo,
                    'pendiente'
                )
            """),
            {
                "usr_id": usuario["id_usr"],
                "rol_id": datos.rol_id,
                "motivo": datos.motivo
            }
        )

        db.commit()

        return {
            "mensaje": "Solicitud registrada correctamente",
            "id_solicitud": resultado.lastrowid,
            "rol": rol["nombre"],
            "estatus": "pendiente"
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar la solicitud"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar la solicitud"
        )


# Consulta de solicitudes propias.

@router.get("/mis-solicitudes")
def consultar_mis_solicitudes(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    s.id_solicitud,
                    s.rol_id,
                    r.nombre as rol,
                    s.motivo,
                    s.estatus,
                    s.observacion,
                    s.fecha,
                    s.fecha_revision
                from solicitudes_rol s
                inner join roles r
                    on s.rol_id = r.id_rol
                where s.usr_id = :usr_id
                order by s.fecha desc
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tus solicitudes"
        )


# Consulta administrativa de solicitudes pendientes.

@router.get("/administracion/solicitudes")
def consultar_solicitudes_pendientes(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        comprobar_administrador(
            db,
            usuario["id_usr"]
        )

        resultado = db.execute(
            text("""
                select
                    s.id_solicitud,
                    s.usr_id,
                    u.nom_usr,
                    u.mail,
                    s.rol_id,
                    r.nombre as rol,
                    s.motivo,
                    s.estatus,
                    s.fecha
                from solicitudes_rol s
                inner join usuario u
                    on s.usr_id = u.id_usr
                inner join roles r
                    on s.rol_id = r.id_rol
                where s.estatus = 'pendiente'
                order by s.fecha asc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las solicitudes"
        )


# Aprobacion o rechazo administrativo.

@router.patch(
    "/administracion/solicitudes/{id_solicitud}/revisar"
)
def revisar_solicitud(
    id_solicitud: int,
    datos: RevisionSolicitud,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        comprobar_administrador(
            db,
            usuario["id_usr"]
        )

        solicitud = db.execute(
            text("""
                select
                    id_solicitud,
                    usr_id,
                    rol_id,
                    estatus
                from solicitudes_rol
                where id_solicitud = :id_solicitud
                for update
            """),
            {"id_solicitud": id_solicitud}
        ).mappings().first()

        if solicitud is None:
            raise HTTPException(
                status_code=404,
                detail="Solicitud no encontrada"
            )

        if solicitud["estatus"] != "pendiente":
            raise HTTPException(
                status_code=409,
                detail="La solicitud ya fue revisada"
            )

        if datos.decision == "aprobada":
            asignar_rol(
                db,
                solicitud["usr_id"],
                solicitud["rol_id"],
                usuario["id_usr"]
            )

        db.execute(
            text("""
                update solicitudes_rol
                set
                    estatus = :estatus,
                    revisado_por = :administrador_id,
                    observacion = :observacion,
                    fecha_revision = current_timestamp
                where id_solicitud = :id_solicitud
            """),
            {
                "estatus": datos.decision,
                "administrador_id": usuario["id_usr"],
                "observacion": datos.observacion,
                "id_solicitud": id_solicitud
            }
        )

        db.commit()

        return {
            "mensaje": "Solicitud revisada correctamente",
            "id_solicitud": id_solicitud,
            "estatus": datos.decision
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Conflicto al asignar el rol solicitado"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al revisar la solicitud"
        )


# Asignacion directa de un rol adicional.

@router.post("/administracion/asignar")
def asignacion_directa(
    datos: AsignacionRol,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        comprobar_administrador(
            db,
            usuario["id_usr"]
        )

        asignar_rol(
            db,
            datos.usr_id,
            datos.rol_id,
            usuario["id_usr"]
        )

        db.commit()

        return {
            "mensaje": "Rol adicional asignado correctamente",
            "usr_id": datos.usr_id,
            "rol_id": datos.rol_id
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Conflicto al asignar el rol"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al asignar el rol"
        )


# Revocacion de un rol adicional.

@router.post("/administracion/revocar")
def revocacion_directa(
    datos: RevocacionRol,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        comprobar_administrador(
            db,
            usuario["id_usr"]
        )

        revocar_rol(
            db,
            datos.usr_id,
            datos.rol_id,
            usuario["id_usr"]
        )

        db.commit()

        return {
            "mensaje": "Rol adicional revocado correctamente",
            "usr_id": datos.usr_id,
            "rol_id": datos.rol_id
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al revocar el rol"
        )


# Consulta administrativa del historial de cambios.

@router.get("/administracion/historial")
def consultar_historial(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        comprobar_administrador(
            db,
            usuario["id_usr"]
        )

        resultado = db.execute(
            text("""
                select
                    h.id_cambio,
                    h.usr_id,
                    u.nom_usr,
                    h.rol_id,
                    r.nombre as rol,
                    h.accion,
                    h.administrador_id,
                    h.fecha
                from historial_roles h
                inner join usuario u
                    on h.usr_id = u.id_usr
                inner join roles r
                    on h.rol_id = r.id_rol
                order by h.fecha desc, h.id_cambio desc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar el historial"
        )


# Consulta administrativa de roles de un usuario.

@router.get("/administracion/usuarios/{usuario_id}")
def consultar_roles_usuario(
    usuario_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        comprobar_administrador(
            db,
            usuario["id_usr"]
        )

        usuario_consultado = db.execute(
            text("""
                select
                    u.id_usr,
                    u.nom_usr,
                    u.estatus,
                    r.id_rol as rol_principal_id,
                    r.nombre as rol_principal
                from usuario u
                inner join roles r
                    on u.tip_usu = r.id_rol
                where u.id_usr = :usuario_id
            """),
            {"usuario_id": usuario_id}
        ).mappings().first()

        if usuario_consultado is None:
            raise HTTPException(
                status_code=404,
                detail="Usuario no encontrado"
            )

        adicionales = db.execute(
            text("""
                select
                    r.id_rol,
                    r.nombre,
                    ur.fecha,
                    ur.asignado_por
                from usuario_roles ur
                inner join roles r
                    on ur.rol_id = r.id_rol
                where ur.usr_id = :usuario_id
                order by r.nombre
            """),
            {"usuario_id": usuario_id}
        ).mappings().all()

        return {
            "usuario": dict(usuario_consultado),
            "roles_adicionales": [
                dict(fila)
                for fila in adicionales
            ]
        }

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los roles del usuario"
        )
