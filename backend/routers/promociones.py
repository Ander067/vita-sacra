from datetime import datetime, timedelta
from typing import Literal
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import verificar_roles


router = APIRouter(
    prefix="/promociones",
    tags=["Promociones"]
)


# Modelo para registrar una promocion.
class PromocionRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    establecimiento_id: int | None = Field(default=None, gt=0)
    espacio_id: int = Field(gt=0)
    recurso_id: int | None = Field(default=None, gt=0)
    titulo: str = Field(min_length=3, max_length=150)
    url_destino: str | None = Field(default=None, max_length=1000)

    @field_validator("url_destino")
    @classmethod
    def validar_url(cls, valor: str | None):
        if valor is None or valor == "":
            return None

        url = urlparse(valor)

        if (
            url.scheme not in ("http", "https")
            or not url.netloc
            or url.username is not None
            or url.password is not None
            or any(caracter.isspace() for caracter in valor)
        ):
            raise ValueError("La URL de destino no es valida")

        return valor


# Modelo para actualizar una promocion pendiente.
class PromocionActualizacion(PromocionRegistro):
    pass


# Modelo para revisar una promocion.
class RevisionPromocion(BaseModel):
    estatus: Literal["aprobada", "rechazada"]


# Consultar un espacio promocional activo.
def verificar_espacio(db: Session, espacio_id: int) -> dict:
    espacio = db.execute(
        text("""
            select
                id_espacio,
                nombre,
                precio,
                dias,
                activo
            from espacios_promocionales
            where id_espacio = :espacio_id
            and activo = 1
        """),
        {"espacio_id": espacio_id}
    ).mappings().first()

    if espacio is None:
        raise HTTPException(
            status_code=404,
            detail="Espacio promocional no disponible"
        )

    return dict(espacio)


# Verificar que el establecimiento pertenezca al anunciante.
def verificar_establecimiento(
    db: Session,
    establecimiento_id: int | None,
    usuario_id: int
) -> None:
    if establecimiento_id is None:
        return

    establecimiento = db.execute(
        text("""
            select
                id_establecimiento,
                solicitante_id,
                estatus
            from establecimientos
            where id_establecimiento = :id_establecimiento
        """),
        {"id_establecimiento": establecimiento_id}
    ).mappings().first()

    if establecimiento is None:
        raise HTTPException(
            status_code=404,
            detail="Establecimiento no encontrado"
        )

    if establecimiento["solicitante_id"] != usuario_id:
        raise HTTPException(
            status_code=403,
            detail="No puedes promocionar un establecimiento ajeno"
        )

    if establecimiento["estatus"] != "aprobado":
        raise HTTPException(
            status_code=409,
            detail="El establecimiento no esta aprobado"
        )


