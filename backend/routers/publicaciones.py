import re
import unicodedata

from typing import Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import verificar_roles


router = APIRouter(
    prefix="/publicaciones",
    tags=["Publicaciones"]
)


# Estados en los que un autor puede modificar una publicacion.
ESTADOS_EDITABLES = (
    "borrador",
    "correccion",
    "rechazado"
)


# Modelo para registrar una publicacion.
class PublicacionRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    categoria_id: int = Field(gt=0)
    plantilla_id: int = Field(default=1, gt=0)
    titulo: str = Field(min_length=5, max_length=200)
    descripcion: str | None = Field(default=None, max_length=500)
    img: str | None = Field(default=None, max_length=255)

    tipo: Literal[
        "articulo",
        "ficha_medicamento",
        "ficha_producto"
    ] = "articulo"


# Modelo para actualizar una publicacion.
class PublicacionActualizacion(PublicacionRegistro):
    pass


# Modelo para registrar una version.
class VersionRegistro(BaseModel):
    advertencia: str | None = None


# Modelo para revisar una version.
class RevisionPublicacion(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    decision: Literal[
        "aprobada",
        "correccion",
        "rechazada",
        "oculta"
    ]

    observacion: str | None = None


# Modelo para asociar una etiqueta.
class EtiquetaRegistro(BaseModel):
    etiqueta_id: int = Field(gt=0)


# Generar un slug unico para cada publicacion.
def generar_slug(titulo: str) -> str:
    normalizado = unicodedata.normalize(
        "NFKD",
        titulo.lower()
    )

    texto = "".join(
        caracter
        for caracter in normalizado
        if not unicodedata.combining(caracter)
    )

    texto = re.sub(
        r"[^a-z0-9]+",
        "-",
        texto
    ).strip("-")

    if not texto:
        texto = "publicacion"

    identificador = uuid4().hex[:10]

    return f"{texto[:200]}-{identificador}"


# Verificar que una categoria exista y este activa.
def verificar_categoria(
    db: Session,
    categoria_id: int
) -> None:
    categoria = db.execute(
        text("""
            select id_categoria
            from categorias
            where id_categoria = :categoria_id
            and activa = 1
        """),
        {"categoria_id": categoria_id}
    ).first()

    if categoria is None:
        raise HTTPException(
            status_code=404,
            detail="Categoria no encontrada o inactiva"
        )


# Verificar que una plantilla exista.
def verificar_plantilla(
    db: Session,
    plantilla_id: int
) -> None:
    plantilla = db.execute(
        text("""
            select id_plantilla
            from plantillas
            where id_plantilla = :plantilla_id
        """),
        {"plantilla_id": plantilla_id}
    ).first()

    if plantilla is None:
        raise HTTPException(
            status_code=404,
            detail="Plantilla no encontrada"
        )


# Consultar una publicacion y verificar su propietario.
def obtener_publicacion_autor(
    db: Session,
    id_blog: int,
    usuario_id: int,
    bloquear: bool = False
) -> dict:
    consulta = """
        select
            id_blog,
            usr_id,
            categoria_id,
            plantilla_id,
            titulo,
            `desc` as descripcion,
            img,
            slug,
            tipo,
            estatus,
            version_publica,
            fecha_creacion,
            fecha_publicacion
        from blog
        where id_blog = :id_blog
        and usr_id = :usuario_id
    """

    if bloquear:
        consulta += " for update"

    publicacion = db.execute(
        text(consulta),
        {
            "id_blog": id_blog,
            "usuario_id": usuario_id
        }
    ).mappings().first()

    if publicacion is None:
        raise HTTPException(
            status_code=404,
            detail="Publicacion no encontrada para este autor"
        )

    return dict(publicacion)


# Verificar que una publicacion permita modificaciones.
def verificar_estado_editable(publicacion: dict) -> None:
    if publicacion["estatus"] not in ESTADOS_EDITABLES:
        raise HTTPException(
            status_code=409,
            detail="La publicacion no admite modificaciones"
        )


# Obtener la ultima version de una publicacion.
def obtener_ultima_version(
    db: Session,
    id_blog: int
) -> dict:
    version = db.execute(
        text("""
            select
                id_version,
                blog_id,
                numero,
                advertencia,
                fecha
            from versiones_blog
            where blog_id = :id_blog
            order by numero desc
            limit 1
        """),
        {"id_blog": id_blog}
    ).mappings().first()

    if version is None:
        raise HTTPException(
            status_code=409,
            detail="La publicacion no tiene versiones"
        )

    return dict(version)


# Comprobar que una version tenga bloques de contenido.
def verificar_contenido_version(
    db: Session,
    id_version: int
) -> None:
    total = db.execute(
        text("""
            select count(*)
            from bloques_version
            where version_id = :id_version
        """),
        {"id_version": id_version}
    ).scalar_one()

    if total == 0:
        raise HTTPException(
            status_code=409,
            detail="La version debe contener al menos un bloque"
        )


# Verificar si un usuario tiene el rol de administrador.
def es_administrador(
    db: Session,
    usuario_id: int
) -> bool:
    resultado = db.execute(
        text("""
            select 1
            from usuario_roles ur
            inner join roles r
                on ur.rol_id = r.id_rol
            where ur.usr_id = :usuario_id
            and lower(r.nombre) = 'administrador'
            limit 1
        """),
        {"usuario_id": usuario_id}
    ).first()

    return resultado is not None


# Consultar las categorias activas.
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

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las categorias"
        ) from error


