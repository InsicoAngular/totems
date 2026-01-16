import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/cupos_provider.dart';
import '../models/cupos_info.dart';
import 'app_header.dart';

class ManualTramiteScreen extends ConsumerWidget {
  const ManualTramiteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final tramite = args['tramite'] as String;
    final code = args['code'] as String;

    // DESPUÉS: pide por el nombre visible del botón
    final cuposAsync = ref.watch(cuposProvider(tramite));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(),
            const SizedBox(height: 16),
            Text(
              tramite,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // —— cuerpo principal ——
            Expanded(
              child: cuposAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (CuposInfo info) {
                  final ahora = TimeOfDay.now();
                  final dentroHorario = _entre(ahora, info.inicio, info.fin);

                  if (!info.habilitado || !dentroHorario) {
                    return _bloqueado(info, dentroHorario, context);
                  }
                  return _disponible(info, tramite, code, context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— Pantalla bloqueo ——
  // —— Pantalla bloqueo ——
  Widget _bloqueado(CuposInfo info, bool dentro, BuildContext ctx) {
    final theme = Theme.of(ctx);
    final cs = theme.colorScheme;

    // Decidir título/icono “grandes”
    final mot = (info.motivo).toLowerCase();
    String titulo;
    IconData icono;

    if (mot.contains('horario')) {
      titulo = 'Fuera de horario';
      icono = Icons.schedule_rounded;
    } else if (mot.contains('habilitado') || mot.contains('configur')) {
      titulo = 'No se han habilitado cupos para este trámite';
      icono = Icons.hourglass_empty_rounded;
    } else if (mot.contains('agotad')) {
      titulo = 'Cupos agotados por hoy';
      icono = Icons.event_busy_rounded;
    } else {
      titulo = 'No disponible';
      icono = Icons.info_outline_rounded;
    }

    String rango = '';
    if (info.inicio.hour + info.fin.hour > 0) {
      rango =
          'Horario del trámite: ${info.inicio.format(ctx)} – ${info.fin.format(ctx)}';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.outline.withOpacity(.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 96, color: cs.primary),
                const SizedBox(height: 20),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (rango.isNotEmpty)
                  Text(
                    rango,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('VOLVER'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // —— Pantalla OK ——
  Widget _disponible(
    CuposInfo info,
    String tramite,
    String code,
    BuildContext ctx,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Cupos disponibles', style: Theme.of(ctx).textTheme.titleMedium),
        Text(
          '${info.cupos}',
          style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
          ),
          onPressed: () {
            Navigator.pushNamed(
              ctx,
              '/pad',
              arguments: {'modo': 'manual', 'tramite': tramite, 'code': code},
            );
          },
          child: const Text('CONTINUAR', style: TextStyle(fontSize: 28)),
        ),
      ],
    );
  }

  bool _entre(TimeOfDay x, TimeOfDay a, TimeOfDay b) {
    int m(TimeOfDay t) => t.hour * 60 + t.minute;
    return m(x) >= m(a) && m(x) < m(b);
  }
}
