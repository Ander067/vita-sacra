import os
import smtplib
import ssl

from email.message import EmailMessage
from email.utils import formataddr

from dotenv import load_dotenv


load_dotenv()


def enviar_correo(
    destinatario: str,
    asunto: str,
    mensaje: str,
    mensaje_html: str | None = None
) -> None:
    host = os.getenv("SMTP_HOST", "smtp-relay.brevo.com").strip()
    puerto_texto = os.getenv("SMTP_PORT", "587").strip()
    usuario_smtp = os.getenv("SMTP_USERNAME", "").strip()
    clave_smtp = os.getenv("SMTP_PASSWORD", "")
    remitente = os.getenv("SMTP_FROM_EMAIL", "").strip()
    nombre_remitente = os.getenv("SMTP_FROM_NAME", "Vita Sacra").strip()

    faltantes = []

    if not host:
        faltantes.append("SMTP_HOST")

    if not usuario_smtp:
        faltantes.append("SMTP_USERNAME")

    if not clave_smtp:
        faltantes.append("SMTP_PASSWORD")

    if not remitente:
        faltantes.append("SMTP_FROM_EMAIL")

    if faltantes:
        raise RuntimeError(
            "Faltan variables SMTP en .env: " + ", ".join(faltantes)
        )

    try:
        puerto = int(puerto_texto)
    except ValueError as error:
        raise RuntimeError("SMTP_PORT debe ser un numero entero") from error

    if puerto != 587:
        raise RuntimeError(
            "Esta configuracion de Brevo requiere SMTP_PORT=587 con STARTTLS"
        )

    if any(caracter in destinatario for caracter in "\r\n"):
        raise ValueError("La direccion destinataria no es valida")

    if any(caracter in asunto for caracter in "\r\n"):
        raise ValueError("El asunto no puede contener saltos de linea")

    correo = EmailMessage()
    correo["Subject"] = asunto
    correo["From"] = formataddr((nombre_remitente, remitente))
    correo["To"] = destinatario
    correo.set_content(mensaje)

    if mensaje_html:
        correo.add_alternative(mensaje_html, subtype="html")

    contexto_tls = ssl.create_default_context()

    with smtplib.SMTP(host, puerto, timeout=20) as servidor:
        servidor.ehlo()
        servidor.starttls(context=contexto_tls)
        servidor.ehlo()
        servidor.login(usuario_smtp, clave_smtp)

        destinatarios_rechazados = servidor.send_message(correo)

        if destinatarios_rechazados:
            raise smtplib.SMTPRecipientsRefused(destinatarios_rechazados)