# Verificar la propiedad y aprobacion del recurso.
def verificar_recurso(
    db: Session,
    recurso_id: int | None,
    usuario_id: int
) -> None:
    if recurso_id is None:
        return

    recurso = db.execute(
        text("""
            select
                id_recurso,
                usr_id,
                tipo,
                estatus
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

    if recurso["usr_id"] != usuario_id:
        raise HTTPException(
            status_code=403,
            detail="No puedes utilizar recursos ajenos"
        )

    if recurso["estatus"] != "aprobado":
        raise HTTPException(
            status_code=409,
            detail="El recurso publicitario no esta aprobado"
        )

    if recurso["tipo"] not in ("imagen", "gif", "video"):
        raise HTTPException(
            status_code=422,
            detail="Tipo de recurso no permitido para publicidad"
        )


# Consultar una promocion del anunciante.
def obtener_promocion(
    db: Session,
    id_promocion: int,
    usuario_id: int,
    bloquear: bool = False
) -> dict:
    consulta = """
        select
            id_promocion,
            anunciante_id,
            establecimiento_id,
            espacio_id,
            recurso_id,
            titulo,
            url_destino,
            estatus,
            administrador_id,
            fecha_inicio,
            fecha_fin
        from promociones
        where id_promocion = :id_promocion
        and anunciante_id = :usuario_id
    """

    if bloquear:
        consulta += " for update"

    promocion = db.execute(
        text(consulta),
        {
            "id_promocion": id_promocion,
            "usuario_id": usuario_id
        }
    ).mappings().first()

    if promocion is None:
        raise HTTPException(
            status_code=404,
            detail="Promocion no encontrada para este anunciante"
        )

    return dict(promocion)


# Validar las relaciones de una promocion.
def validar_relaciones(
    db: Session,
    datos: PromocionRegistro,
    usuario_id: int
) -> dict:
    espacio = verificar_espacio(
        db,
        datos.espacio_id
    )

    verificar_establecimiento(
        db,
        datos.establecimiento_id,
        usuario_id
    )

    verificar_recurso(
        db,
        datos.recurso_id,
        usuario_id
    )

    return espacio


# Consultar los espacios promocionales disponibles.
@router.get("/espacios")
def consultar_espacios(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_espacio,
                    nombre,
                    precio,
                    dias
                from espacios_promocionales
                where activo = 1
                order by precio asc, id_espacio asc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los espacios promocionales"
        ) from error


# Consultar las promociones publicas activas.
@router.get("/activas")
def consultar_promociones_activas(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    p.id_promocion,
                    p.titulo,
                    p.url_destino,
                    p.fecha_inicio,
                    p.fecha_fin,
                    e.nombre as establecimiento,
                    r.url as recurso_url,
                    r.tipo as recurso_tipo,
                    ep.nombre as espacio
                from promociones p
                inner join espacios_promocionales ep
                    on p.espacio_id = ep.id_espacio
                left join establecimientos e
                    on p.establecimiento_id = e.id_establecimiento
                left join recursos r
                    on p.recurso_id = r.id_recurso
                where p.estatus = 'activa'
                and p.fecha_inicio <= current_timestamp
                and p.fecha_fin > current_timestamp
                and ep.activo = 1
                and (
                    p.establecimiento_id is null
                    or e.estatus = 'aprobado'
                )
                and (
                    p.recurso_id is null
                    or (
                        r.estatus = 'aprobado'
                        and r.tipo in ('imagen', 'gif', 'video')
                    )
                )
                and exists (
                    select 1
                    from pagos pg
                    where pg.promocion_id = p.id_promocion
                    and pg.tipo = 'promocion'
                    and pg.estatus = 'completado'
                    and pg.fecha_confirmacion is not null
                )
                order by p.fecha_inicio desc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las promociones activas"
        ) from error


# Consultar las promociones propias del anunciante.
@router.get("/mis-promociones")
def consultar_mis_promociones(
    usuario: dict = Depends(verificar_roles("anunciante")),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    p.*,
                    ep.nombre as espacio,
                    ep.precio,
                    ep.dias
                from promociones p
                inner join espacios_promocionales ep
                    on p.espacio_id = ep.id_espacio
                where p.anunciante_id = :usuario_id
                order by p.id_promocion desc
            """),
            {"usuario_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tus promociones"
        ) from error


# Consultar las solicitudes administrativas.
@router.get("/administracion/solicitudes")
def consultar_solicitudes(
    usuario: dict = Depends(verificar_roles("administrador")),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    p.*,
                    u.nom_usr as anunciante,
                    ep.nombre as espacio,
                    ep.precio,
                    ep.dias
                from promociones p
                inner join usuario u
                    on p.anunciante_id = u.id_usr
                inner join espacios_promocionales ep
                    on p.espacio_id = ep.id_espacio
                order by p.id_promocion desc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las solicitudes"
        ) from error


# Registrar una solicitud de promocion.
@router.post(
    "/registrar",
    status_code=status.HTTP_201_CREATED
)
def registrar_promocion(
    datos: PromocionRegistro,
    usuario: dict = Depends(verificar_roles("anunciante")),
    db: Session = Depends(get_db)
):
    try:
        validar_relaciones(
            db,
            datos,
            usuario["id_usr"]
        )

        resultado = db.execute(
            text("""
                insert into promociones (
                    anunciante_id,
                    establecimiento_id,
                    espacio_id,
                    recurso_id,
                    titulo,
                    url_destino,
                    estatus
                )
                values (
                    :anunciante_id,
                    :establecimiento_id,
                    :espacio_id,
                    :recurso_id,
                    :titulo,
                    :url_destino,
                    'pendiente'
                )
            """),
            {
                "anunciante_id": usuario["id_usr"],
                "establecimiento_id": datos.establecimiento_id,
                "espacio_id": datos.espacio_id,
                "recurso_id": datos.recurso_id,
                "titulo": datos.titulo,
                "url_destino": datos.url_destino
            }
        )

        id_promocion = resultado.lastrowid
        db.commit()

        return {
            "mensaje": "Promocion registrada correctamente",
            "id_promocion": id_promocion,
            "estatus": "pendiente"
        }

    except IntegrityError as error:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar las relaciones de la promocion"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar la promocion"
        ) from error


