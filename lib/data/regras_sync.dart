import 'package:flutter/foundation.dart';

/// Regras puras da sincronização (sem banco, sem internet) — fáceis de testar.
class RegrasSync {
  /// Margem do download. O servidor marca cada linha com a hora em que ela
  /// foi gravada (`synced_at`), mas duas gravações quase simultâneas podem
  /// ficar visíveis fora de ordem: uma linha com hora menor aparece depois
  /// que o app já baixou outra com hora maior. Sem margem, essa linha nunca
  /// seria baixada. Por isso cada download volta [margem] antes da última
  /// marca (baixar de novo uma linha que já temos não faz mal).
  static const margem = Duration(seconds: 60);

  static const _inicio = '1970-01-01T00:00:00Z';

  /// A partir de quando baixar, dada a última marca gravada.
  static String desdeComMargem(String? marca) {
    if (marca == null) return _inicio;
    return DateTime.parse(marca).toUtc().subtract(margem).toIso8601String();
  }

  /// Nova marca: nunca anda para trás (com a margem, o download pode trazer
  /// só linhas mais antigas que a marca atual).
  static String novaMarca(String? atual, String ultimaBaixada) {
    if (atual == null) return ultimaBaixada;
    return DateTime.parse(ultimaBaixada).isAfter(DateTime.parse(atual))
        ? ultimaBaixada
        : atual;
  }

  /// Gravar no celular a linha que veio do servidor?
  ///
  /// - [local]: linha atual do SQLite (null = não existe).
  /// - [remoto]: linha do servidor já convertida para o formato do SQLite.
  ///
  /// Regras:
  /// - não existe no celular -> grava;
  /// - existe com alteração pendente -> mantém a do celular só se ela for
  ///   mais nova (ela sobe no próximo envio); senão o servidor vence;
  /// - já sincronizada -> só grava se algo mudou (evita recarregar as telas
  ///   à toa, já que a margem baixa de novo linhas que já temos).
  static bool aplicarRemoto(
      Map<String, Object?>? local, Map<String, Object?> remoto) {
    if (local == null) return true;
    if (local['pendente'] == 1) {
      final dataLocal = DateTime.parse(local['updated_at'] as String);
      final dataRemota = DateTime.parse(remoto['updated_at'] as String);
      return !dataLocal.isAfter(dataRemota);
    }
    final a = Map<String, Object?>.of(local)..remove('pendente');
    final b = Map<String, Object?>.of(remoto)..remove('pendente');
    return !mapEquals(a, b);
  }
}
