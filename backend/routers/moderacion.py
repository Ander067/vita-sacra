from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, ConfigDict, model_validator
from sqlalchemy import text
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError, IntegrityError

from database import get_db
from security.auth import obtener_usuario_actual, verificar_roles

router = APIRouter(
    prefix="/moderacion",
    tags=["Moderacion"]
)


# Modelo para registrar un reporte.
class ReporteRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    blog_id: int | None = Field(default=None, gt=0)
    com_id: int | None = Field(default=None, gt=0)
    motivo: str = Field(min_length=5, max_length=255)

    @model_validator(mode="after")
    def validar_objetivo(self):
        if (self.blog_id is None) == (self.com_id is None):
            raise ValueError(
                "Debes reportar una publicacion o un comentario"
            )

        return self


# Modelo para resolver un reporte.
class ReporteResolucion(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    estatus: Literal["resuelto", "descartado"]
    resolucion: str = Field(min_length=5)


# Modelo para registrar terminos de moderacion.
class TerminoRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    expresion: str = Field(min_length=2, max_length=150)
    accion: Literal["marcar", "censurar", "bloquear"]


# Modelo para actualizar un termino.
class TerminoActualizacion(TerminoRegistro):
    activo: bool = True


# Modelo para registrar una evaluacion de moderacion.
class EvaluacionRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    com_id: int | None = Field(default=None, gt=0)
    version_id: int | None = Field(default=None, gt=0)

    resultado: Literal[
        "limpio",
        "marcado",
        "censurado",
        "bloqueado"
    ]

    detalle: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def validar_objetivo(self):
        if (self.com_id is None) == (self.version_id is None):
            raise ValueError(
                "Debes evaluar un comentario o una version"
            )

        return self


# Funcion para comprobar que existe el contenido reportado.
def verificar_contenido(
    db: Session,
    blog_id: int | None,
    com_id: int | None
):
    if blog_id is not None:
        resultado = db.execute(
            text("""
                select id_blog
                from blog_publico
                where id_blog = :blog_id
            """),
            {"blog_id": blog_id}
        ).first()

    else:
        resultado = db.execute(
            text("""
                select id_com
                from comentarios_publicos
                where id_com = :com_id
            """),
            {"com_id": com_id}
        ).first()

    if resultado is None:
        raise HTTPException(
            status_code=404,
            detail="Contenido no encontrado o no disponible"
        )


# Endpoint para registrar un reporte.
@router.post(
    "/reportar",
    status_code=status.HTTP_201_CREATED
)
def registrar_reporte(
    datos: ReporteRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_contenido(
            db,
            datos.blog_id,
            datos.com_id
        )

        resultado = db.execute(
            text("""
                insert into reportes (
                    usr_id,
                    blog_id,
                    com_id,
                    motivo
                )
                values (
                    :usr_id,
                    :blog_id,
                    :com_id,
                    :motivo
                )
            """),
            {
                "usr_id": usuario["id_usr"],
                "blog_id": datos.blog_id,
                "com_id": datos.com_id,
                "motivo": datos.motivo
            }
        )

        db.commit()

        return {
            "mensaje": "Reporte registrado correctamente",
            "id_reporte": resultado.lastrowid,
            "estatus": "pendiente"
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar el reporte"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar el reporte"
        )


# Endpoint para consultar reportes propios.
@router.get("/mis-reportes")
def consultar_mis_reportes(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_reporte,
                    blog_id,
                    com_id,
                    motivo,
                    estatus,
                    resolucion,
                    fecha
                from reportes
                where usr_id = :usr_id
                order by fecha desc
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tus reportes"
        )


# Endpoint para consultar todos los reportes.
@router.get("/reportes")
def consultar_reportes(
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    r.*,
                    u.nom_usr as reportado_por
                from reportes r
                inner join usuario u
                    on r.usr_id = u.id_usr
                order by r.fecha desc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los reportes"
        )


# Endpoint para resolver o descartar un reporte.
@router.patch("/reportes/{id_reporte}/resolver")
def resolver_reporte(
    id_reporte: int,
    datos: ReporteResolucion,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                update reportes
                set
                    estatus = :estatus,
                    resolucion = :resolucion,
                    administrador_id = :administrador_id
                where id_reporte = :id_reporte
                and estatus = 'pendiente'
            """),
            {
                "estatus": datos.estatus,
                "resolucion": datos.resolucion,
                "administrador_id": usuario["id_usr"],
                "id_reporte": id_reporte
            }
        )

        if resultado.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="Reporte inexistente o ya revisado"
            )

        db.commit()

        return {
            "mensaje": "Reporte revisado correctamente",
            "id_reporte": id_reporte,
            "estatus": datos.estatus
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al resolver el reporte"
        )


# Endpoint para consultar los terminos de moderacion.
@router.get("/terminos")
def consultar_terminos(
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_termino,
                    expresion,
                    accion,
                    activo
                from terminos_moderacion
                order by expresion
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los terminos"
        )


# Endpoint para registrar un termino de moderacion.
@router.post(
    "/terminos",
    status_code=status.HTTP_201_CREATED
)
def registrar_termino(
    datos: TerminoRegistro,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                insert into terminos_moderacion (
                    expresion,
                    accion
                )
                values (
                    :expresion,
                    :accion
                )
            """),
            {
                "expresion": datos.expresion,
                "accion": datos.accion
            }
        )

        db.commit()

        return {
            "mensaje": "Termino registrado correctamente",
            "id_termino": resultado.lastrowid
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="El termino ya existe"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar el termino"
        )


# Endpoint para actualizar un termino de moderacion.
@router.put("/terminos/{id_termino}")
def actualizar_termino(
    id_termino: int,
    datos: TerminoActualizacion,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                update terminos_moderacion
                set
                    expresion = :expresion,
                    accion = :accion,
                    activo = :activo
                where id_termino = :id_termino
            """),
            {
                "expresion": datos.expresion,
                "accion": datos.accion,
                "activo": datos.activo,
                "id_termino": id_termino
            }
        )

        if resultado.rowcount == 0:
            existe = db.execute(
                text("""
                    select id_termino
                    from terminos_moderacion
                    where id_termino = :id_termino
                """),
                {"id_termino": id_termino}
            ).first()

            if existe is None:
                raise HTTPException(
                    status_code=404,
                    detail="Termino no encontrado"
                )

        db.commit()

        return {
            "mensaje": "Termino actualizado correctamente"
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Ya existe un termino con esa expresion"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al actualizar el termino"
        )


# Endpoint para registrar una evaluacion de moderacion.
@router.post(
    "/evaluaciones",
    status_code=status.HTTP_201_CREATED
)
def registrar_evaluacion(
    datos: EvaluacionRegistro,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                insert into evaluaciones_moderacion (
                    com_id,
                    version_id,
                    resultado,
                    detalle
                )
                values (
                    :com_id,
                    :version_id,
                    :resultado,
                    :detalle
                )
            """),
            {
                "com_id": datos.com_id,
                "version_id": datos.version_id,
                "resultado": datos.resultado,
                "detalle": datos.detalle
            }
        )

        db.commit()

        return {
            "mensaje": "Evaluacion registrada correctamente",
            "id_evaluacion": resultado.lastrowid
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="El contenido no existe o la evaluacion no es valida"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar la evaluacion"
        )
