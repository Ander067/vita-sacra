import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AbrirMapaButton extends StatefulWidget {
  final String nombre;
  final String direccion;
  final String latitud;
  final String longitud;

  const AbrirMapaButton({
    super.key,
    required this.nombre,
    required this.direccion,
    required this.latitud,
    required this.longitud,
  });

  @override
  State<AbrirMapaButton> createState() => _AbrirMapaButtonState();
}

class _AbrirMapaButtonState extends State<AbrirMapaButton> {
  bool _abriendo = false;

  double? _leerCoordenada(String valor) {
    final double? coordenada = double.tryParse(valor.trim());

    if (coordenada == null || !coordenada.isFinite) {
      return null;
    }

    return coordenada;
  }

  String? _crearDestino() {
    final double? latitud = _leerCoordenada(widget.latitud);
    final double? longitud = _leerCoordenada(widget.longitud);

    final bool coordenadasValidas =
        latitud != null &&
        longitud != null &&
        latitud >= -90 &&
        latitud <= 90 &&
        longitud >= -180 &&
        longitud <= 180;

    if (coordenadasValidas) {
      return '$latitud,$longitud';
    }

    final String direccion = widget.direccion.trim();
    final String nombre = widget.nombre.trim();

    if (direccion.isNotEmpty && nombre.isNotEmpty) {
      return '$direccion, $nombre';
    }

    if (direccion.isNotEmpty) {
      return direccion;
    }

    if (nombre.isNotEmpty && nombre.toLowerCase() != 'establecimiento') {
      return nombre;
    }

    return null;
  }

  Future<void> _abrirMapa() async {
    if (_abriendo) {
      return;
    }

    final String? destino = _crearDestino();

    if (destino == null) {
      _mostrarMensaje('Este establecimiento no tiene ubicación disponible.');
      return;
    }

    final Uri url = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destino,
    });

    setState(() {
      _abriendo = true;
    });

    try {
      final bool abierto = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!abierto && mounted) {
        _mostrarMensaje('No fue posible abrir una aplicación de mapas.');
      }
    } catch (error) {
      if (mounted) {
        _mostrarMensaje('Ocurrió un error al abrir el mapa.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _abriendo = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final bool disponible = _crearDestino() != null;

    return OutlinedButton.icon(
      onPressed: _abriendo || !disponible ? null : _abrirMapa,
      icon: _abriendo
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.directions_outlined),
      label: Text(_abriendo ? 'Abriendo mapa...' : 'Abrir en mapas'),
    );
  }
}
