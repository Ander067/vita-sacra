import os
import uuid
from decimal import Decimal, InvalidOperation
from typing import Any

import httpx
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from database import get_db
from security.auth import obtener_usuario_actual, verificar_roles


load_dotenv()

router = APIRouter(
    prefix="/pagos",
    tags=["Pagos"]
)


PAYPAL_MODE = os.getenv("PAYPAL_MODE", "sandbox").strip().lower()
PAYPAL_CLIENT_ID = os.getenv("PAYPAL_CLIENT_ID", "").strip()
PAYPAL_CLIENT_SECRET = os.getenv("PAYPAL_CLIENT_SECRET", "").strip()
PAYPAL_CURRENCY = "MXN"

PAYPAL_BASE_URL = (
    "https://api-m.paypal.com"
    if PAYPAL_MODE == "live"
    else "https://api-m.sandbox.paypal.com"
)

ENTORNO_BD = (
    "produccion"
    if PAYPAL_MODE == "live"
    else "sandbox"
)


# Modelo para registrar una aportacion voluntaria.
class AportacionRegistro(BaseModel):
    monto: Decimal = Field(
        ge=Decimal("10.00"),
        le=Decimal("10000.00"),
        max_digits=10,
        decimal_places=2
    )


# Verificar la configuracion de PayPal.
def verificar_configuracion() -> None:
    if PAYPAL_MODE not in ("sandbox", "live"):
        raise HTTPException(
            status_code=503,
            detail="Modo de PayPal no válido"
        )

    if not PAYPAL_CLIENT_ID or not PAYPAL_CLIENT_SECRET:
        raise HTTPException(
            status_code=503,
            detail="Credenciales de PayPal no configuradas"
        )

    if os.getenv("PAYPAL_CURRENCY", "MXN").upper() != "MXN":
        raise HTTPException(
            status_code=503,
            detail="Esta integración requiere moneda MXN"
        )


# Obtener un token OAuth de PayPal.
async def obtener_token_paypal() -> str:
    verificar_configuracion()

    try:
        async with httpx.AsyncClient(timeout=20.0) as cliente:
            respuesta = await cliente.post(
                f"{PAYPAL_BASE_URL}/v1/oauth2/token",
                auth=(
                    PAYPAL_CLIENT_ID,
                    PAYPAL_CLIENT_SECRET
                ),
                data={
                    "grant_type": "client_credentials"
                },
                headers={
                    "Accept": "application/json"
                }
            )

            respuesta.raise_for_status()

            token = respuesta.json().get("access_token")

            if not isinstance(token, str) or not token:
                raise HTTPException(
                    status_code=502,
                    detail="PayPal no devolvió un token válido"
                )

            return token

    except (httpx.HTTPError, ValueError) as error:
        raise HTTPException(
            status_code=502,
            detail="No fue posible autenticar con PayPal"
        ) from error


# Realizar solicitudes HTTP a PayPal.
async def solicitar_paypal(
    metodo: str,
    ruta: str,
    datos: dict | None = None,
    solicitud_id: str | None = None
) -> dict:
    token = await obtener_token_paypal()

    encabezados = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }

    if solicitud_id:
        encabezados["PayPal-Request-Id"] = solicitud_id

    try:
        async with httpx.AsyncClient(timeout=30.0) as cliente:
            respuesta = await cliente.request(
                metodo,
                f"{PAYPAL_BASE_URL}{ruta}",
                headers=encabezados,
                json=datos
            )

            respuesta.raise_for_status()

            resultado = respuesta.json()

            if not isinstance(resultado, dict):
                raise HTTPException(
                    status_code=502,
                    detail="Respuesta inesperada de PayPal"
                )

            return resultado

    except httpx.HTTPStatusError as error:
        codigo = error.response.status_code

        if codigo == 404:
            raise HTTPException(
                status_code=404,
                detail="Orden no encontrada en PayPal"
            ) from error

        raise HTTPException(
            status_code=502,
            detail=f"PayPal rechazó la operación (HTTP {codigo})"
        ) from error

    except (httpx.RequestError, ValueError) as error:
        raise HTTPException(
            status_code=502,
            detail="Error de comunicación con PayPal"
        ) from error


# Consultar un pago registrado en MariaDB.
def obtener_pago(
    db: Session,
    id_orden: str,
    usr_id: int
) -> dict:
    try:
        fila = db.execute(
            text("""
                select
                    id_pago,
                    usr_id,
                    promocion_id,
                    tipo,
                    paypal_order_id,
                    paypal_capture_id,
                    monto,
                    moneda,
                    entorno,
                    estatus,
                    fecha,
                    fecha_confirmacion
                from pagos
                where paypal_order_id = :id_orden
                and usr_id = :usr_id
            """),
            {
                "id_orden": id_orden,
                "usr_id": usr_id
            }
        ).mappings().first()

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar el pago"
        ) from error

    if fila is None:
        raise HTTPException(
            status_code=404,
            detail="Pago no encontrado para este usuario"
        )

    return dict(fila)


