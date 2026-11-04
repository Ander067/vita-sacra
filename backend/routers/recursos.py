from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import obtener_usuario_actual, verificar_roles


router = APIRouter(
    prefix="/recursos",
    tags=["Recursos y contenido"]
)


# Modelos de validacion.

class RecursoRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    tipo: Literal[
        "imagen", "pdf", "video",
        "gif", "sticker", "modelo_3d"
    ]
    url: str = Field(min_length=1, max_length=1000)
    mime: str | None = Field(default=None, max_length=100)
    titulo: str | None = Field(default=None, max_length=180)
    licencia: str | None = Field(default=None, max_length=200)
    procedencia: str | None = Field(default=None, max_length=500)


class RevisionRecurso(BaseModel):
    estatus: Literal["aprobado", "rechazado", "oculto"]


class BloqueRegistro(BaseModel):
    orden: int = Field(ge=0, le=65535)
    tipo: Literal[
        "titulo", "parrafo", "lista", "cita",
        "imagen", "video", "modelo_3d"
    ]
    contenido: str | None = None
    recurso_id: int | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def validar_bloque(self):
        multimedia = {"imagen", "video", "modelo_3d"}

        if self.tipo in multimedia and self.recurso_id is None:
            raise ValueError(
                "Los bloques multimedia requieren un recurso"
            )

        if self.tipo not in multimedia:
            if not self.contenido or not self.contenido.strip():
                raise ValueError(
                    "Los bloques de texto requieren contenido"
                )

            if self.recurso_id is not None:
                raise ValueError(
                    "Un bloque de texto no admite recurso_id"
                )

        return self


class FuenteRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    titulo: str = Field(min_length=1, max_length=255)
    autor: str | None = Field(default=None, max_length=255)
    url: str | None = Field(default=None, max_length=1000)
    anio: int | None = Field(default=None, ge=0, le=65535)


class AsociacionFuente(BaseModel):
    fuente_id: int = Field(gt=0)


class AsociacionRecurso(BaseModel):
    recurso_id: int = Field(gt=0)
    orden: int = Field(default=0, ge=0, le=65535)


# Funciones auxiliares.

def consultar_recurso(db: Session, recurso_id: int):
    recurso = db.execute(
        text("""
            select *
            from recursos
            where id_recurso = :recurso_id
        """),
        {"recurso_id": recurso_id}
    ).mappings().first()

    if recurso is None:
        raise HTTPException(
            status_code=404,
            detail="Recurso no encontrado"
        )

    return dict(recurso)


def es_administrador(db: Session, usuario_id: int):
    # El nombre del rol evita depender de identificadores numericos fijos.
    resultado = db.execute(
        text("""
            select 1
            from usuario u
            inner join roles r on r.id_rol = u.tip_usu
            where u.id_usr = :usuario_id
            and r.nombre = 'administrador'

            union

            select 1
            from usuario_roles ur
            inner join roles r on r.id_rol = ur.rol_id
            where ur.usr_id = :usuario_id
            and r.nombre = 'administrador'
        """),
        {"usuario_id": usuario_id}
    ).first()
    return resultado is not None


