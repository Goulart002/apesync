import 'package:flutter/material.dart';

import '../data/sync_service.dart';
import '../theme.dart';

/// Indicador de sincronização (como o reloginho do WhatsApp).
/// Toque para sincronizar na hora.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final (IconData icone, Color cor, String texto) = switch (sync.estado) {
          EstadoSync.sincronizado =>
            (Icons.cloud_done_outlined, AppColors.positive, 'Sincronizado'),
          EstadoSync.sincronizando =>
            (Icons.sync, AppColors.primary, 'Sincronizando...'),
          EstadoSync.pendente => (
              Icons.cloud_upload_outlined,
              AppColors.amber,
              '${sync.pendentes} pendente(s)'
            ),
          EstadoSync.semInternet => (
              Icons.cloud_off_outlined,
              AppColors.muted,
              sync.pendentes > 0
                  ? 'Offline · ${sync.pendentes} pendente(s)'
                  : 'Offline'
            ),
          EstadoSync.erro =>
            (Icons.error_outline, AppColors.negative, 'Erro ao sincronizar'),
        };
        return Tooltip(
          message: sync.ultimoErro ?? texto,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => sync.sincronizar(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icone, size: 16, color: cor),
                  const SizedBox(width: 6),
                  Text(texto,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cor)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