# Comprobar el entorno de la orden.
def validar_entorno(pago: dict) -> None:
    if pago["entorno"] != ENTORNO_BD:
        raise HTTPException(
            status_code=409,
            detail="La orden pertenece a otro entorno"
        )


# Validar el importe y la moneda.
def validar_importe(
    importe: Any,
    pago: dict
) -> None:
    if not isinstance(importe, dict):
        raise HTTPException(
            status_code=502,
            detail="PayPal devolvió un importe inválido"
        )

    try:
        monto = Decimal(str(importe["value"]))
        moneda = importe["currency_code"]

    except (
        KeyError,
        InvalidOperation,
        TypeError,
        ValueError
    ) as error:
        raise HTTPException(
            status_code=502,
            detail="PayPal devolvió un importe inválido"
        ) from error

    if (
        not monto.is_finite()
        or monto != Decimal(str(pago["monto"]))
    ):
        raise HTTPException(
            status_code=409,
            detail="El importe de PayPal no coincide"
        )

    if moneda != pago["moneda"]:
        raise HTTPException(
            status_code=409,
            detail="La moneda de PayPal no coincide"
        )


# Validar que la orden corresponda al pago local.
def validar_orden(
    orden: dict,
    pago: dict
) -> dict:
    if orden.get("id") != pago["paypal_order_id"]:
        raise HTTPException(
            status_code=409,
            detail="El identificador de la orden no coincide"
        )

    if orden.get("intent") != "CAPTURE":
        raise HTTPException(
            status_code=409,
            detail="La orden no admite captura directa"
        )

    unidades = orden.get("purchase_units")

    if not isinstance(unidades, list) or len(unidades) != 1:
        raise HTTPException(
            status_code=502,
            detail="La orden contiene unidades inesperadas"
        )

    unidad = unidades[0]

    if not isinstance(unidad, dict):
        raise HTTPException(
            status_code=502,
            detail="Unidad de compra inválida"
        )

    referencia = (
        f"vitasacra:{pago['tipo']}:{pago['usr_id']}"
    )

    if unidad.get("custom_id") != referencia:
        raise HTTPException(
            status_code=409,
            detail="La referencia de la orden no coincide"
        )

    if (
        pago["tipo"] != "aportacion"
        or pago["promocion_id"] is not None
    ):
        raise HTTPException(
            status_code=409,
            detail="Este flujo solo admite aportaciones"
        )

    validar_importe(
        unidad.get("amount"),
        pago
    )

    return unidad


# Obtener la captura confirmada por PayPal.
def obtener_captura(orden: dict) -> dict:
    unidades = orden.get("purchase_units")

    if not isinstance(unidades, list) or len(unidades) != 1:
        raise HTTPException(
            status_code=502,
            detail="Respuesta de PayPal con unidades inesperadas"
        )

    pagos = unidades[0].get("payments", {})

    capturas = (
        pagos.get("captures", [])
        if isinstance(pagos, dict)
        else []
    )

    if not isinstance(capturas, list) or len(capturas) != 1:
        raise HTTPException(
            status_code=502,
            detail="No se encontró una captura única"
        )

    captura = capturas[0]

    if not isinstance(captura, dict):
        raise HTTPException(
            status_code=502,
            detail="Captura de PayPal inválida"
        )

    return captura


# Sincronizar una captura confirmada con MariaDB.
def sincronizar_captura(
    db: Session,
    pago: dict,
    orden: dict
) -> dict:
    validar_orden(orden, pago)

    if orden.get("status") != "COMPLETED":
        raise HTTPException(
            status_code=409,
            detail="La orden aún no está completada"
        )

    captura = obtener_captura(orden)

    if captura.get("status") != "COMPLETED":
        raise HTTPException(
            status_code=409,
            detail="La captura aún no está completada"
        )

    id_captura = captura.get("id")

    if not isinstance(id_captura, str) or not id_captura:
        raise HTTPException(
            status_code=502,
            detail="PayPal no devolvió el identificador de captura"
        )

    validar_importe(
        captura.get("amount"),
        pago
    )

    # Evitar confirmar dos veces una misma captura.
    if pago["estatus"] == "completado":
        if pago["paypal_capture_id"] != id_captura:
            raise HTTPException(
                status_code=409,
                detail="Existe una captura diferente registrada"
            )

        return {
            "mensaje": "El pago ya estaba confirmado",
            "id_pago": pago["id_pago"],
            "paypal_capture_id": id_captura,
            "estatus": "completado"
        }

    try:
        resultado = db.execute(
            text("""
                update pagos
                set
                    paypal_capture_id = :id_captura,
                    estatus = 'completado',
                    fecha_confirmacion = current_timestamp
                where id_pago = :id_pago
                and estatus in ('creado', 'aprobado')
            """),
            {
                "id_captura": id_captura,
                "id_pago": pago["id_pago"]
            }
        )

        if resultado.rowcount != 1:
            db.rollback()

            # Comprobar si otra solicitud confirmo el pago.
            actualizado = obtener_pago(
                db,
                pago["paypal_order_id"],
                pago["usr_id"]
            )

            if (
                actualizado["estatus"] == "completado"
                and actualizado["paypal_capture_id"] == id_captura
            ):
                return {
                    "mensaje": "El pago ya estaba confirmado",
                    "id_pago": pago["id_pago"],
                    "paypal_capture_id": id_captura,
                    "estatus": "completado"
                }

            raise HTTPException(
                status_code=409,
                detail="El pago no admite esta transición"
            )

        db.commit()

    except IntegrityError as error:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail="La captura ya se encuentra registrada"
        ) from error

    except SQLAlchemyError as error:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="No fue posible guardar la confirmación"
        ) from error

    return {
        "mensaje": "Pago confirmado correctamente",
        "id_pago": pago["id_pago"],
        "paypal_capture_id": id_captura,
        "estatus": "completado"
    }