# Actualizar una promocion pendiente.
@router.put("/{id_promocion}")
def actualizar_promocion(
    id_promocion: int,
    datos: PromocionActualizacion,
    usuario: dict = Depends(verificar_roles("anunciante")),
    db: Session = Depends(get_db)
):
    try:
        promocion = obtener_promocion(
            db,
            id_promocion,
            usuario["id_usr"],
            bloquear=True
        )

        if promocion["estatus"] != "pendiente":
            raise HTTPException(
                status_code=409,
                detail="Solo puedes modificar promociones pendientes"
            )

        validar_relaciones(
            db,
            datos,
            usuario["id_usr"]
        )

        resultado = db.execute(
            text("""
                update promociones
                set
                    establecimiento_id = :establecimiento_id,
                    espacio_id = :espacio_id,
                    recurso_id = :recurso_id,
                    titulo = :titulo,
                    url_destino = :url_destino
                where id_promocion = :id_promocion
                and anunciante_id = :anunciante_id
                and estatus = 'pendiente'
            """),
            {
                "establecimiento_id": datos.establecimiento_id,
                "espacio_id": datos.espacio_id,
                "recurso_id": datos.recurso_id,
                "titulo": datos.titulo,
                "url_destino": datos.url_destino,
                "id_promocion": id_promocion,
                "anunciante_id": usuario["id_usr"]
            }
        )

        if resultado.rowcount != 1:
            db.rollback()
            raise HTTPException(
                status_code=409,
                detail="La promocion cambio de estado"
            )

        db.commit()

        return {
            "mensaje": "Promocion actualizada correctamente",
            "id_promocion": id_promocion
        }

    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al actualizar la promocion"
        ) from error


# Aprobar o rechazar una promocion.
@router.patch("/{id_promocion}/revisar")
def revisar_promocion(
    id_promocion: int,
    datos: RevisionPromocion,
    usuario: dict = Depends(verificar_roles("administrador")),
    db: Session = Depends(get_db)
):
    try:
        promocion = db.execute(
            text("""
                select
                    p.id_promocion,
                    p.estatus,
                    p.anunciante_id,
                    p.establecimiento_id,
                    p.espacio_id,
                    p.recurso_id
                from promociones p
                where p.id_promocion = :id_promocion
                for update
            """),
            {"id_promocion": id_promocion}
        ).mappings().first()

        if promocion is None:
            raise HTTPException(
                status_code=404,
                detail="Promocion no encontrada"
            )

        if promocion["estatus"] != "pendiente":
            raise HTTPException(
                status_code=409,
                detail="La promocion ya fue revisada"
            )

        # Validar las relaciones antes de aprobar.
        if datos.estatus == "aprobada":
            verificar_espacio(
                db,
                promocion["espacio_id"]
            )

            verificar_establecimiento(
                db,
                promocion["establecimiento_id"],
                promocion["anunciante_id"]
            )

            verificar_recurso(
                db,
                promocion["recurso_id"],
                promocion["anunciante_id"]
            )

        resultado = db.execute(
            text("""
                update promociones
                set
                    estatus = :estatus,
                    administrador_id = :administrador_id
                where id_promocion = :id_promocion
                and estatus = 'pendiente'
            """),
            {
                "estatus": datos.estatus,
                "administrador_id": usuario["id_usr"],
                "id_promocion": id_promocion
            }
        )

        if resultado.rowcount != 1:
            db.rollback()
            raise HTTPException(
                status_code=409,
                detail="La promocion cambio de estado"
            )

        db.commit()

        return {
            "mensaje": "Promocion revisada correctamente",
            "id_promocion": id_promocion,
            "estatus": datos.estatus
        }

    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al revisar la promocion"
        ) from error


# Consultar la cotizacion de una promocion.
@router.get("/{id_promocion}/cotizacion")
def consultar_cotizacion(
    id_promocion: int,
    usuario: dict = Depends(verificar_roles("anunciante")),
    db: Session = Depends(get_db)
):
    try:
        promocion = obtener_promocion(
            db,
            id_promocion,
            usuario["id_usr"]
        )

        espacio = verificar_espacio(
            db,
            promocion["espacio_id"]
        )

        pago = db.execute(
            text("""
                select
                    id_pago,
                    estatus,
                    monto,
                    moneda
                from pagos
                where promocion_id = :id_promocion
                and tipo = 'promocion'
                order by id_pago desc
                limit 1
            """),
            {"id_promocion": id_promocion}
        ).mappings().first()

        return {
            "id_promocion": id_promocion,
            "estatus": promocion["estatus"],
            "espacio": espacio["nombre"],
            "monto": str(espacio["precio"]),
            "moneda": "MXN",
            "dias": espacio["dias"],
            "pago_habilitado": (
                promocion["estatus"] == "aprobada"
                and (
                    pago is None
                    or pago["estatus"] in (
                        "cancelado",
                        "fallido"
                    )
                )
            ),
            "pago_registrado": (
                dict(pago)
                if pago is not None
                else None
            )
        }

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar la cotizacion"
        ) from error