# Consultar las plantillas disponibles.
@router.get("/plantillas")
def consultar_plantillas(
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

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las plantillas"
        ) from error


# Consultar las etiquetas disponibles.
@router.get("/etiquetas")
def consultar_etiquetas(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_etiqueta,
                    nombre
                from etiquetas
                order by nombre
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las etiquetas"
        ) from error


# Consultar las publicaciones visibles al publico.
@router.get("/")
def consultar_publicaciones(
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
                order by b.fecha_publicacion desc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las publicaciones"
        ) from error


# Consultar las publicaciones del autor autenticado.
@router.get("/mis-publicaciones")
def consultar_mis_publicaciones(
    usuario: dict = Depends(verificar_roles("autor")),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_blog,
                    categoria_id,
                    plantilla_id,
                    titulo,
                    `desc` as descripcion,
                    img,
                    slug,
                    tipo,
                    estatus,
                    version_publica,
                    fecha_creacion,
                    fecha_publicacion
                from blog
                where usr_id = :usuario_id
                order by fecha_creacion desc
            """),
            {"usuario_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tus publicaciones"
        ) from error


# Consultar publicaciones pendientes de revision.
@router.get("/administracion/pendientes")
def consultar_pendientes(
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    b.id_blog,
                    b.titulo,
                    b.tipo,
                    b.estatus,
                    b.fecha_creacion,
                    u.nom_usr as autor,
                    v.id_version,
                    v.numero,
                    v.fecha as fecha_version
                from blog b
                inner join usuario u
                    on b.usr_id = u.id_usr
                inner join versiones_blog v
                    on v.blog_id = b.id_blog
                where b.estatus = 'revision'
                and v.numero = (
                    select max(v2.numero)
                    from versiones_blog v2
                    where v2.blog_id = b.id_blog
                )
                order by v.fecha asc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las publicaciones pendientes"
        ) from error


# Consultar una publicacion publica por identificador.
@router.get("/{id_blog}")
def consultar_publicacion(
    id_blog: int,
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    b.*,
                    c.nombre as categoria,
                    u.nom_usr as autor
                from blog_publico b
                inner join categorias c
                    on b.categoria_id = c.id_categoria
                inner join usuario u
                    on b.usr_id = u.id_usr
                where b.id_blog = :id_blog
            """),
            {"id_blog": id_blog}
        ).mappings().first()

        if resultado is None:
            raise HTTPException(
                status_code=404,
                detail="Publicacion no encontrada"
            )

        return dict(resultado)

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar la publicacion"
        ) from error


