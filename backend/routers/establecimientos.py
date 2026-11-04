from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, ConfigDict, field_validator
from sqlalchemy import text
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError, IntegrityError

from database import get_db
from security.auth import obtener_usuario_actual, verificar_roles

router = APIRouter(
    prefix="/establecimientos",
    tags=["Establecimientos"]
)


# Modelo para registrar un establecimiento.
class EstablecimientoRegistro(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    nombre: str = Field(min_length=3, max_length=180)
    tipo: str = Field(min_length=3, max_length=80)
    descripcion: str | None = None
    direccion: str = Field(min_length=5, max_length=300)
    latitud: Decimal | None = Field(
        default=None,
        ge=Decimal("-90"),
        le=Decimal("90"),
        max_digits=10,
        decimal_places=7
    )
    longitud: Decimal | None = Field(
        default=None,
        ge=Decimal("-180"),
        le=Decimal("180"),
        max_digits=10,
        decimal_places=7
    )
    telefono: str | None = Field(default=None, max_length=30)
    sitio_web: str | None = Field(default=None, max_length=500)

    @field_validator("latitud", "longitud")
    @classmethod
    def validar_coordenadas(cls, valor):
        if valor is not None and not valor.is_finite():
            raise ValueError("La coordenada debe ser finita")
        return valor


# Modelo para actualizar los datos de un establecimiento.
class EstablecimientoActualizacion(EstablecimientoRegistro):
    pass


# Modelo para revisar una solicitud.
class RevisionEstablecimiento(BaseModel):
    estatus: str
    observacion: str | None = None

    @field_validator("estatus")
    @classmethod
    def validar_estatus(cls, valor):
        if valor not in ("aprobado", "rechazado", "oculto"):
            raise ValueError("Estado de revision no permitido")
        return valor


# Endpoint para consultar establecimientos aprobados.
@router.get("/")
def consultar_establecimientos(
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_establecimiento,
                    nombre,
                    tipo,
                    descripcion,
                    direccion,
                    latitud,
                    longitud,
                    telefono,
                    sitio_web
                from establecimientos_publicos
                order by nombre
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los establecimientos"
        )


# Endpoint para consultar solicitudes propias.
@router.get("/mis-solicitudes")
def consultar_mis_solicitudes(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    id_establecimiento,
                    nombre,
                    tipo,
                    descripcion,
                    direccion,
                    estatus,
                    fecha_revision
                from establecimientos
                where solicitante_id = :usr_id
                order by id_establecimiento desc
            """),
            {"usr_id": usuario["id_usr"]}
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar tus solicitudes"
        )


# Endpoint para consultar solicitudes administrativas.
@router.get("/administracion/solicitudes")
def consultar_solicitudes(
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select
                    e.*,
                    u.nom_usr as solicitante
                from establecimientos e
                inner join usuario u
                    on e.solicitante_id = u.id_usr
                order by e.id_establecimiento desc
            """)
        ).mappings().all()

        return [dict(fila) for fila in resultado]

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar las solicitudes"
        )


