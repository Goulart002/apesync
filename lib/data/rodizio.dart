import 'package:uuid/uuid.dart';

import 'modelos.dart';
import 'recorrentes.dart';

enum SituacaoTarefa { concluida, atrasada, hoje, amanha, futura }

/// Regras das tarefas da casa: próxima data, de quem é a vez e o que muda
/// ao marcar como feita. Regras puras, fáceis de testar.
class Rodizio {
  /// "Namespace" fixo para o id do histórico (UUID v5 de tarefa + data):
  /// a mesma vez não conta duas vezes, mesmo marcada em dois celulares.
  static const _namespace = '0b7e4c2a-6d1f-4e8b-9c3a-5f2d8e1a7b64';

  static DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Próxima vez estritamente DEPOIS do dia [depoisDe] (null = não repete).
  static DateTime? proximaOcorrencia(Tarefa t, DateTime depoisDe) {
    final base = _dia(depoisDe);
    switch (t.repeticao) {
      case Repeticao.nenhuma:
        return null;
      case Repeticao.diaria:
        return DateTime(base.year, base.month, base.day + 1);
      case Repeticao.semanal:
        final dias = t.diasSemana.isEmpty ? [t.proxima.weekday] : t.diasSemana;
        for (var i = 1; i <= 7; i++) {
          final d = DateTime(base.year, base.month, base.day + i);
          if (dias.contains(d.weekday)) return d;
        }
        return null;
      case Repeticao.mensal:
        final dia = t.diaMes ?? t.proxima.day;
        final esteMes = Recorrentes.vencimento(base.year, base.month, dia);
        return esteMes.isAfter(base)
            ? esteMes
            : Recorrentes.vencimento(base.year, base.month + 1, dia);
    }
  }

  /// Próxima data depois de fazer a vez de [Tarefa.proxima] em [hoje].
  /// Se a tarefa estava atrasada há várias vezes, pula as perdidas: a
  /// próxima fica para hoje em diante.
  static DateTime? dataDepoisDeFeita(Tarefa t, DateTime hoje) {
    var d = proximaOcorrencia(t, t.proxima);
    while (d != null && d.isBefore(_dia(hoje))) {
      d = proximaOcorrencia(t, d);
    }
    return d;
  }

  /// De quem é a próxima vez, seguindo a ordem do rodízio e pulando quem
  /// saiu da casa ([ativos] = ids dos moradores atuais).
  static String? proximoResponsavel(Tarefa t, Set<String> ativos) {
    final fila = t.rodizio.where(ativos.contains).toList();
    if (fila.length < 2) {
      if (t.responsavelId != null && ativos.contains(t.responsavelId)) {
        return t.responsavelId;
      }
      return fila.isEmpty ? null : fila.first;
    }
    final i = fila.indexOf(t.responsavelId ?? '');
    return fila[(i + 1) % fila.length];
  }

  /// A tarefa depois de marcada como feita.
  static Tarefa depoisDeFeita(Tarefa t,
      {required DateTime hoje, required Set<String> ativos}) {
    final proxima = dataDepoisDeFeita(t, hoje);
    if (proxima == null) return t.copia(concluida: true);
    final vez = proximoResponsavel(t, ativos);
    return vez == null
        ? t.copia(proxima: proxima, limparResponsavel: true)
        : t.copia(proxima: proxima, responsavelId: vez);
  }

  static String idDaFeita(String tarefaId, DateTime dataPrevista) =>
      const Uuid().v5(_namespace, '$tarefaId/${dataIso(dataPrevista)}');

  static SituacaoTarefa situacao(Tarefa t, DateTime hoje) {
    if (t.concluida) return SituacaoTarefa.concluida;
    final h = _dia(hoje);
    final p = _dia(t.proxima);
    if (p.isBefore(h)) return SituacaoTarefa.atrasada;
    if (p == h) return SituacaoTarefa.hoje;
    if (p == DateTime(h.year, h.month, h.day + 1)) return SituacaoTarefa.amanha;
    return SituacaoTarefa.futura;
  }

  static const _semana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  /// "Não repete", "Todo dia", "Seg, Qua, Sex", "Todo dia 5".
  static String descreverRepeticao(Tarefa t) {
    switch (t.repeticao) {
      case Repeticao.nenhuma:
        return 'Não repete';
      case Repeticao.diaria:
        return 'Todo dia';
      case Repeticao.semanal:
        final dias = [
          ...(t.diasSemana.isEmpty ? [t.proxima.weekday] : t.diasSemana)
        ]..sort();
        if (dias.length == 7) return 'Todo dia';
        return dias.map((d) => _semana[d - 1]).join(', ');
      case Repeticao.mensal:
        return 'Todo dia ${t.diaMes ?? t.proxima.day} do mês';
    }
  }

  /// "atrasada há 2 dias", "hoje", "amanhã", "sex, 21/11".
  static String descreverData(Tarefa t, DateTime hoje) {
    final h = _dia(hoje);
    final p = _dia(t.proxima);
    switch (situacao(t, hoje)) {
      case SituacaoTarefa.concluida:
        return 'feita';
      case SituacaoTarefa.atrasada:
        final dias = h.difference(p).inDays;
        return dias == 1 ? 'atrasada desde ontem' : 'atrasada há $dias dias';
      case SituacaoTarefa.hoje:
        return 'hoje';
      case SituacaoTarefa.amanha:
        return 'amanhã';
      case SituacaoTarefa.futura:
        return '${_semana[p.weekday - 1].toLowerCase()}, '
            '${p.day.toString().padLeft(2, '0')}/${p.month.toString().padLeft(2, '0')}';
    }
  }

  /// Quantas tarefas cada morador fez no mês (placar).
  static Map<String, int> placarDoMes(
      Iterable<TarefaFeita> feitas, DateTime mes) {
    final placar = <String, int>{};
    for (final f in feitas) {
      if (f.deleted) continue;
      final d = DateTime.tryParse(f.feitaEm)?.toLocal();
      if (d == null || d.year != mes.year || d.month != mes.month) continue;
      placar[f.feitaPorId] = (placar[f.feitaPorId] ?? 0) + 1;
    }
    return placar;
  }
}