# Activar una promocion con pago confirmado.
@router.post("/{id_promocion}/activar")
def activar_promocion(
    id_promocion: int,
    usuario: dict = Depends(verificar_roles("administrador")),
    db: Session = Depends(get_db)
):
    try:
        promocion = db.execute(
            text("""
                select
                    p.id_promocion,
                    p.anunciante_id,
                    p.estatus,
                    p.espacio_id,
                    p.establecimiento_id,
                    p.recurso_id,
                    ep.precio,
                    ep.dias,
                    ep.activo
                from promociones p
                inner join espacios_promocionales ep
                    on p.espacio_id = ep.id_espacio
                where p.id_promocion = :id_promocion
                for update
            """),
            {"id_promocion": id_promocion}
        ).mappings().first()

        if promocion is None:
            raise HTTPException(
                status_code=404,
                detail="Promocion no encontrada"
            )

        if promocion["estatus"] != "aprobada":
            raise HTTPException(
                status_code=409,
                detail="La promocion no esta aprobada"
            )

        if not promocion["activo"]:
            raise HTTPException(
                status_code=409,
                detail="El espacio promocional no esta disponible"
            )

        verificar_establecimiento(
            db,
            promocion["establecimiento_id"],
            promocion["anunciante_id"]
        )

        verificar_recurso(
            db,
            promocion["recurso_id"],
            promocion["anunciante_id"]
        )

        # Comprobar un pago confirmado y asociado al anunciante.
        pago = db.execute(
            text("""
                select
                    id_pago,
                    monto,
                    moneda,
                    entorno,
                    paypal_capture_id
                from pagos
                where promocion_id = :id_promocion
                and usr_id = :anunciante_id
                and tipo = 'promocion'
                and estatus = 'completado'
                and fecha_confirmacion is not null
                and paypal_capture_id is not null
                and monto = :precio
                and moneda = 'MXN'
                order by id_pago desc
                limit 1
            """),
            {
                "id_promocion": id_promocion,
                "anunciante_id": promocion["anunciante_id"],
                "precio": promocion["precio"]
            }
        ).mappings().first()

        if pago is None:
            raise HTTPException(
                status_code=409,
                detail="La promocion no tiene un pago confirmado valido"
            )

        # Las fechas se calculan al activar la campaña.
        fecha_inicio = datetime.now()
        fecha_fin = fecha_inicio + timedelta(
            days=promocion["dias"]
        )

        resultado = db.execute(
            text("""
                update promociones
                set
                    estatus = 'activa',
                    fecha_inicio = :fecha_inicio,
                    fecha_fin = :fecha_fin
                where id_promocion = :id_promocion
                and estatus = 'aprobada'
            """),
            {
                "fecha_inicio": fecha_inicio,
                "fecha_fin": fecha_fin,
                "id_promocion": id_promocion
            }
        )

        if resultado.rowcount != 1:
            db.rollback()
            raise HTTPException(
                status_code=409,
                detail="La promocion cambio de estado"
            )

        db.commit()

        return {
            "mensaje": "Promocion activada correctamente",
            "id_promocion": id_promocion,
            "estatus": "activa",
            "id_pago": pago["id_pago"],
            "fecha_inicio": fecha_inicio,
            "fecha_fin": fecha_fin
        }

    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al activar la promocion"
        ) from error


# Finalizar una promocion cuando haya vencido.
@router.post("/{id_promocion}/finalizar")
def finalizar_promocion(
    id_promocion: int,
    usuario: dict = Depends(verificar_roles("administrador")),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                update promociones
                set estatus = 'finalizada'
                where id_promocion = :id_promocion
                and estatus = 'activa'
                and fecha_fin <= current_timestamp
            """),
            {"id_promocion": id_promocion}
        )

        if resultado.rowcount != 1:
            db.rollback()

            raise HTTPException(
                status_code=409,
                detail="La promocion no esta activa o aun no vence"
            )

        db.commit()

        return {
            "mensaje": "Promocion finalizada correctamente",
            "id_promocion": id_promocion,
            "estatus": "finalizada"
        }

    except SQLAlchemyError as error:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al finalizar la promocion"
        ) from error
