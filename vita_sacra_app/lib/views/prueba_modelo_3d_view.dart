import 'package:flutter/material.dart';

import '../widgets/visor_modelo_3d.dart';

// Pantalla independiente para probar la visualizacion de modelos 3D.
class PruebaModelo3DView extends StatelessWidget {
  const PruebaModelo3DView({super.key});

  // Enlace directo al modelo GLB del corazon humano.
  static const String urlCorazon =
      'https://cdn.3dassets.dev/assets/38952/v1/model.glb';

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      appBar: AppBar(
        title: const Text('Prueba del visor 3D'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Modelo anatomico: corazon humano',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Esta prueba carga el archivo GLB directamente '
                'sin consultar la base de datos ni FastAPI.',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 20),

              // Visor 3D reutilizable.
              VisorModelo3D(
                urlModelo: urlCorazon,
                titulo: 'Corazon humano',
                mime: 'model/gltf-binary',
                altura: 350,
              ),

              const SizedBox(height: 16),

              Text(
                'URL del modelo:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colores.onSurface,
                ),
              ),

              const SizedBox(height: 6),

              SelectableText(
                urlCorazon,
                style: TextStyle(fontSize: 12, color: colores.primary),
              ),

              const SizedBox(height: 16),

              Text(
                'Prueba mover el modelo con el dedo para comprobar '
                'si responde a los controles de la camara.',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