def verificar_version(
    db: Session,
    version_id: int,
    usuario_id: int,
    escritura: bool = False
):
    if escritura:
        # Bloquear la publicacion para sincronizarse con publicaciones.py.
        referencia = db.execute(
            text("select blog_id from versiones_blog where id_version = :version_id"),
            {"version_id": version_id}
        ).mappings().first()
        if referencia is None:
            raise HTTPException(status_code=404, detail="Version no encontrada")
        db.execute(
            text("select id_blog from blog where id_blog = :blog_id for update"),
            {"blog_id": referencia["blog_id"]}
        ).first()

    version = db.execute(
        text("""
            select
                v.id_version,
                v.blog_id,
                v.numero,
                b.usr_id,
                b.estatus,
                b.version_publica
            from versiones_blog v
            inner join blog b
                on v.blog_id = b.id_blog
            where v.id_version = :version_id
        """),
        {"version_id": version_id}
    ).mappings().first()

    if version is None:
        raise HTTPException(
            status_code=404,
            detail="Version no encontrada"
        )

    administrador = es_administrador(db, usuario_id)
    propietario = version["usr_id"] == usuario_id

    if not propietario and not administrador:
        raise HTTPException(
            status_code=403,
            detail="No tienes acceso a esta version"
        )

    if escritura:
        if not propietario:
            raise HTTPException(
                status_code=403,
                detail="Solo el autor puede editar esta version"
            )

        if version["estatus"] not in (
            "borrador", "correccion", "rechazado"
        ):
            raise HTTPException(
                status_code=409,
                detail="La publicacion no admite modificaciones"
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
                detail="Solo puede modificarse la ultima version"
            )

        if version["numero"] == version["version_publica"]:
            raise HTTPException(
                status_code=409,
                detail="No se puede modificar una version publicada"
            )

        revision = db.execute(
            text("""
                select 1
                from revisiones_blog
                where version_id = :version_id
                and decision = 'aprobada'
                limit 1
            """),
            {"version_id": version_id}
        ).first()

        if revision is not None:
            raise HTTPException(
                status_code=409,
                detail="Una version aprobada es inmutable"
            )

    return dict(version)


def verificar_recurso_para_version(
    db: Session,
    recurso_id: int,
    usuario_id: int,
    tipo_bloque: str | None = None
):
    recurso = consultar_recurso(db, recurso_id)

    if recurso["usr_id"] != usuario_id:
        raise HTTPException(
            status_code=403,
            detail="No puedes asociar recursos ajenos"
        )

    if recurso["estatus"] != "aprobado":
        raise HTTPException(
            status_code=409,
            detail="El recurso debe estar aprobado"
        )

    if tipo_bloque is not None:
        tipos_validos = {
            "imagen": {"imagen", "gif"},
            "video": {"video"},
            "modelo_3d": {"modelo_3d"}
        }

        if recurso["tipo"] not in tipos_validos[tipo_bloque]:
            raise HTTPException(
                status_code=422,
                detail="Tipo de recurso incompatible con el bloque"
            )

    return recurso


# Consulta publica de recursos aprobados.

@router.get("/publicos/{recurso_id}")
def consultar_recurso_publico(
    recurso_id: int,
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
                where id_recurso = :recurso_id
                and estatus = 'aprobado'
            """),
            {"recurso_id": recurso_id}
        ).mappings().first()

        if resultado is None:
            raise HTTPException(
                status_code=404,
                detail="Recurso no disponible"
            )

        return dict(resultado)

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar el recurso"
        )


# Consulta de recursos propios.

@router.get("/mis-recursos")
def consultar_mis_recursos(
    usuario: dict = Depends(obtener_usuario_actual),
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
                    procedencia,
                    estatus,
                    fecha
                from recursos
                where usr_id = :usr_id
                order by fecha desc
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tus recursos"
        )


# Registro de metadatos de un recurso.

@router.post(
    "/registrar",
    status_code=status.HTTP_201_CREATED
)
def registrar_recurso(
    datos: RecursoRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
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
                    :tipo,
                    :url,
                    :mime,
                    :titulo,
                    :licencia,
                    :procedencia,
                    'pendiente'
                )
            """),
            {
                "usr_id": usuario["id_usr"],
                **datos.model_dump()
            }
        )

        db.commit()

        return {
            "mensaje": "Recurso registrado para revision",
            "id_recurso": resultado.lastrowid,
            "estatus": "pendiente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar el recurso"
        )


# Consulta administrativa de recursos.

@router.get("/administracion/pendientes")
def consultar_recursos_pendientes(
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
                    u.nom_usr as propietario
                from recursos r
                inner join usuario u
                    on r.usr_id = u.id_usr
                where r.estatus = 'pendiente'
                order by r.fecha asc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar recursos pendientes"
        )


