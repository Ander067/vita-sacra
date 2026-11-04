import os

from dotenv import load_dotenv
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from routers import (
    autenticacion,
    comentarios,
    establecimientos,
    interacciones,
    moderacion,
    pagos,
    personalizacion,
    promociones,
    publicaciones,
    recursos,
    roles,
    usuarios
)


# Cargar las variables de entorno del proyecto.
load_dotenv()


# Configuracion principal de FastAPI.
app = FastAPI(
    title="Vita Sacra API",
    description="API REST del proyecto Vita Sacra 1.0.0 - Arca",
    version="1.0.0"
)


# Direcciones permitidas para los clientes web.
# Las direcciones adicionales pueden configurarse en .env.
origenes_predeterminados = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:8080",
    "http://127.0.0.1:8080"
]


# Obtener las direcciones adicionales desde variables de entorno.
origenes_adicionales = os.getenv(
    "CORS_ORIGINS",
    ""
)


# Separar las direcciones configuradas.
origenes_configurados = [
    origen.strip().rstrip("/")
    for origen in origenes_adicionales.split(",")
    if origen.strip()
]


# Unificar las direcciones sin repetir elementos.
origenes_permitidos = list(
    dict.fromkeys(
        origenes_predeterminados + origenes_configurados
    )
)


# Configuracion de acceso desde clientes web y moviles.
app.add_middleware(
    CORSMiddleware,
    allow_origins=origenes_permitidos,
    allow_credentials=False,
    allow_methods=[
        "GET",
        "POST",
        "PUT",
        "PATCH",
        "DELETE",
        "OPTIONS"
    ],
    allow_headers=[
        "Content-Type",
        "Authorization"
    ]
)


# Registro de los modulos de la API REST.
app.include_router(autenticacion.router)
app.include_router(usuarios.router)
app.include_router(roles.router)
app.include_router(publicaciones.router)
app.include_router(comentarios.router)
app.include_router(interacciones.router)
app.include_router(personalizacion.router)
app.include_router(recursos.router)
app.include_router(establecimientos.router)
app.include_router(moderacion.router)
app.include_router(promociones.router)
app.include_router(pagos.router)


# Comprobar que la API se encuentra activa.
@app.get("/")
def inicio():
    return {
        "proyecto": "Vita Sacra",
        "version": "1.0.0",
        "nombre": "Arca",
        "estado": "API REST activa"
    }


# Comprobar la conexion con MariaDB.
@app.get("/verificar-conexion")
def verificar_conexion(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select database() as base_datos
            """)
        ).mappings().first()

        # Verificar que exista una base de datos seleccionada.
        if resultado is None or resultado["base_datos"] is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="No hay una base de datos seleccionada"
            )

        return {
            "estado": "Conexion exitosa",
            "base_datos": resultado["base_datos"]
        }

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No se pudo establecer la conexion con MariaDB"
        ) from error


# Consultar los roles principales disponibles.
@app.get("/roles")
def obtener_roles(
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

        return [
            dict(fila)
            for fila in resultado
        ]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar los roles"
        ) from error


# Consultar las categorias activas.
@app.get("/categorias")
def obtener_categorias(
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

        return [
            dict(fila)
            for fila in resultado
        ]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar las categorias"
        ) from error


# Consultar las plantillas disponibles.
@app.get("/plantillas")
def obtener_plantillas(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_plantilla,
                    nombre,
                    descripcion
                from plantillas
                order by id_plantilla
            """)
        ).mappings().all()

        return [
            dict(fila)
            for fila in resultado
        ]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar las plantillas"
        ) from error


# Consultar las publicaciones aprobadas.
# Se utiliza la vista publica para mostrar solo versiones autorizadas.
@app.get("/posts")
def obtener_publicaciones(
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
                    b.id_version,
                    u.nom_usr as autor
                from blog_publico b
                inner join usuario u
                    on b.usr_id = u.id_usr
                order by b.fecha_publicacion desc
            """)
        ).mappings().all()

        return [
            dict(fila)
            for fila in resultado
        ]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar las publicaciones"
        ) from error


# Consultar el detalle de una publicacion.
@app.get("/posts/{id_blog}")
def obtener_publicacion(
    id_blog: int,
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
                    b.id_version,
                    b.advertencia,
                    u.nom_usr as autor
                from blog_publico b
                inner join usuario u
                    on b.usr_id = u.id_usr
                where b.id_blog = :id_blog
            """),
            {
                "id_blog": id_blog
            }
        ).mappings().first()

        # Comprobar que la publicacion exista y sea publica.
        if resultado is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Publicacion no encontrada"
            )

        return dict(resultado)

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar la publicacion"
        ) from error


# Consultar los comentarios publicos de una publicacion.
@app.get("/posts/{id_blog}/comentarios")
def obtener_comentarios(
    id_blog: int,
    db: Session = Depends(get_db)
):
    try:
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
                inner join blog_publico b
                    on c.blog_id = b.id_blog
                where c.blog_id = :id_blog
                and c.estatus = 1
                order by c.fecha asc
            """),
            {
                "id_blog": id_blog
            }
        ).mappings().all()

        return [
            dict(fila)
            for fila in resultado
        ]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar los comentarios"
        ) from error