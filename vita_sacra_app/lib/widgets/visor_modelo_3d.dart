import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

// Widget reutilizable para visualizar modelos anatomicos en formato GLB.
class VisorModelo3D extends StatelessWidget {
  // Direccion publica del archivo tridimensional.
  final String urlModelo;

  // Nombre accesible del modelo que se esta mostrando.
  final String titulo;

  // MIME opcional para enlaces GLB que no terminan en .glb.
  final String? mime;

  // Altura del area de visualizacion.
  final double altura;

  const VisorModelo3D({
    super.key,
    required this.urlModelo,
    required this.titulo,
    this.mime,
    this.altura = 300,
  });

  // Verificar que el enlace sea HTTPS y no incluya credenciales.
  bool _esUrlSegura(String url) {
    final Uri? uri = Uri.tryParse(url.trim());

    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  // Comprobar la extension o el formato del recurso solicitado.
  bool _esArchivoGlb(String url) {
    final Uri? uri = Uri.tryParse(url.trim());

    if (uri == null) {
      return false;
    }

    // Las URL firmadas pueden tener parametros despues de la extension.
    return uri.path.toLowerCase().endsWith('.glb') ||
        (mime ?? '').trim().toLowerCase() == 'model/gltf-binary';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final String url = urlModelo.trim();
    final String nombre = titulo.trim().isEmpty
        ? 'Modelo anatomico tridimensional'
        : titulo.trim();

    // Evitar cargar enlaces vacios, inseguros o de formato no compatible.
    if (!_esUrlSegura(url) || !_esArchivoGlb(url)) {
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
            Icon(Icons.warning_amber_outlined, size: 42, color: colores.error),
            const SizedBox(height: 12),
            const Text(
              'No se puede visualizar este modelo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Se requiere un enlace HTTPS a un archivo GLB valido.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colores.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // El visor usa un WebView interno para representar el archivo GLB.
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
          ar: false,
          backgroundColor: colores.surfaceContainerLow,
        ),
      ),
    );
  }
}