# Revision administrativa de recursos.

@router.patch("/administracion/{recurso_id}/revisar")
def revisar_recurso(
    recurso_id: int,
    datos: RevisionRecurso,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        # Bloquear el recurso para evitar revisiones simultaneas.
        recurso = db.execute(
            text("""
                select *
                from recursos
                where id_recurso = :recurso_id
                for update
            """),
            {"recurso_id": recurso_id}
        ).mappings().first()
        if recurso is None:
            raise HTTPException(status_code=404, detail="Recurso no encontrado")
        recurso = dict(recurso)

        transiciones = {
            "pendiente": {"aprobado", "rechazado"},
            "aprobado": {"oculto"},
            "rechazado": set(),
            "oculto": {"aprobado"}
        }

        if datos.estatus not in transiciones[recurso["estatus"]]:
            raise HTTPException(
                status_code=409,
                detail="Cambio de estado no permitido"
            )

        db.execute(
            text("""
                update recursos
                set
                    estatus = :estatus,
                    revisado_por = :administrador_id,
                    fecha_revision = current_timestamp
                where id_recurso = :recurso_id
            """),
            {
                "estatus": datos.estatus,
                "administrador_id": usuario["id_usr"],
                "recurso_id": recurso_id
            }
        )

        db.commit()

        return {
            "mensaje": "Recurso revisado correctamente",
            "id_recurso": recurso_id,
            "estatus": datos.estatus
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al revisar el recurso"
        )


# Registro de bloques en una version.

@router.post(
    "/versiones/{version_id}/bloques",
    status_code=status.HTTP_201_CREATED
)
def registrar_bloque(
    version_id: int,
    datos: BloqueRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"],
            escritura=True
        )

        if datos.recurso_id is not None:
            verificar_recurso_para_version(
                db,
                datos.recurso_id,
                usuario["id_usr"],
                datos.tipo
            )

        resultado = db.execute(
            text("""
                insert into bloques_version (
                    version_id,
                    orden,
                    tipo,
                    contenido,
                    recurso_id
                )
                values (
                    :version_id,
                    :orden,
                    :tipo,
                    :contenido,
                    :recurso_id
                )
            """),
            {
                "version_id": version_id,
                **datos.model_dump()
            }
        )

        db.commit()

        return {
            "mensaje": "Bloque registrado correctamente",
            "id_bloque": resultado.lastrowid,
            "version_id": version_id
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="El orden ya esta ocupado o el recurso no es valido"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar el bloque"
        )


# Consulta privada de bloques de una version.

@router.get("/versiones/{version_id}/bloques")
def consultar_bloques(
    version_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"]
        )

        resultado = db.execute(
            text("""
                select
                    b.id_bloque,
                    b.orden,
                    b.tipo,
                    b.contenido,
                    b.recurso_id,
                    r.url as recurso_url,
                    r.mime as recurso_mime,
                    r.estatus as recurso_estatus
                from bloques_version b
                left join recursos r
                    on b.recurso_id = r.id_recurso
                where b.version_id = :version_id
                order by b.orden
            """),
            {"version_id": version_id}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los bloques"
        )


# Consulta publica de bloques de la version publicada.

@router.get("/publicaciones/{blog_id}/bloques")
def consultar_bloques_publicos(
    blog_id: int,
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    b.id_bloque,
                    b.orden,
                    b.tipo,
                    b.contenido,
                    b.recurso_id,
                    r.url as recurso_url,
                    r.mime as recurso_mime
                from blog_publico bp
                inner join bloques_version b
                    on bp.id_version = b.version_id
                left join recursos r
                    on b.recurso_id = r.id_recurso
                    and r.estatus = 'aprobado'
                where bp.id_blog = :blog_id
                and (
                    b.recurso_id is null
                    or r.id_recurso is not null
                )
                order by b.orden
            """),
            {"blog_id": blog_id}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los bloques publicos"
        )


# Actualizacion de un bloque.

@router.put("/bloques/{bloque_id}")
def actualizar_bloque(
    bloque_id: int,
    datos: BloqueRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        bloque = db.execute(
            text("""
                select version_id
                from bloques_version
                where id_bloque = :bloque_id
            """),
            {"bloque_id": bloque_id}
        ).mappings().first()

        if bloque is None:
            raise HTTPException(
                status_code=404,
                detail="Bloque no encontrado"
            )

        verificar_version(
            db,
            bloque["version_id"],
            usuario["id_usr"],
            escritura=True
        )

        if datos.recurso_id is not None:
            verificar_recurso_para_version(
                db,
                datos.recurso_id,
                usuario["id_usr"],
                datos.tipo
            )

        db.execute(
            text("""
                update bloques_version
                set
                    orden = :orden,
                    tipo = :tipo,
                    contenido = :contenido,
                    recurso_id = :recurso_id
                where id_bloque = :bloque_id
            """),
            {
                "bloque_id": bloque_id,
                **datos.model_dump()
            }
        )

        db.commit()

        return {
            "mensaje": "Bloque actualizado correctamente"
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="El orden ya esta ocupado"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al actualizar el bloque"
        )


# Eliminacion de un bloque editable.

@router.delete("/bloques/{bloque_id}")
def eliminar_bloque(
    bloque_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        bloque = db.execute(
            text("""
                select version_id
                from bloques_version
                where id_bloque = :bloque_id
            """),
            {"bloque_id": bloque_id}
        ).mappings().first()

        if bloque is None:
            raise HTTPException(
                status_code=404,
                detail="Bloque no encontrado"
            )

        verificar_version(
            db,
            bloque["version_id"],
            usuario["id_usr"],
            escritura=True
        )

        db.execute(
            text("""
                delete from bloques_version
                where id_bloque = :bloque_id
            """),
            {"bloque_id": bloque_id}
        )

        db.commit()

        return {
            "mensaje": "Bloque eliminado correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al eliminar el bloque"
        )


# Asociacion de un recurso a una version.

@router.post("/versiones/{version_id}/recursos")
def asociar_recurso(
    version_id: int,
    datos: AsociacionRecurso,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"],
            escritura=True
        )

        verificar_recurso_para_version(
            db,
            datos.recurso_id,
            usuario["id_usr"]
        )

        db.execute(
            text("""
                insert into version_recursos (
                    version_id,
                    recurso_id,
                    orden
                )
                values (
                    :version_id,
                    :recurso_id,
                    :orden
                )
            """),
            {
                "version_id": version_id,
                **datos.model_dump()
            }
        )

        db.commit()

        return {
            "mensaje": "Recurso asociado correctamente"
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="El recurso ya esta asociado"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al asociar el recurso"
        )


# Consulta de recursos asociados a una version.

@router.get("/versiones/{version_id}/recursos")
def consultar_recursos_version(
    version_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"]
        )

        resultado = db.execute(
            text("""
                select
                    vr.recurso_id,
                    vr.orden,
                    r.tipo,
                    r.url,
                    r.mime,
                    r.titulo,
                    r.estatus
                from version_recursos vr
                inner join recursos r
                    on vr.recurso_id = r.id_recurso
                where vr.version_id = :version_id
                order by vr.orden, vr.recurso_id
            """),
            {"version_id": version_id}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar recursos asociados"
        )


# Desasociacion de recursos.

@router.delete(
    "/versiones/{version_id}/recursos/{recurso_id}"
)
def desasociar_recurso(
    version_id: int,
    recurso_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"],
            escritura=True
        )

        resultado = db.execute(
            text("""
                delete from version_recursos
                where version_id = :version_id
                and recurso_id = :recurso_id
            """),
            {
                "version_id": version_id,
                "recurso_id": recurso_id
            }
        )

        if resultado.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="Recurso no asociado a la version"
            )

        db.commit()

        return {
            "mensaje": "Recurso desasociado correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al desasociar el recurso"
        )


# Registro de referencias bibliograficas.
# Solo el administrador puede crear entradas globales.

@router.post(
    "/fuentes",
    status_code=status.HTTP_201_CREATED
)
def registrar_fuente(
    datos: FuenteRegistro,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                insert into fuentes (
                    titulo,
                    autor,
                    url,
                    anio
                )
                values (
                    :titulo,
                    :autor,
                    :url,
                    :anio
                )
            """),
            datos.model_dump()
        )

        db.commit()

        return {
            "mensaje": "Fuente registrada correctamente",
            "id_fuente": resultado.lastrowid
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar la fuente"
        )


