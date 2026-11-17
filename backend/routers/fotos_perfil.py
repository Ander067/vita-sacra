import io
import logging
import re
import uuid
import warnings

from pathlib import Path
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import obtener_usuario_actual


router = APIRouter(
    prefix="/usuarios",
    tags=["Fotos de perfil"]
)

logger = logging.getLogger(__name__)

DIRECTORIO_PERFILES = (
    Path(__file__).resolve().parents[1] / "media" / "perfiles"
)

MAX_BYTES = 5 * 1024 * 1024
MAX_PIXELES = 20_000_000
TAMANO_MAXIMO = (512, 512)
FORMATOS_PERMITIDOS = {"JPEG", "PNG", "WEBP"}
PATRON_NOMBRE = re.compile(r"^[0-9a-f]{32}\.jpg$")


def _normalizar_imagen(contenido: bytes) -> bytes:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)

            with Image.open(io.BytesIO(contenido)) as imagen:
                if imagen.format not in FORMATOS_PERMITIDOS:
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

                imagen = ImageOps.exif_transpose(imagen)
                imagen.thumbnail(
                    TAMANO_MAXIMO,
                    Image.Resampling.LANCZOS
                )

                if imagen.mode in ("RGBA", "LA") or "transparency" in imagen.info:
                    imagen_rgba = imagen.convert("RGBA")
                    fondo = Image.new("RGB", imagen_rgba.size, (255, 255, 255))
                    fondo.paste(
                        imagen_rgba,
                        mask=imagen_rgba.getchannel("A")
                    )
                    imagen_final = fondo
                else:
                    imagen_final = imagen.convert("RGB")

                salida = io.BytesIO()
                imagen_final.save(
                    salida,
                    format="JPEG",
                    quality=85,
                    optimize=True
                )

                return salida.getvalue()

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


def _obtener_nombre_anterior(url_foto: str | None) -> str | None:
    if not url_foto:
        return None

    nombre = Path(urlparse(url_foto).path).name

    if not PATRON_NOMBRE.fullmatch(nombre):
        return None

    return nombre


def _eliminar_archivo_anterior(url_foto: str | None) -> None:
    nombre = _obtener_nombre_anterior(url_foto)

    if nombre is None:
        return

    ruta = DIRECTORIO_PERFILES / nombre

    try:
        ruta.unlink(missing_ok=True)
    except OSError:
        logger.exception("No se pudo eliminar la foto de perfil anterior")


@router.put("/mi-perfil/foto")
async def actualizar_foto_perfil(
    archivo: UploadFile = File(...),
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    contenido = await archivo.read(MAX_BYTES + 1)
    await archivo.close()

    if not contenido:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Selecciona una imagen"
        )

    if len(contenido) > MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="La imagen no puede superar los 5 MB"
        )

    imagen_jpeg = _normalizar_imagen(contenido)

    DIRECTORIO_PERFILES.mkdir(parents=True, exist_ok=True)

    nombre_archivo = f"{uuid.uuid4().hex}.jpg"
    ruta_temporal = DIRECTORIO_PERFILES / f".{nombre_archivo}.tmp"
    ruta_final = DIRECTORIO_PERFILES / nombre_archivo
    url_foto = f"/usuarios/fotos/{nombre_archivo}"

    anterior = db.execute(
        text("""
            select foto_perfil_url
            from usuario
            where id_usr = :usuario_id
        """),
        {"usuario_id": usuario["id_usr"]}
    ).mappings().first()

    if anterior is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Usuario no encontrado"
        )

    try:
        ruta_temporal.write_bytes(imagen_jpeg)
        ruta_temporal.replace(ruta_final)
    except OSError as error:
        ruta_temporal.unlink(missing_ok=True)
        logger.exception("No se pudo guardar la nueva foto de perfil")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible guardar la foto de perfil"
        ) from error

    try:
        db.execute(
            text("""
                update usuario
                set foto_perfil_url = :foto_url
                where id_usr = :usuario_id
            """),
            {
                "foto_url": url_foto,
                "usuario_id": usuario["id_usr"]
            }
        )
        db.commit()
    except SQLAlchemyError as error:
        db.rollback()

        try:
            ruta_final.unlink(missing_ok=True)
        except OSError:
            logger.exception(
                "No se pudo limpiar el archivo de foto tras un error de base de datos"
            )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible actualizar la foto de perfil"
        ) from error

    _eliminar_archivo_anterior(anterior["foto_perfil_url"])

    return {
        "mensaje": "Foto de perfil actualizada",
        "foto_perfil_url": url_foto
    }


@router.delete("/mi-perfil/foto")
def eliminar_foto_perfil(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    anterior = db.execute(
        text("""
            select foto_perfil_url
            from usuario
            where id_usr = :usuario_id
        """),
        {"usuario_id": usuario["id_usr"]}
    ).mappings().first()

    if anterior is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Usuario no encontrado"
        )

    try:
        db.execute(
            text("""
                update usuario
                set foto_perfil_url = null
                where id_usr = :usuario_id
            """),
            {"usuario_id": usuario["id_usr"]}
        )
        db.commit()
    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible eliminar la foto de perfil"
        ) from error

    _eliminar_archivo_anterior(anterior["foto_perfil_url"])

    return {
        "mensaje": "Foto de perfil eliminada",
        "foto_perfil_url": None
    }


@router.get("/fotos/{nombre_archivo}")
def consultar_foto_perfil(nombre_archivo: str):
    if not PATRON_NOMBRE.fullmatch(nombre_archivo):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Foto no encontrada"
        )

    ruta = DIRECTORIO_PERFILES / nombre_archivo

    if not ruta.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Foto no encontrada"
        )

    return FileResponse(
        ruta,
        media_type="image/jpeg",
        headers={
            "Cache-Control": "public, max-age=31536000, immutable",
            "X-Content-Type-Options": "nosniff"
        }
    )