from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError, IntegrityError

from database import get_db
from security.auth import obtener_usuario_actual

router = APIRouter(
    prefix="/personalizacion",
    tags=["Personalizacion"]
)


# Modelo para registrar un interes.
class InteresRegistro(BaseModel):
    categoria_id: int = Field(gt=0)


# Modelo para actualizar el tema visual.
class PreferenciaTema(BaseModel):
    tema: Literal["claro", "oscuro", "automatico"]


# Funcion para comprobar que una categoria esta activa.
def verificar_categoria(db: Session, categoria_id: int):
    categoria = db.execute(
        text("""
            select
                id_categoria,
                nombre
            from categorias
            where id_categoria = :categoria_id
            and activa = 1
        """),
        {"categoria_id": categoria_id}
    ).mappings().first()

    if categoria is None:
        raise HTTPException(
            status_code=404,
            detail="Categoria no encontrada o inactiva"
        )

    return dict(categoria)


# Endpoint para consultar las categorias disponibles.
@router.get("/categorias")
def consultar_categorias(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_categoria,
                    nombre,
                    descripcion
                from categorias
                where activa = 1
                order by nombre
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las categorias"
        )


# Endpoint para consultar los intereses del usuario.
@router.get("/mis-intereses")
def consultar_mis_intereses(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    i.categoria_id,
                    c.nombre,
                    c.descripcion,
                    c.activa
                from intereses i
                inner join categorias c
                    on i.categoria_id = c.id_categoria
                where i.usr_id = :usr_id
                order by c.nombre
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los intereses"
        )


# Endpoint para registrar una categoria de interes.
@router.post(
    "/intereses",
    status_code=status.HTTP_201_CREATED
)
def registrar_interes(
    datos: InteresRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        categoria = verificar_categoria(
            db,
            datos.categoria_id
        )

        existente = db.execute(
            text("""
                select categoria_id
                from intereses
                where usr_id = :usr_id
                and categoria_id = :categoria_id
            """),
            {
                "usr_id": usuario["id_usr"],
                "categoria_id": datos.categoria_id
            }
        ).first()

        if existente is not None:
            raise HTTPException(
                status_code=409,
                detail="Ya tienes registrada esta categoria"
            )

        db.execute(
            text("""
                insert into intereses (
                    usr_id,
                    categoria_id
                )
                values (
                    :usr_id,
                    :categoria_id
                )
            """),
            {
                "usr_id": usuario["id_usr"],
                "categoria_id": datos.categoria_id
            }
        )

        db.commit()

        return {
            "mensaje": "Interes registrado correctamente",
            "categoria_id": datos.categoria_id,
            "categoria": categoria["nombre"]
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar el interes"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar el interes"
        )


# Endpoint para eliminar una categoria de interes.
@router.delete("/intereses/{categoria_id}")
def eliminar_interes(
    categoria_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                delete from intereses
                where usr_id = :usr_id
                and categoria_id = :categoria_id
            """),
            {
                "usr_id": usuario["id_usr"],
                "categoria_id": categoria_id
            }
        )

        if resultado.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="La categoria no esta registrada en tus intereses"
            )

        db.commit()

        return {
            "mensaje": "Interes eliminado correctamente",
            "categoria_id": categoria_id
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al eliminar el interes"
        )


# Endpoint para consultar las preferencias personales.
@router.get("/mis-preferencias")
def consultar_mis_preferencias(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    usr_id,
                    tema
                from preferencias
                where usr_id = :usr_id
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().first()

        if resultado is None:
            return {
                "usr_id": usuario["id_usr"],
                "tema": "automatico"
            }

        return dict(resultado)

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las preferencias"
        )


# Endpoint para actualizar el tema visual.
@router.put("/tema")
def actualizar_tema(
    datos: PreferenciaTema,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        db.execute(
            text("""
                insert into preferencias (
                    usr_id,
                    tema
                )
                values (
                    :usr_id,
                    :tema
                )
                on duplicate key update
                    tema = values(tema)
            """),
            {
                "usr_id": usuario["id_usr"],
                "tema": datos.tema
            }
        )

        db.commit()

        return {
            "mensaje": "Preferencia actualizada correctamente",
            "tema": datos.tema
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al actualizar el tema"
        )


# Endpoint para consultar publicaciones recomendadas.
@router.get("/recomendaciones")
def consultar_recomendaciones(
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
                    c.nombre as categoria,
                    u.nom_usr as autor
                from blog_publico b
                inner join intereses i
                    on b.categoria_id = i.categoria_id
                inner join categorias c
                    on b.categoria_id = c.id_categoria
                inner join usuario u
                    on b.usr_id = u.id_usr
                where i.usr_id = :usr_id
                and c.activa = 1
                order by b.fecha_publicacion desc
                limit 20
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las recomendaciones"
        )


# Endpoint para descubrir publicaciones recientes.
@router.get("/descubrir")
def descubrir_publicaciones(
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
                    c.nombre as categoria,
                    u.nom_usr as autor
                from blog_publico b
                inner join categorias c
                    on b.categoria_id = c.id_categoria
                inner join usuario u
                    on b.usr_id = u.id_usr
                where c.activa = 1
                order by b.fecha_publicacion desc
                limit 20
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las publicaciones"
        )
