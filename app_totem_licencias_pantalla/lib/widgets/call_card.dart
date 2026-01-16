import 'package:flutter/material.dart';
import '../models/ticket.dart';

class CallCard extends StatelessWidget {
  final Ticket ticket;
  final bool isSmall;
  const CallCard({super.key, required this.ticket, this.isSmall = false});

  // Limpia underscores/guiones y colapsa espacios
  String _cleanModule(String s) {
    final t = s.replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? '-' : t;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final scale = (w / 600).clamp(0.8, 1.15);
      final padV = 8.0 * scale;
      final padH = 12.0 * scale;
      final primary = Theme.of(context).primaryColor;

      return Padding(
        padding: EdgeInsets.symmetric(vertical: padV / 2, horizontal: padH / 2),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            border: Border.all(color: primary.withOpacity(0.7), width: 1.2 * scale),
            borderRadius: BorderRadius.circular(12 * scale),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 4 * scale, offset: Offset(0, 2 * scale)),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: padV, horizontal: padH),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Ícono megáfono
                Container(
                  padding: EdgeInsets.all(10 * scale),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10 * scale),
                  ),
                  child: Icon(Icons.campaign_rounded, size: (isSmall ? 28 : 36) * scale, color: primary),
                ),
                SizedBox(width: 12 * scale),

                // Nombre + MÓDULO (estilo único)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nombre (auto-fit)
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            ticket.name.isEmpty ? 'Llamado' : ticket.name,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: (isSmall ? 24 : 56) * scale,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              height: 1.05,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 6 * scale),

                      // MÓDULO <valor> — mismo estilo para todo
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            ' ${_cleanModule(ticket.station).toUpperCase()}',
                            style: TextStyle(
                              fontSize: (isSmall ? 28 : 40) * scale,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                              letterSpacing: .5,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