# Registrar una publicacion y su primera version.
@router.post(
    "/registrar",
    status_code=status.HTTP_201_CREATED
)
def registrar_publicacion(
    datos: PublicacionRegistro,
    usuario: dict = Depends(verificar_roles("autor")),
    db: Session = Depends(get_db)
):
    try:
        verificar_categoria(
            db,
            datos.categoria_id
        )

        verificar_plantilla(
            db,
            datos.plantilla_id
        )

        slug = generar_slug(datos.titulo)

        resultado = db.execute(
            text("""
                insert into blog (
                    usr_id,
                    categoria_id,
                    plantilla_id,
                    titulo,
                    `desc`,
                    img,
                    slug,
                    tipo,
                    estatus
                )
                values (
                    :usr_id,
                    :categoria_id,
                    :plantilla_id,
                    :titulo,
                    :descripcion,
                    :img,
                    :slug,
                    :tipo,
                    'borrador'
                )
            """),
            {
                "usr_id": usuario["id_usr"],
                "categoria_id": datos.categoria_id,
                "plantilla_id": datos.plantilla_id,
                "titulo": datos.titulo,
                "descripcion": datos.descripcion,
                "img": datos.img,
                "slug": slug,
                "tipo": datos.tipo
            }
        )

        id_blog = resultado.lastrowid

        version = db.execute(
            text("""
                insert into versiones_blog (
                    blog_id,
                    numero
                )
                values (
                    :blog_id,
                    1
                )
            """),
            {"blog_id": id_blog}
        )

        id_version = version.lastrowid

        db.commit()

        return {
            "mensaje": "Publicacion creada correctamente",
            "id_blog": id_blog,
            "id_version": id_version,
            "slug": slug,
            "version": 1,
            "estatus": "borrador"
        }

    except IntegrityError as error:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar la publicacion"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al registrar la publicacion"
        ) from error


# Actualizar los datos de una publicacion editable.
@router.put("/{id_blog}")
def actualizar_publicacion(
    id_blog: int,
    datos: PublicacionActualizacion,
    usuario: dict = Depends(verificar_roles("autor")),
    db: Session = Depends(get_db)
):
    try:
        publicacion = obtener_publicacion_autor(
            db,
            id_blog,
            usuario["id_usr"],
            bloquear=True
        )

        verificar_estado_editable(publicacion)

        verificar_categoria(
            db,
            datos.categoria_id
        )

        verificar_plantilla(
            db,
            datos.plantilla_id
        )

        resultado = db.execute(
            text("""
                update blog
                set
                    categoria_id = :categoria_id,
                    plantilla_id = :plantilla_id,
                    titulo = :titulo,
                    `desc` = :descripcion,
                    img = :img,
                    tipo = :tipo
                where id_blog = :id_blog
                and usr_id = :usr_id
                and estatus in (
                    'borrador',
                    'correccion',
                    'rechazado'
                )
            """),
            {
                "categoria_id": datos.categoria_id,
                "plantilla_id": datos.plantilla_id,
                "titulo": datos.titulo,
                "descripcion": datos.descripcion,
                "img": datos.img,
                "tipo": datos.tipo,
                "id_blog": id_blog,
                "usr_id": usuario["id_usr"]
            }
        )

        if resultado.rowcount != 1:
            db.rollback()

            raise HTTPException(
                status_code=409,
                detail="La publicacion no pudo actualizarse"
            )

        db.commit()

        return {
            "mensaje": "Publicacion actualizada correctamente",
            "id_blog": id_blog
        }

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al actualizar la publicacion"
        ) from error


# Crear una nueva version de una publicacion.
@router.post("/{id_blog}/versiones")
def crear_version(
    id_blog: int,
    datos: VersionRegistro,
    usuario: dict = Depends(verificar_roles("autor")),
    db: Session = Depends(get_db)
):
    try:
        # Bloquear la publicacion para evitar versiones simultaneas.
        publicacion = obtener_publicacion_autor(
            db,
            id_blog,
            usuario["id_usr"],
            bloquear=True
        )

        verificar_estado_editable(publicacion)

        ultima_version = db.execute(
            text("""
                select coalesce(max(numero), 0)
                from versiones_blog
                where blog_id = :id_blog
            """),
            {"id_blog": id_blog}
        ).scalar_one()

        nuevo_numero = ultima_version + 1

        resultado = db.execute(
            text("""
                insert into versiones_blog (
                    blog_id,
                    numero,
                    advertencia
                )
                values (
                    :blog_id,
                    :numero,
                    :advertencia
                )
            """),
            {
                "blog_id": id_blog,
                "numero": nuevo_numero,
                "advertencia": datos.advertencia
            }
        )

        id_version = resultado.lastrowid

        db.commit()

        return {
            "mensaje": "Nueva version creada",
            "id_version": id_version,
            "numero": nuevo_numero
        }

    except IntegrityError as error:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail="La version ya existe"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al crear la version"
        ) from error


