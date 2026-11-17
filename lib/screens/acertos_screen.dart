import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

/// Acertos: dívidas simplificadas (quem paga quem), saldo de cada morador
/// e histórico de pagamentos registrados.
class AcertosScreen extends StatelessWidget {
  const AcertosScreen({super.key});

  Future<void> _confirmarPagamento(
      BuildContext context, Transferencia t) async {
    final data = AppData.instance;
    final de = data.nomeDe(t.deId);
    final para = data.nomeDe(t.paraId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar pagamento'),
        content: Text(
            'Confirmar que $de pagou ${formatarReais(t.valorCentavos)} para $para?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await data.registrarPagamento(t.deId, t.paraId, t.valorCentavos);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensagemErro(e))));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
          content: Text(
              'Pagamento registrado: $de → $para ${formatarReais(t.valorCentavos)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: data,
          builder: (context, _) {
            final transferencias = data.simplificarDividas();
            final semSimplificar = data.dividasSemSimplificar();
            final pagamentos = data.pagamentos;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    SquareIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.pop(context)),
                    const Expanded(
                      child: Text('Acertos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),

                // ---------- Quem paga quem ----------
                const SectionHeader('Quem paga quem'),
                if (transferencias.isEmpty)
                  const AppCard(
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: AppColors.positive),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Tudo certo! Ninguém deve nada.',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            semSimplificar > transferencias.length
                                ? 'Dívidas simplificadas: ${transferencias.length} '
                                    'transferência(s) em vez de $semSimplificar'
                                : 'Menor número de transferências possível',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final t in transferencias)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TransferenciaCard(
                        t: t,
                        onPagar: () => _confirmarPagamento(context, t),
                      ),
                    ),
                ],

                // ---------- Saldo por pessoa ----------
                const SectionHeader('Saldo de cada morador'),
                AppCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < data.moradores.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: AppColors.divider),
                        _SaldoMorador(data.moradores[i],
                            data.saldoDe(data.moradores[i].id)),
                      ],
                    ],
                  ),
                ),

                // ---------- Histórico ----------
                const SectionHeader('Histórico de pagamentos'),
                if (pagamentos.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Segure um pagamento para desfazer.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
                if (pagamentos.isEmpty)
                  const Text('Nenhum pagamento registrado ainda.',
                      style: TextStyle(color: AppColors.muted))
                else
                  AppCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < pagamentos.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: AppColors.divider),
                          _PagamentoTile(pagamentos[i]),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TransferenciaCard extends StatelessWidget {
  final Transferencia t;
  final VoidCallback onPagar;
  const _TransferenciaCard({required this.t, required this.onPagar});

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    final de = data.morador(t.deId);
    final para = data.morador(t.paraId);
    final envolveMim = t.deId == data.euId || t.paraId == data.euId;
    final podeRegistrar =
        data.permissoes.podeMexerNoPagamento(t.deId, t.paraId);

    return AppCard(
      border: Border.all(
          color: envolveMim ? AppColors.primary : AppColors.border,
          width: envolveMim ? 1.5 : 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(de, size: 36),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward,
                    size: 20, color: AppColors.muted),
              ),
              Avatar(para, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${data.nomeDe(t.deId)} paga ${data.nomeDe(t.paraId)}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Text(formatarReais(t.valorCentavos),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          if (podeRegistrar)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPagar,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Registrar pagamento'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  foregroundColor: AppColors.primary,
                  backgroundColor: AppColors.primaryLight,
                  side: BorderSide.none,
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            const Text(
                'Quem paga, quem recebe ou o administrador registra o pagamento.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _SaldoMorador extends StatelessWidget {
  final Morador m;
  final int saldo;
  const _SaldoMorador(this.m, this.saldo);

  @override
  Widget build(BuildContext context) {
    final String texto;
    final Color cor;
    if (saldo > 0) {
      texto = 'recebe ${formatarReais(saldo)}';
      cor = AppColors.positive;
    } else if (saldo < 0) {
      texto = 'deve ${formatarReais(-saldo)}';
      cor = AppColors.negative;
    } else {
      texto = 'quite';
      cor = AppColors.muted;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Avatar(m, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(m.nome,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Text(texto,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: cor)),
        ],
      ),
    );
  }
}

class _PagamentoTile extends StatelessWidget {
  final Pagamento p;
  const _PagamentoTile(this.p);

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return InkWell(
      // Segurar = desfazer o pagamento (DELETE lógico).
      onLongPress: () => _desfazer(context),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppColors.positiveLight,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.payments_outlined,
                size: 20, color: AppColors.positive),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${data.nomeDe(p.deId)} pagou ${data.nomeDe(p.paraId)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(dataCurta(p.data),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          Text(formatarReais(p.valorCentavos),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
      ),
    );
  }

  Future<void> _desfazer(BuildContext context) async {
    final data = AppData.instance;
    final messenger = ScaffoldMessenger.of(context);
    if (!data.permissoes.podeMexerNoPagamento(p.deId, p.paraId)) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Só quem pagou, quem recebeu ou o administrador '
              'pode desfazer este pagamento')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desfazer pagamento'),
        content: Text('Apagar o registro "${data.nomeDe(p.deId)} pagou '
            '${data.nomeDe(p.paraId)} ${formatarReais(p.valorCentavos)}"? '
            'A dívida volta a aparecer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: AppColors.negative),
            child: const Text('Desfazer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await data.excluirPagamento(p);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensagemErro(e))));
      return;
    }
    messenger.showSnackBar(
        const SnackBar(content: Text('Pagamento desfeito')));
  }
}