# Consultar la configuracion publica de PayPal.
@router.get("/configuracion")
def consultar_configuracion():
    return {
        "proveedor": "PayPal",
        "modo": PAYPAL_MODE,
        "moneda": PAYPAL_CURRENCY,
        "configurado": bool(
            PAYPAL_MODE in ("sandbox", "live")
            and PAYPAL_CLIENT_ID
            and PAYPAL_CLIENT_SECRET
            and os.getenv(
                "PAYPAL_CURRENCY",
                "MXN"
            ).upper() == "MXN"
        )
    }


# Verificar la conexion con PayPal.
@router.get("/verificar-conexion")
async def verificar_conexion(
    usuario: dict = Depends(
        verificar_roles("administrador")
    )
):
    await obtener_token_paypal()

    return {
        "mensaje": "Autenticación con PayPal correcta",
        "modo": PAYPAL_MODE
    }


# Consultar los pagos del usuario autenticado.
@router.get("/mis-pagos")
def consultar_mis_pagos(
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    try:
        filas = db.execute(
            text("""
                select
                    id_pago,
                    promocion_id,
                    tipo,
                    paypal_order_id,
                    paypal_capture_id,
                    monto,
                    moneda,
                    entorno,
                    estatus,
                    fecha,
                    fecha_confirmacion
                from pagos
                where usr_id = :usr_id
                order by fecha desc
            """),
            {
                "usr_id": usuario["id_usr"]
            }
        ).mappings().all()

        return [
            dict(fila)
            for fila in filas
        ]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los pagos"
        ) from error


# Consultar todos los pagos como administrador.
@router.get("/administracion/pagos")
def consultar_todos_los_pagos(
    usuario: dict = Depends(
        verificar_roles("administrador")
    ),
    db: Session = Depends(get_db)
):
    try:
        filas = db.execute(
            text("""
                select
                    p.*,
                    u.nom_usr as nombre_usuario
                from pagos p
                inner join usuario u
                    on p.usr_id = u.id_usr
                order by p.fecha desc
            """)
        ).mappings().all()

        return [
            dict(fila)
            for fila in filas
        ]

    except SQLAlchemyError as error:
        raise HTTPException(
            status_code=500,
            detail="Error al consultar los pagos"
        ) from error


