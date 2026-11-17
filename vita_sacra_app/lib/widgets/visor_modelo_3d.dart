import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class VisorModelo3D extends StatelessWidget {
  final String urlModelo;
  final String titulo;
  final String? mime;
  final double altura;

  const VisorModelo3D({
    super.key,
    required this.urlModelo,
    required this.titulo,
    this.mime,
    this.altura = 300,
  });

  bool _esUrlSegura(String url) {
    final Uri? uri = Uri.tryParse(url.trim());

    return uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  bool _esArchivoGlb(String url) {
    final Uri? uri = Uri.tryParse(url.trim());

    if (uri == null) {
      return false;
    }

    return uri.path.toLowerCase().endsWith('.glb') ||
        (mime ?? '').trim().toLowerCase() == 'model/gltf-binary';
  }

  Widget _construirMensaje(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required String descripcion,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: altura),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 44, color: colores.error),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            descripcion,
            textAlign: TextAlign.center,
            style: TextStyle(color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final String url = urlModelo.trim();
    final String nombre = titulo.trim().isEmpty
        ? 'Modelo anatomico tridimensional'
        : titulo.trim();

    if (!_esUrlSegura(url)) {
      return _construirMensaje(
        context,
        icono: Icons.link_off,
        titulo: 'No se puede abrir este modelo',
        descripcion: 'El recurso debe tener una URL HTTPS valida.',
      );
    }

    if (!_esArchivoGlb(url)) {
      return _construirMensaje(
        context,
        icono: Icons.view_in_ar_outlined,
        titulo: 'Formato no compatible',
        descripcion: 'Se requiere un modelo GLB valido.',
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: double.infinity,
        height: altura,
        child: ModelViewer(
          key: ValueKey<String>(url),
          src: url,
          alt: 'Modelo anatomico 3D: $nombre',
          cameraControls: true,
          autoRotate: false,
          cameraTarget: 'auto auto auto',
          cameraOrbit: 'auto 75deg 105%',
          exposure: 1,
          shadowIntensity: 0.8,
          shadowSoftness: 0.8,
          ar: true,
          arModes: const ['scene-viewer'],
          backgroundColor: colores.surfaceContainerLow,
        ),
      ),
    );
  }
}
