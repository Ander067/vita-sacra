from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError, IntegrityError

from database import get_db
from security.auth import obtener_usuario_actual, verificar_roles

router = APIRouter(
    prefix="/comentarios",
    tags=["Comentarios"]
)


# Modelo para registrar un comentario.
class ComentarioRegistro(BaseModel):
    blog_id: int = Field(gt=0)
    comentario: str = Field(min_length=1, max_length=5000)
    com_padre_id: int | None = Field(default=None, gt=0)


# Modelo para modificar un comentario.
class ComentarioActualizacion(BaseModel):
    comentario: str = Field(min_length=1, max_length=5000)


# Endpoint para consultar los comentarios de una publicacion.
@router.get("/publicacion/{id_blog}")
def consultar_comentarios(
    id_blog: int,
    db: Session = Depends(get_db)
):
    try:
        publicacion = db.execute(
            text("""
                select id_blog
                from blog
                where id_blog = :id_blog
                and estatus = 'publicado'
                and version_publica is not null
            """),
            {"id_blog": id_blog}
        ).first()

        if publicacion is None:
            raise HTTPException(
                status_code=404,
                detail="Publicacion no encontrada"
            )

        resultado = db.execute(
            text("""
                select
                    c.id_com,
                    c.comentario,
                    c.fecha,
                    c.com_padre_id,
                    u.nom_usr as autor
                from comentarios c
                inner join usuario u
                    on c.usr_id = u.id_usr
                where c.blog_id = :id_blog
                and c.estatus = 1
                order by c.fecha asc, c.id_com asc
            """),
            {"id_blog": id_blog}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los comentarios"
        )


# Endpoint para registrar un comentario o respuesta.
@router.post("/registrar", status_code=status.HTTP_201_CREATED)
def registrar_comentario(
    datos: ComentarioRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    contenido = datos.comentario.strip()

    if not contenido:
        raise HTTPException(
            status_code=422,
            detail="El comentario no puede estar vacio"
        )

    try:
        publicacion = db.execute(
            text("""
                select id_blog
                from blog
                where id_blog = :id_blog
                and estatus = 'publicado'
                and version_publica is not null
            """),
            {"id_blog": datos.blog_id}
        ).first()

        if publicacion is None:
            raise HTTPException(
                status_code=404,
                detail="La publicacion no esta disponible"
            )

        # Se comprueba que la respuesta pertenezca a la misma publicacion.
        if datos.com_padre_id is not None:
            comentario_padre = db.execute(
                text("""
                    select id_com
                    from comentarios
                    where id_com = :id_com
                    and blog_id = :id_blog
                    and estatus = 1
                """),
                {
                    "id_com": datos.com_padre_id,
                    "id_blog": datos.blog_id
                }
            ).first()

            if comentario_padre is None:
                raise HTTPException(
                    status_code=404,
                    detail="El comentario al que deseas responder no existe"
                )

        resultado = db.execute(
            text("""
                insert into comentarios (
                    comentario,
                    estatus,
                    usr_id,
                    blog_id,
                    com_padre_id
                )
                values (
                    :comentario,
                    1,
                    :usr_id,
                    :blog_id,
                    :com_padre_id
                )
            """),
            {
                "comentario": contenido,
                "usr_id": usuario["id_usr"],
                "blog_id": datos.blog_id,
                "com_padre_id": datos.com_padre_id
            }
        )

        db.commit()

        return {
            "mensaje": "Comentario registrado correctamente",
            "id_com": resultado.lastrowid,
            "blog_id": datos.blog_id
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar el comentario"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar el comentario"
        )


# Endpoint para modificar un comentario propio.
@router.put("/{id_com}")
def actualizar_comentario(
    id_com: int,
    datos: ComentarioActualizacion,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    contenido = datos.comentario.strip()

    if not contenido:
        raise HTTPException(
            status_code=422,
            detail="El comentario no puede estar vacio"
        )

    try:
        comentario = db.execute(
            text("""
                select usr_id, estatus
                from comentarios
                where id_com = :id_com
            """),
            {"id_com": id_com}
        ).mappings().first()

        if comentario is None or comentario["estatus"] != 1:
            raise HTTPException(
                status_code=404,
                detail="Comentario no encontrado"
            )

        if comentario["usr_id"] != usuario["id_usr"]:
            raise HTTPException(
                status_code=403,
                detail="No puedes modificar comentarios de otros usuarios"
            )

        db.execute(
            text("""
                update comentarios
                set comentario = :comentario
                where id_com = :id_com
            """),
            {
                "comentario": contenido,
                "id_com": id_com
            }
        )

        db.commit()

        return {
            "mensaje": "Comentario actualizado correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al actualizar el comentario"
        )


# Endpoint para retirar un comentario propio.
@router.delete("/{id_com}")
def eliminar_comentario(
    id_com: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        comentario = db.execute(
            text("""
                select usr_id, estatus
                from comentarios
                where id_com = :id_com
            """),
            {"id_com": id_com}
        ).mappings().first()

        if comentario is None or comentario["estatus"] != 1:
            raise HTTPException(
                status_code=404,
                detail="Comentario no encontrado"
            )

        if comentario["usr_id"] != usuario["id_usr"]:
            raise HTTPException(
                status_code=403,
                detail="No puedes eliminar comentarios de otros usuarios"
            )

        # Eliminacion logica para conservar las relaciones existentes.
        db.execute(
            text("""
                update comentarios
                set estatus = 0
                where id_com = :id_com
            """),
            {"id_com": id_com}
        )

        db.commit()

        return {
            "mensaje": "Comentario eliminado correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al eliminar el comentario"
        )


# Endpoint para que el administrador modere comentarios.
@router.patch("/{id_com}/moderar")
def moderar_comentario(
    id_com: int,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        comentario = db.execute(
            text("""
                select id_com
                from comentarios
                where id_com = :id_com
            """),
            {"id_com": id_com}
        ).first()

        if comentario is None:
            raise HTTPException(
                status_code=404,
                detail="Comentario no encontrado"
            )

        db.execute(
            text("""
                update comentarios
                set estatus = 0
                where id_com = :id_com
            """),
            {"id_com": id_com}
        )

        db.commit()

        return {
            "mensaje": "Comentario moderado correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al moderar el comentario"
        )