# Crear una orden de aportacion voluntaria.
@router.post("/aportaciones/crear")
async def crear_aportacion(
    datos: AportacionRegistro,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    monto = f"{datos.monto:.2f}"
    solicitud_id = str(uuid.uuid4())

    orden = await solicitar_paypal(
        metodo="POST",
        ruta="/v2/checkout/orders",
        datos={
            "intent": "CAPTURE",
            "purchase_units": [
                {
                    "reference_id": "aportacion",
                    "custom_id": (
                        f"vitasacra:aportacion:{usuario['id_usr']}"
                    ),
                    "description": (
                        "Aportación voluntaria a Vita Sacra"
                    ),
                    "amount": {
                        "currency_code": PAYPAL_CURRENCY,
                        "value": monto
                    }
                }
            ]
        },
        solicitud_id=solicitud_id
    )

    id_orden = orden.get("id")

    if (
        not isinstance(id_orden, str)
        or not id_orden
        or orden.get("status") != "CREATED"
    ):
        raise HTTPException(
            status_code=502,
            detail="PayPal no confirmó la creación de la orden"
        )

    # Obtener el enlace para aprobar la orden.
    enlace_aprobacion = next(
        (
            enlace.get("href")
            for enlace in orden.get("links", [])
            if (
                isinstance(enlace, dict)
                and enlace.get("rel") in (
                    "approve",
                    "payer-action"
                )
            )
        ),
        None
    )

    if (
        not isinstance(enlace_aprobacion, str)
        or not enlace_aprobacion.startswith("https://")
    ):
        raise HTTPException(
            status_code=502,
            detail="PayPal no devolvió un enlace de aprobación válido"
        )

    # Registrar la orden en MariaDB.
    try:
        resultado = db.execute(
            text("""
                insert into pagos (
                    usr_id,
                    promocion_id,
                    tipo,
                    paypal_order_id,
                    monto,
                    moneda,
                    entorno,
                    estatus
                )
                values (
                    :usr_id,
                    null,
                    'aportacion',
                    :id_orden,
                    :monto,
                    :moneda,
                    :entorno,
                    'creado'
                )
            """),
            {
                "usr_id": usuario["id_usr"],
                "id_orden": id_orden,
                "monto": datos.monto,
                "moneda": PAYPAL_CURRENCY,
                "entorno": ENTORNO_BD
            }
        )

        id_pago = resultado.lastrowid

        db.commit()

    except SQLAlchemyError as error:
        db.rollback()

        # No devolver una orden sin registro local.
        raise HTTPException(
            status_code=500,
            detail="No se pudo registrar la orden en MariaDB"
        ) from error

    return {
        "mensaje": "Orden de aportación creada",
        "id_pago": id_pago,
        "paypal_order_id": id_orden,
        "estatus": "creado",
        "monto": monto,
        "moneda": PAYPAL_CURRENCY,
        "url_aprobacion": enlace_aprobacion
    }


# Consultar una orden propia en PayPal.
@router.get("/orden/{id_orden}")
async def consultar_orden(
    id_orden: str,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    pago = obtener_pago(
        db,
        id_orden,
        usuario["id_usr"]
    )

    validar_entorno(pago)

    orden = await solicitar_paypal(
        "GET",
        f"/v2/checkout/orders/{id_orden}"
    )

    validar_orden(orden, pago)

    return {
        "id_pago": pago["id_pago"],
        "paypal_order_id": id_orden,
        "estatus_local": pago["estatus"],
        "estatus_paypal": orden.get("status"),
        "monto": str(pago["monto"]),
        "moneda": pago["moneda"]
    }


# Capturar una orden aprobada por el usuario.
@router.post("/orden/{id_orden}/capturar")
async def capturar_orden(
    id_orden: str,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    pago = obtener_pago(
        db,
        id_orden,
        usuario["id_usr"]
    )

    validar_entorno(pago)

    if pago["estatus"] not in (
        "creado",
        "aprobado",
        "completado"
    ):
        raise HTTPException(
            status_code=409,
            detail="El pago no se encuentra disponible para captura"
        )

    # Consultar el estado real de PayPal.
    orden = await solicitar_paypal(
        "GET",
        f"/v2/checkout/orders/{id_orden}"
    )

    validar_orden(orden, pago)

    # Sincronizar una orden previamente capturada.
    if orden.get("status") == "COMPLETED":
        return sincronizar_captura(
            db,
            pago,
            orden
        )

    if pago["estatus"] == "completado":
        raise HTTPException(
            status_code=409,
            detail="El estado local no coincide con PayPal"
        )

    if orden.get("status") != "APPROVED":
        raise HTTPException(
            status_code=409,
            detail="El usuario aún no ha aprobado la orden"
        )

    # Mantener el mismo identificador en los reintentos.
    solicitud_id = str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            f"vitasacra:captura:{ENTORNO_BD}:{id_orden}"
        )
    )

    respuesta = await solicitar_paypal(
        metodo="POST",
        ruta=f"/v2/checkout/orders/{id_orden}/capture",
        datos={},
        solicitud_id=solicitud_id
    )

    if respuesta.get("status") != "COMPLETED":
        return {
            "mensaje": "La captura aún no está completada",
            "id_pago": pago["id_pago"],
            "estatus_paypal": respuesta.get("status"),
            "estatus_local": pago["estatus"]
        }

    return sincronizar_captura(
        db,
        pago,
        respuesta
    )


# Sincronizar una captura con MariaDB.
@router.post("/orden/{id_orden}/sincronizar")
async def sincronizar_orden(
    id_orden: str,
    usuario: dict = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db)
):
    pago = obtener_pago(
        db,
        id_orden,
        usuario["id_usr"]
    )

    validar_entorno(pago)

    if pago["estatus"] not in (
        "creado",
        "aprobado",
        "completado"
    ):
        raise HTTPException(
            status_code=409,
            detail="El pago no admite sincronización"
        )

    orden = await solicitar_paypal(
        "GET",
        f"/v2/checkout/orders/{id_orden}"
    )

    return sincronizar_captura(
        db,
        pago,
        orden
    )