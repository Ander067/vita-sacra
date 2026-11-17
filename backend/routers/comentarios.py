import io
import logging
import re
import uuid
import warnings

from pathlib import Path

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    UploadFile,
    status
)
from fastapi.responses import FileResponse
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from database import get_db
from security.auth import obtener_usuario_actual, verificar_roles


router = APIRouter(
    prefix="/comentarios",
    tags=["Comentarios"]
)

logger = logging.getLogger(__name__)

DIRECTORIO_COMENTARIOS = (
    Path(__file__).resolve().parents[1] / "media" / "comentarios"
)

MAX_BYTES = 3 * 1024 * 1024
MAX_PIXELES = 20_000_000
FORMATOS_PERMITIDOS = {"JPEG", "PNG", "WEBP"}
EXTENSIONES_FORMATO = {
    "JPEG": (".jpg", "image/jpeg"),
    "PNG": (".png", "image/png"),
    "WEBP": (".webp", "image/webp")
}
PREFIJO_ARCHIVO_LOCAL = "local:comentarios/"
PATRON_NOMBRE_ARCHIVO = re.compile(
    r"^[0-9a-f]{32}\.(jpg|png|webp)$"
)


class ComentarioRegistro(BaseModel):
    blog_id: int = Field(gt=0)
    comentario: str = Field(min_length=1, max_length=5000)
    com_padre_id: int | None = Field(default=None, gt=0)


class ComentarioActualizacion(BaseModel):
    comentario: str = Field(min_length=1, max_length=5000)


def _normalizar_imagen(contenido: bytes) -> tuple[bytes, str, str]:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)

            with Image.open(io.BytesIO(contenido)) as imagen:
                formato = imagen.format

                if formato not in FORMATOS_PERMITIDOS:
                    raise HTTPException(
                        status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                        detail="La imagen debe ser JPEG, PNG o WebP"
                    )

                imagen.verify()

            with Image.open(io.BytesIO(contenido)) as imagen:
                if imagen.width * imagen.height > MAX_PIXELES:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="La resolución de la imagen es demasiado grande"
                    )

                if getattr(imagen, "n_frames", 1) != 1:
                    raise HTTPException(
                        status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                        detail="La imagen no puede ser animada"
                    )

                imagen.load()
                imagen = ImageOps.exif_transpose(imagen)

                tiene_transparencia = (
                    "A" in imagen.getbands()
                    or "transparency" in imagen.info
                )

                salida = io.BytesIO()

                if formato == "JPEG":
                    imagen.convert("RGB").save(
                        salida,
                        format="JPEG",
                        quality=90,
                        optimize=True
                    )
                elif formato == "PNG":
                    modo = "RGBA" if tiene_transparencia else "RGB"
                    imagen.convert(modo).save(
                        salida,
                        format="PNG",
                        optimize=True
                    )
                else:
                    modo = "RGBA" if tiene_transparencia else "RGB"
                    imagen.convert(modo).save(
                        salida,
                        format="WEBP",
                        quality=90,
                        method=6
                    )

                contenido_limpio = salida.getvalue()

                if len(contenido_limpio) > MAX_BYTES:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="La imagen procesada supera el límite de 3 MB"
                    )

                extension, mime = EXTENSIONES_FORMATO[formato]
                return contenido_limpio, mime, extension

    except HTTPException:
        raise
    except (
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
        UnidentifiedImageError,
        OSError,
        ValueError
    ) as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El archivo no contiene una imagen válida"
        ) from error


def _url_catalogo_valida(url: str | None) -> bool:
    if not url:
        return False

    limpia = url.strip()

    if limpia.startswith("https://"):
        return True

    return (
        limpia.startswith("/")
        and not limpia.startswith("//")
        and "\\" not in limpia
    )


def _validar_publicacion(db: Session, blog_id: int) -> None:
    publicacion = db.execute(
        text("""
            select id_blog
            from blog
            where id_blog = :id_blog
            and estatus = 'publicado'
            and version_publica is not null
        """),
        {"id_blog": blog_id}
    ).first()

    if publicacion is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="La publicación no está disponible"
        )


def _validar_comentario_padre(
    db: Session,
    blog_id: int,
    com_padre_id: int | None
) -> None:
    if com_padre_id is None:
        return

    comentario_padre = db.execute(
        text("""
            select id_com
            from comentarios
            where id_com = :id_com
            and blog_id = :blog_id
            and estatus = 1
        """),
        {
            "id_com": com_padre_id,
            "blog_id": blog_id
        }
    ).first()

    if comentario_padre is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="El comentario al que deseas responder no existe"
        )