# Endpoint para consultar un establecimiento publico.
@router.get("/{id_establecimiento}")
def consultar_establecimiento(
    id_establecimiento: int,
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                select *
                from establecimientos_publicos
                where id_establecimiento = :id_establecimiento
            """),
            {"id_establecimiento": id_establecimiento}
        ).mappings().first()

        if resultado is None:
            raise HTTPException(
                status_code=404,
                detail="Establecimiento no encontrado"
            )

        return dict(resultado)

    except SQLAlchemyError:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar el establecimiento"
        )


# Endpoint para solicitar el registro de un establecimiento.
@router.post(
    "/registrar",
    status_code=status.HTTP_201_CREATED
)
def registrar_establecimiento(
    datos: EstablecimientoRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        resultado = db.execute(
            text("""
                insert into establecimientos (
                    solicitante_id,
                    nombre,
                    tipo,
                    descripcion,
                    direccion,
                    latitud,
                    longitud,
                    telefono,
                    sitio_web,
                    estatus
                )
                values (
                    :solicitante_id,
                    :nombre,
                    :tipo,
                    :descripcion,
                    :direccion,
                    :latitud,
                    :longitud,
                    :telefono,
                    :sitio_web,
                    'pendiente'
                )
            """),
            {
                "solicitante_id": usuario["id_usr"],
                "nombre": datos.nombre,
                "tipo": datos.tipo,
                "descripcion": datos.descripcion,
                "direccion": datos.direccion,
                "latitud": datos.latitud,
                "longitud": datos.longitud,
                "telefono": datos.telefono,
                "sitio_web": datos.sitio_web
            }
        )

        db.commit()

        return {
            "mensaje": "Solicitud registrada correctamente",
            "id_establecimiento": resultado.lastrowid,
            "estatus": "pendiente"
        }

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="No fue posible registrar el establecimiento"
        )

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al registrar el establecimiento"
        )


# Endpoint para actualizar una solicitud pendiente.
@router.put("/{id_establecimiento}")
def actualizar_establecimiento(
    id_establecimiento: int,
    datos: EstablecimientoActualizacion,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        establecimiento = db.execute(
            text("""
                select solicitante_id, estatus
                from establecimientos
                where id_establecimiento = :id_establecimiento
            """),
            {"id_establecimiento": id_establecimiento}
        ).mappings().first()

        if establecimiento is None:
            raise HTTPException(
                status_code=404,
                detail="Establecimiento no encontrado"
            )

        if establecimiento["solicitante_id"] != usuario["id_usr"]:
            raise HTTPException(
                status_code=403,
                detail="No puedes modificar solicitudes ajenas"
            )

        if establecimiento["estatus"] != "pendiente":
            raise HTTPException(
                status_code=409,
                detail="Solo se pueden modificar solicitudes pendientes"
            )

        db.execute(
            text("""
                update establecimientos
                set
                    nombre = :nombre,
                    tipo = :tipo,
                    descripcion = :descripcion,
                    direccion = :direccion,
                    latitud = :latitud,
                    longitud = :longitud,
                    telefono = :telefono,
                    sitio_web = :sitio_web
                where id_establecimiento = :id_establecimiento
            """),
            {
                "nombre": datos.nombre,
                "tipo": datos.tipo,
                "descripcion": datos.descripcion,
                "direccion": datos.direccion,
                "latitud": datos.latitud,
                "longitud": datos.longitud,
                "telefono": datos.telefono,
                "sitio_web": datos.sitio_web,
                "id_establecimiento": id_establecimiento
            }
        )

        db.commit()

        return {
            "mensaje": "Solicitud actualizada correctamente"
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al actualizar el establecimiento"
        )


# Endpoint para aprobar, rechazar u ocultar establecimientos.
@router.patch("/{id_establecimiento}/revisar")
def revisar_establecimiento(
    id_establecimiento: int,
    datos: RevisionEstablecimiento,
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        establecimiento = db.execute(
            text("""
                select id_establecimiento, estatus
                from establecimientos
                where id_establecimiento = :id_establecimiento
            """),
            {"id_establecimiento": id_establecimiento}
        ).mappings().first()

        if establecimiento is None:
            raise HTTPException(
                status_code=404,
                detail="Establecimiento no encontrado"
            )

        estado_actual = establecimiento["estatus"]

        transiciones = {
            "pendiente": {"aprobado", "rechazado"},
            "aprobado": {"oculto"},
            "rechazado": set(),
            "oculto": {"aprobado"}
        }

        if datos.estatus not in transiciones.get(estado_actual, set()):
            raise HTTPException(
                status_code=409,
                detail="Cambio de estado no permitido"
            )

        db.execute(
            text("""
                update establecimientos
                set
                    estatus = :estatus,
                    administrador_id = :administrador_id,
                    fecha_revision = current_timestamp
                where id_establecimiento = :id_establecimiento
            """),
            {
                "estatus": datos.estatus,
                "administrador_id": usuario["id_usr"],
                "id_establecimiento": id_establecimiento
            }
        )

        db.commit()

        return {
            "mensaje": "Establecimiento revisado correctamente",
            "id_establecimiento": id_establecimiento,
            "estatus": datos.estatus
        }

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Error al revisar el establecimiento"
        )
