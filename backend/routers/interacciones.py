from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError, IntegrityError

from database import get_db
from security.auth import obtener_usuario_actual

router = APIRouter(
    prefix="/interacciones",
    tags=["Interacciones"]
)


# Modelo para registrar o actualizar una valoracion.
class ValoracionRegistro(BaseModel):
    blog_id: int = Field(gt=0)
    estrellas: int = Field(ge=1, le=5)


# Modelo para guardar una publicacion.
class PublicacionGuardada(BaseModel):
    blog_id: int = Field(gt=0)


# Funcion para verificar que una publicacion sea publica.
def verificar_publicacion(db: Session, blog_id: int):
    publicacion = db.execute(
        text("""
            select id_blog
            from blog_publico
            where id_blog = :blog_id
        """),
        {"blog_id": blog_id}
    ).first()

    if publicacion is None:
        raise HTTPException(
            status_code=404,
            detail="Publicacion no encontrada o no disponible"
        )


# Endpoint para consultar el resumen de valoraciones.
@router.get("/valoraciones/{blog_id}")
def consultar_valoraciones(
    blog_id: int,
    db: Session = Depends(get_db)
):
    try:
        verificar_publicacion(db, blog_id)

        resultado = db.execute(
            text("""
                select
                    blog_id,
                    count(*) as total_valoraciones,
                    round(avg(estrellas), 2) as promedio_estrellas
                from valoraciones
                where blog_id = :blog_id
                group by blog_id
            """),
            {"blog_id": blog_id}
        ).mappings().first()

        if resultado is None:
            return {
                "blog_id": blog_id,
                "total_valoraciones": 0,
                "promedio_estrellas": None
            }

        return dict(resultado)

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las valoraciones"
        )


# Endpoint para consultar la valoracion propia.
@router.get("/mi-valoracion/{blog_id}")
def consultar_mi_valoracion(
    blog_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_publicacion(db, blog_id)

        resultado = db.execute(
            text("""
                select
                    blog_id,
                    estrellas
                from valoraciones
                where usr_id = :usr_id
                and blog_id = :blog_id
            """),
            {
                "usr_id": usuario["id_usr"],
                "blog_id": blog_id
            }
        ).mappings().first()

        if resultado is None:
            raise HTTPException(
                status_code=404,
                detail="No has valorado esta publicacion"
            )

        return dict(resultado)

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tu valoracion"
        )


# Endpoint para registrar o actualizar una valoracion.
@router.post("/valorar")
def registrar_valoracion(
    datos: ValoracionRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_publicacion(db, datos.blog_id)

        # La clave primaria compuesta evita valoraciones duplicadas.
        db.execute(
            text("""
                insert into valoraciones (
                    usr_id,
                    blog_id,
                    estrellas
                )
                values (
                    :usr_id,
                    :blog_id,
                    :estrellas
                )
                on duplicate key update
                    estrellas = values(estrellas)
            """),
            {
                "usr_id": usuario["id_usr"],
                "blog_id": datos.blog_id,
                "estrellas": datos.estrellas
            }
        )

        db.commit()

        return {
            "mensaje": "Valoracion guardada correctamente",
            "blog_id": datos.blog_id,
            "estrellas": datos.estrellas
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible guardar la valoracion"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al guardar la valoracion"
        )


# Endpoint para eliminar una valoracion propia.
@router.delete("/valoraciones/{blog_id}")
def eliminar_valoracion(
    blog_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                delete from valoraciones
                where usr_id = :usr_id
                and blog_id = :blog_id
            """),
            {
                "usr_id": usuario["id_usr"],
                "blog_id": blog_id
            }
        )

        if resultado.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="No existe una valoracion para eliminar"
            )

        db.commit()

        return {
            "mensaje": "Valoracion eliminada correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al eliminar la valoracion"
        )


# Endpoint para consultar las publicaciones guardadas.
@router.get("/guardados")
def consultar_guardados(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    b.id_blog,
                    b.titulo,
                    b.`desc` as descripcion,
                    b.img,
                    b.slug,
                    b.tipo,
                    b.fecha_publicacion,
                    g.fecha as fecha_guardado
                from guardados g
                inner join blog_publico b
                    on g.blog_id = b.id_blog
                where g.usr_id = :usr_id
                order by g.fecha desc
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las publicaciones guardadas"
        )


# Endpoint para guardar una publicacion.
@router.post(
    "/guardar",
    status_code=status.HTTP_201_CREATED
)
def guardar_publicacion(
    datos: PublicacionGuardada,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_publicacion(db, datos.blog_id)

        resultado = db.execute(
            text("""
                insert ignore into guardados (
                    usr_id,
                    blog_id
                )
                values (
                    :usr_id,
                    :blog_id
                )
            """),
            {
                "usr_id": usuario["id_usr"],
                "blog_id": datos.blog_id
            }
        )

        db.commit()

        if resultado.rowcount == 0:
            return {
                "mensaje": "La publicacion ya estaba guardada",
                "blog_id": datos.blog_id
            }

        return {
            "mensaje": "Publicacion guardada correctamente",
            "blog_id": datos.blog_id
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible guardar la publicacion"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al guardar la publicacion"
        )


# Endpoint para eliminar una publicacion guardada.
@router.delete("/guardados/{blog_id}")
def eliminar_guardado(
    blog_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                delete from guardados
                where usr_id = :usr_id
                and blog_id = :blog_id
            """),
            {
                "usr_id": usuario["id_usr"],
                "blog_id": blog_id
            }
        )

        if resultado.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="La publicacion no se encuentra guardada"
            )

        db.commit()

        return {
            "mensaje": "Publicacion retirada de guardados"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al eliminar la publicacion guardada"
        )