@router.get("/catalogo")
def consultar_catalogo_comentarios(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_recurso,
                    tipo,
                    url,
                    mime,
                    titulo,
                    licencia,
                    procedencia
                from recursos
                where estatus = 'aprobado'
                and tipo in ('gif', 'sticker')
                and licencia is not null
                and trim(licencia) <> ''
                and procedencia is not null
                and trim(procedencia) <> ''
                order by tipo, titulo, id_recurso
            """)
        ).mappings().all()

        catalogo = []

        for fila in resultado:
            recurso = dict(fila)

            if _url_catalogo_valida(recurso.get("url")):
                catalogo.append(recurso)

        return catalogo

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar el catálogo de comentarios"
        ) from error


@router.get("/publicacion/{id_blog}")
def consultar_comentarios(
    id_blog: int,
    db: Session = Depends(get_db)
):
    try:
        _validar_publicacion(db, id_blog)

        filas = db.execute(
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

        comentarios = [dict(fila) for fila in filas]

        for comentario in comentarios:
            comentario["adjuntos"] = []

        if not comentarios:
            return comentarios

        adjuntos = db.execute(
            text("""
                select
                    cr.com_id,
                    r.id_recurso,
                    r.tipo,
                    r.url,
                    r.mime,
                    r.titulo
                from comentario_recursos cr
                inner join recursos r
                    on r.id_recurso = cr.recurso_id
                inner join comentarios c
                    on c.id_com = cr.com_id
                where c.blog_id = :id_blog
                and c.estatus = 1
                and r.estatus = 'aprobado'
                order by cr.com_id, r.id_recurso
            """),
            {"id_blog": id_blog}
        ).mappings().all()

        comentarios_por_id = {
            comentario["id_com"]: comentario
            for comentario in comentarios
        }

        for fila in adjuntos:
            adjunto = dict(fila)
            comentario = comentarios_por_id.get(adjunto.pop("com_id"))

            if comentario is None:
                continue

            url = adjunto.get("url", "")

            if url.startswith(PREFIJO_ARCHIVO_LOCAL):
                adjunto["url"] = (
                    f"/comentarios/recursos/"
                    f"{adjunto['id_recurso']}/archivo"
                )
            elif not _url_catalogo_valida(url):
                continue

            adjunto.pop("url_original", None)
            comentario["adjuntos"].append(adjunto)

        return comentarios

    except HTTPException:
        raise
    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar los comentarios"
        ) from error


@router.post("/registrar", status_code=status.HTTP_201_CREATED)
def registrar_comentario(
    datos: ComentarioRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    contenido = datos.comentario.strip()

    if not contenido:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El comentario no puede estar vacío"
        )

    try:
        _validar_publicacion(db, datos.blog_id)
        _validar_comentario_padre(
            db,
            datos.blog_id,
            datos.com_padre_id
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

    except HTTPException:
        db.rollback()
        raise
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No fue posible registrar el comentario"
        ) from error
    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al registrar el comentario"
        ) from error


@router.post(
    "/registrar-multimedia",
    status_code=status.HTTP_201_CREATED
)
async def registrar_comentario_multimedia(
    blog_id: int = Form(..., gt=0),
    comentario: str = Form(..., min_length=1, max_length=5000),
    com_padre_id: int | None = Form(default=None, gt=0),
    recurso_catalogo_id: int | None = Form(default=None, gt=0),
    archivo: UploadFile | None = File(default=None),
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    contenido = comentario.strip()

    if not contenido:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El comentario no puede estar vacío"
        )

    contenido_archivo = None
    mime_archivo = None
    extension_archivo = None

    if archivo is not None:
        try:
            contenido_original = await archivo.read(MAX_BYTES + 1)
        finally:
            await archivo.close()

        if not contenido_original:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El archivo está vacío"
            )

        if len(contenido_original) > MAX_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="La imagen no puede superar los 3 MB"
            )

        (
            contenido_archivo,
            mime_archivo,
            extension_archivo
        ) = _normalizar_imagen(contenido_original)

    ruta_temporal = None
    ruta_final = None
    nombre_archivo = None

    try:
        _validar_publicacion(db, blog_id)
        _validar_comentario_padre(db, blog_id, com_padre_id)

        recurso_catalogo = None

        if recurso_catalogo_id is not None:
            recurso_catalogo = db.execute(
                text("""
                    select
                        id_recurso,
                        tipo,
                        url,
                        licencia,
                        procedencia
                    from recursos
                    where id_recurso = :recurso_id
                    and estatus = 'aprobado'
                    and tipo in ('gif', 'sticker')
                """),
                {"recurso_id": recurso_catalogo_id}
            ).mappings().first()

            if recurso_catalogo is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="El sticker o GIF no está disponible"
                )

            if (
                not recurso_catalogo["licencia"]
                or not recurso_catalogo["licencia"].strip()
                or not recurso_catalogo["procedencia"]
                or not recurso_catalogo["procedencia"].strip()
                or not _url_catalogo_valida(recurso_catalogo["url"])
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El recurso no tiene licencia, procedencia o URL válida"
                )

        if contenido_archivo is not None:
            DIRECTORIO_COMENTARIOS.mkdir(
                parents=True,
                exist_ok=True
            )

            nombre_archivo = (
                f"{uuid.uuid4().hex}{extension_archivo}"
            )
            ruta_temporal = (
                DIRECTORIO_COMENTARIOS
                / f".{nombre_archivo}.tmp"
            )
            ruta_final = DIRECTORIO_COMENTARIOS / nombre_archivo

            try:
                ruta_temporal.write_bytes(contenido_archivo)
                ruta_temporal.replace(ruta_final)
            except OSError as error:
                ruta_temporal.unlink(missing_ok=True)
                logger.exception(
                    "No se pudo guardar la imagen del comentario"
                )
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="No fue posible guardar la imagen"
                ) from error

        resultado_comentario = db.execute(
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
                "blog_id": blog_id,
                "com_padre_id": com_padre_id
            }
        )

        id_comentario = resultado_comentario.lastrowid

        if recurso_catalogo is not None:
            db.execute(
                text("""
                    insert into comentario_recursos (
                        com_id,
                        recurso_id
                    )
                    values (
                        :com_id,
                        :recurso_id
                    )
                """),
                {
                    "com_id": id_comentario,
                    "recurso_id": recurso_catalogo_id
                }
            )

        id_imagen = None

        if nombre_archivo is not None:
            resultado_recurso = db.execute(
                text("""
                    insert into recursos (
                        usr_id,
                        tipo,
                        url,
                        mime,
                        titulo,
                        licencia,
                        procedencia,
                        estatus
                    )
                    values (
                        :usr_id,
                        'imagen',
                        :url,
                        :mime,
                        'Imagen adjunta a comentario',
                        'Declaración del usuario',
                        'Carga desde comentario móvil',
                        'pendiente'
                    )
                """),
                {
                    "usr_id": usuario["id_usr"],
                    "url": f"{PREFIJO_ARCHIVO_LOCAL}{nombre_archivo}",
                    "mime": mime_archivo
                }
            )

            id_imagen = resultado_recurso.lastrowid

            db.execute(
                text("""
                    insert into comentario_recursos (
                        com_id,
                        recurso_id
                    )
                    values (
                        :com_id,
                        :recurso_id
                    )
                """),
                {
                    "com_id": id_comentario,
                    "recurso_id": id_imagen
                }
            )

        db.commit()

        return {
            "mensaje": (
                "Comentario registrado. La imagen quedó pendiente de revisión."
                if id_imagen is not None
                else "Comentario registrado correctamente"
            ),
            "id_com": id_comentario,
            "blog_id": blog_id,
            "estatus_imagen": (
                "pendiente" if id_imagen is not None else None
            ),
            "id_recurso_imagen": id_imagen,
            "id_recurso_catalogo": recurso_catalogo_id
        }

    except HTTPException:
        db.rollback()

        if ruta_temporal is not None:
            ruta_temporal.unlink(missing_ok=True)
        if ruta_final is not None:
            ruta_final.unlink(missing_ok=True)

        raise
    except IntegrityError as error:
        db.rollback()

        if ruta_temporal is not None:
            ruta_temporal.unlink(missing_ok=True)
        if ruta_final is not None:
            ruta_final.unlink(missing_ok=True)

        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No fue posible registrar el comentario multimedia"
        ) from error
    except SQLAlchemyError as error:
        db.rollback()

        if ruta_temporal is not None:
            ruta_temporal.unlink(missing_ok=True)
        if ruta_final is not None:
            ruta_final.unlink(missing_ok=True)

        logger.exception(
            "Error al registrar un comentario multimedia"
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al registrar el comentario multimedia"
        ) from error


@router.get("/recursos/{recurso_id}/archivo")
def consultar_archivo_comentario(
    recurso_id: int,
    db: Session = Depends(get_db)
):
    try:
        recurso = db.execute(
            text("""
                select url, mime, estatus, tipo
                from recursos
                where id_recurso = :recurso_id
            """),
            {"recurso_id": recurso_id}
        ).mappings().first()

        if (
            recurso is None
            or recurso["estatus"] != "aprobado"
            or recurso["tipo"] != "imagen"
            or not recurso["url"]
            or not recurso["url"].startswith(PREFIJO_ARCHIVO_LOCAL)
        ):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Imagen no disponible"
            )

        nombre_archivo = recurso["url"][len(PREFIJO_ARCHIVO_LOCAL):]

        if not PATRON_NOMBRE_ARCHIVO.fullmatch(nombre_archivo):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Imagen no disponible"
            )

        ruta = DIRECTORIO_COMENTARIOS / nombre_archivo

        if not ruta.is_file():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Imagen no disponible"
            )

        return FileResponse(
            ruta,
            media_type=recurso["mime"] or "application/octet-stream",
            headers={
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff"
            }
        )

    except HTTPException:
        raise
    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al consultar la imagen"
        ) from error


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
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El comentario no puede estar vacío"
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
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Comentario no encontrado"
            )

        if comentario["usr_id"] != usuario["id_usr"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
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

    except HTTPException:
        db.rollback()
        raise
    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al actualizar el comentario"
        ) from error


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
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Comentario no encontrado"
            )

        if comentario["usr_id"] != usuario["id_usr"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No puedes eliminar comentarios de otros usuarios"
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
            "mensaje": "Comentario eliminado correctamente"
        }

    except HTTPException:
        db.rollback()
        raise
    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al eliminar el comentario"
        ) from error


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
                status_code=status.HTTP_404_NOT_FOUND,
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

    except HTTPException:
        db.rollback()
        raise
    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error al moderar el comentario"
        ) from error