# Consultar el historial de versiones.
@router.get("/{id_blog}/versiones")
def consultar_versiones(
    id_blog: int,
    usuario: dict = Depends(
        verificar_roles("autor", "administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        publicacion = db.execute(
            text("""
                select usr_id
                from blog
                where id_blog = :id_blog
            """),
            {"id_blog": id_blog}
        ).mappings().first()

        if publicacion is None:
            raise HTTPException(
                status_code=404,
                detail="Publicacion no encontrada"
            )

        administrador = es_administrador(
            db,
            usuario["id_usr"]
        )

        if (
            publicacion["usr_id"] != usuario["id_usr"]
            and not administrador
        ):
            raise HTTPException(
                status_code=403,
                detail="No puedes consultar versiones ajenas"
            )

        resultado = db.execute(
            text("""
                select
                    id_version,
                    numero,
                    advertencia,
                    fecha
                from versiones_blog
                where blog_id = :id_blog
                order by numero desc
            """),
            {"id_blog": id_blog}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las versiones"
        ) from error


# Enviar una publicacion a revision editorial.
@router.post("/{id_blog}/enviar-revision")
def enviar_revision(
    id_blog: int,
    usuario: dict = Depends(verificar_roles("autor")),
    db: Session = Depends(get_db)
):
    try:
        publicacion = obtener_publicacion_autor(
            db,
            id_blog,
            usuario["id_usr"],
            bloquear=True
        )

        verificar_estado_editable(publicacion)

        version = obtener_ultima_version(
            db,
            id_blog
        )

        # No permitir enviar versiones sin contenido.
        verificar_contenido_version(
            db,
            version["id_version"]
        )

        resultado = db.execute(
            text("""
                update blog
                set estatus = 'revision'
                where id_blog = :id_blog
                and usr_id = :usr_id
                and estatus in (
                    'borrador',
                    'correccion',
                    'rechazado'
                )
            """),
            {
                "id_blog": id_blog,
                "usr_id": usuario["id_usr"]
            }
        )

        if resultado.rowcount != 1:
            db.rollback()

            raise HTTPException(
                status_code=409,
                detail="La publicacion cambio de estado"
            )

        db.commit()

        return {
            "mensaje": "Publicacion enviada a revision",
            "id_blog": id_blog,
            "id_version": version["id_version"],
            "estatus": "revision"
        }

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al enviar la publicacion a revision"
        ) from error


# Revisar una version como administrador.
@router.post("/administracion/versiones/{id_version}/revisar")
def revisar_version(
    id_version: int,
    datos: RevisionPublicacion,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        # Obtener el blog de la version solicitada.
        referencia = db.execute(
            text("""
                select blog_id
                from versiones_blog
                where id_version = :id_version
            """),
            {"id_version": id_version}
        ).mappings().first()

        if referencia is None:
            raise HTTPException(
                status_code=404,
                detail="Version no encontrada"
            )

        # Bloquear primero la publicacion.
        # Todos los cambios editoriales siguen este orden.
        publicacion = db.execute(
            text("""
                select
                    id_blog,
                    estatus,
                    version_publica
                from blog
                where id_blog = :id_blog
                for update
            """),
            {"id_blog": referencia["blog_id"]}
        ).mappings().first()

        if publicacion is None:
            raise HTTPException(
                status_code=404,
                detail="Publicacion no encontrada"
            )

        version = db.execute(
            text("""
                select
                    id_version,
                    blog_id,
                    numero
                from versiones_blog
                where id_version = :id_version
                and blog_id = :blog_id
            """),
            {
                "id_version": id_version,
                "blog_id": publicacion["id_blog"]
            }
        ).mappings().first()

        if version is None:
            raise HTTPException(
                status_code=404,
                detail="Version no encontrada"
            )

        if datos.decision == "oculta":
            if publicacion["estatus"] != "publicado":
                raise HTTPException(
                    status_code=409,
                    detail="Solo se pueden ocultar publicaciones publicadas"
                )

            if version["numero"] != publicacion["version_publica"]:
                raise HTTPException(
                    status_code=409,
                    detail="Solo se puede ocultar la version publicada"
                )

        else:
            if publicacion["estatus"] != "revision":
                raise HTTPException(
                    status_code=409,
                    detail="La publicacion no esta en revision"
                )

            ultima = db.execute(
                text("""
                    select max(numero)
                    from versiones_blog
                    where blog_id = :blog_id
                """),
                {"blog_id": version["blog_id"]}
            ).scalar_one()

            if version["numero"] != ultima:
                raise HTTPException(
                    status_code=409,
                    detail="Solo se puede revisar la ultima version"
                )

            if datos.decision == "aprobada":
                verificar_contenido_version(
                    db,
                    id_version
                )

        # Registrar la decision editorial.
        db.execute(
            text("""
                insert into revisiones_blog (
                    version_id,
                    administrador_id,
                    decision,
                    observacion
                )
                values (
                    :version_id,
                    :administrador_id,
                    :decision,
                    :observacion
                )
            """),
            {
                "version_id": id_version,
                "administrador_id": usuario["id_usr"],
                "decision": datos.decision,
                "observacion": datos.observacion
            }
        )

        estados = {
            "aprobada": "publicado",
            "correccion": "correccion",
            "rechazada": "rechazado",
            "oculta": "oculto"
        }

        nuevo_estado = estados[datos.decision]

        if datos.decision == "aprobada":
            db.execute(
                text("""
                    update blog
                    set
                        estatus = 'publicado',
                        version_publica = :numero,
                        fecha_publicacion = current_timestamp
                    where id_blog = :blog_id
                    and estatus = 'revision'
                """),
                {
                    "numero": version["numero"],
                    "blog_id": version["blog_id"]
                }
            )

        else:
            db.execute(
                text("""
                    update blog
                    set estatus = :estatus
                    where id_blog = :blog_id
                """),
                {
                    "estatus": nuevo_estado,
                    "blog_id": version["blog_id"]
                }
            )

        db.commit()

        return {
            "mensaje": "Revision registrada correctamente",
            "id_version": id_version,
            "id_blog": version["blog_id"],
            "decision": datos.decision,
            "estatus": nuevo_estado
        }

    except IntegrityError as error:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar la revision"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al revisar la version"
        ) from error


# Asociar una etiqueta a una publicacion editable.
@router.post("/{id_blog}/etiquetas")
def asociar_etiqueta(
    id_blog: int,
    datos: EtiquetaRegistro,
    usuario: dict = Depends(verificar_roles("autor")),
    db: Session = Depends(get_db)
):
    try:
        publicacion = obtener_publicacion_autor(
            db,
            id_blog,
            usuario["id_usr"],
            bloquear=True
        )

        verificar_estado_editable(publicacion)

        etiqueta = db.execute(
            text("""
                select id_etiqueta
                from etiquetas
                where id_etiqueta = :etiqueta_id
            """),
            {"etiqueta_id": datos.etiqueta_id}
        ).first()

        if etiqueta is None:
            raise HTTPException(
                status_code=404,
                detail="Etiqueta no encontrada"
            )

        db.execute(
            text("""
                insert ignore into blog_etiquetas (
                    blog_id,
                    etiqueta_id
                )
                values (
                    :blog_id,
                    :etiqueta_id
                )
            """),
            {
                "blog_id": id_blog,
                "etiqueta_id": datos.etiqueta_id
            }
        )

        db.commit()

        return {
            "mensaje": "Etiqueta asociada correctamente"
        }

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al asociar la etiqueta"
        ) from error


# Eliminar una etiqueta asociada a una publicacion.
@router.delete("/{id_blog}/etiquetas/{etiqueta_id}")
def eliminar_etiqueta(
    id_blog: int,
    etiqueta_id: int,
    usuario: dict = Depends(verificar_roles("autor")),
    db: Session = Depends(get_db)
):
    try:
        publicacion = obtener_publicacion_autor(
            db,
            id_blog,
            usuario["id_usr"],
            bloquear=True
        )

        verificar_estado_editable(publicacion)

        resultado = db.execute(
            text("""
                delete from blog_etiquetas
                where blog_id = :blog_id
                and etiqueta_id = :etiqueta_id
            """),
            {
                "blog_id": id_blog,
                "etiqueta_id": etiqueta_id
            }
        )

        if resultado.rowcount == 0:
            db.rollback()

            raise HTTPException(
                status_code=404,
                detail="Etiqueta no asociada a esta publicacion"
            )

        db.commit()

        return {
            "mensaje": "Etiqueta eliminada correctamente"
        }

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Error al eliminar la etiqueta"
        ) from error