# Consulta del catalogo de fuentes.

@router.get("/fuentes")
def consultar_fuentes(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_fuente,
                    titulo,
                    autor,
                    url,
                    anio
                from fuentes
                order by titulo
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las fuentes"
        )


# Asociacion de una fuente bibliografica.

@router.post("/versiones/{version_id}/fuentes")
def asociar_fuente(
    version_id: int,
    datos: AsociacionFuente,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"],
            escritura=True
        )

        fuente = db.execute(
            text("""
                select id_fuente
                from fuentes
                where id_fuente = :fuente_id
            """),
            {"fuente_id": datos.fuente_id}
        ).first()

        if fuente is None:
            raise HTTPException(
                status_code=404,
                detail="Fuente no encontrada"
            )

        db.execute(
            text("""
                insert into version_fuentes (
                    version_id,
                    fuente_id
                )
                values (
                    :version_id,
                    :fuente_id
                )
            """),
            {
                "version_id": version_id,
                "fuente_id": datos.fuente_id
            }
        )

        db.commit()

        return {
            "mensaje": "Fuente asociada correctamente"
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="La fuente ya esta asociada"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al asociar la fuente"
        )


# Consulta de referencias de una version.

@router.get("/versiones/{version_id}/fuentes")
def consultar_fuentes_version(
    version_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"]
        )

        resultado = db.execute(
            text("""
                select
                    f.id_fuente,
                    f.titulo,
                    f.autor,
                    f.url,
                    f.anio
                from version_fuentes vf
                inner join fuentes f
                    on vf.fuente_id = f.id_fuente
                where vf.version_id = :version_id
                order by f.titulo
            """),
            {"version_id": version_id}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las fuentes de la version"
        )


# Consulta publica de referencias de una publicacion.

@router.get("/publicaciones/{blog_id}/fuentes")
def consultar_fuentes_publicas(
    blog_id: int,
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    f.id_fuente,
                    f.titulo,
                    f.autor,
                    f.url,
                    f.anio
                from blog_publico bp
                inner join version_fuentes vf
                    on bp.id_version = vf.version_id
                inner join fuentes f
                    on vf.fuente_id = f.id_fuente
                where bp.id_blog = :blog_id
                order by f.titulo
            """),
            {"blog_id": blog_id}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las fuentes publicas"
        )


# Eliminacion de una asociacion bibliografica.

@router.delete(
    "/versiones/{version_id}/fuentes/{fuente_id}"
)
def desasociar_fuente(
    version_id: int,
    fuente_id: int,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        verificar_version(
            db,
            version_id,
            usuario["id_usr"],
            escritura=True
        )

        resultado = db.execute(
            text("""
                delete from version_fuentes
                where version_id = :version_id
                and fuente_id = :fuente_id
            """),
            {
                "version_id": version_id,
                "fuente_id": fuente_id
            }
        )

        if resultado.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="Fuente no asociada a la version"
            )

        db.commit()

        return {
            "mensaje": "Fuente desasociada correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al desasociar la fuente"
        )
