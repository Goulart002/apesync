import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pix_widgets.dart';
import 'fluxo.dart';

/// Moradores da casa, convite e administração.
///
/// - Todos: veem os moradores, convidam pelo código, editam o próprio nome
///   e podem sair da casa.
/// - Administrador: remove moradores, transfere a administração e gera um
///   novo código de convite.
class MoradoresScreen extends StatelessWidget {
  const MoradoresScreen({super.key});

  static void _aviso(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  static Future<bool> _confirmar(
    BuildContext context, {
    required String titulo,
    required String texto,
    required String botao,
    bool perigoso = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: perigoso ? AppColors.negative : null),
            child: Text(botao),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ---------------- Convite ----------------

  Future<void> _compartilhar(BuildContext context, Casa casa) async {
    try {
      await SharePlus.instance.share(ShareParams(
        subject: 'Convite para a casa ${casa.nome}',
        text: 'Entre na nossa casa "${casa.nome}" no ApeSync para dividir '
            'os gastos!\n\nCódigo de convite: ${casa.codigoConvite}',
      ));
    } catch (_) {
      // Sem tela de compartilhar (ex.: alguns desktops): copia o código.
      await Clipboard.setData(ClipboardData(text: casa.codigoConvite));
      if (context.mounted) _aviso(context, 'Código copiado');
    }
  }

  Future<void> _novoCodigo(BuildContext context) async {
    final ok = await _confirmar(
      context,
      titulo: 'Gerar novo código',
      texto: 'O código atual vai parar de funcionar. Quem já mora na casa '
          'continua normalmente. Use isso se o código foi parar com quem '
          'não devia.',
      botao: 'Gerar',
    );
    if (!ok || !context.mounted) return;
    try {
      await AppData.instance.gerarNovoCodigo();
      if (context.mounted) _aviso(context, 'Novo código gerado');
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  // ---------------- Moradores ----------------

  Future<void> _editarNome(BuildContext context, Morador m) async {
    final controle = TextEditingController(text: m.nome);
    final nome = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar nome'),
        content: TextField(
          controller: controle,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Nome'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controle.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (nome == null || nome.isEmpty || !context.mounted) return;
    try {
      await AppData.instance.editarNome(m, nome);
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  Future<void> _remover(BuildContext context, Morador m) async {
    final data = AppData.instance;
    final motivo = data.permissoes.motivoNaoPodeRemover(m, data.saldoDe(m.id));
    if (motivo != null) {
      _aviso(context, motivo);
      return;
    }
    // Está devendo? Mostra quanto cada um que fica vai absorver.
    final ajuste = data.previaAjuste(m);
    var divida = '';
    if (ajuste != null) {
      final n = ajuste.divididoEntre.length;
      final cada = ajuste.valorCentavos ~/ n;
      final exato = ajuste.valorCentavos % n == 0;
      divida = '${m.nome} deve ${formatarReais(ajuste.valorCentavos)}. Ao '
          'remover, esse valor será dividido entre os $n moradores que ficam '
          '(${exato ? '' : 'cerca de '}${formatarReais(cada)} cada). Isso fica '
          'registrado nos gastos como um ajuste.\n\n';
    }
    final ok = await _confirmar(
      context,
      titulo: 'Remover morador',
      texto: '${divida}Remover ${m.nome} da casa? O nome continua aparecendo '
          'nos gastos antigos. Se precisar, a pessoa pode voltar com o código '
          'de convite.',
      botao: 'Remover',
      perigoso: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await data.removerMorador(m);
      if (context.mounted) _aviso(context, '${m.nome} foi removido da casa');
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  Future<void> _tornarAdmin(BuildContext context, Morador m) async {
    final ok = await _confirmar(
      context,
      titulo: 'Transferir administração',
      texto: '${m.nome} passa a administrar a casa e você deixa de ser '
          'admin. Só ${m.nome} poderá desfazer isso. Precisa de internet.',
      botao: 'Transferir',
    );
    if (!ok || !context.mounted) return;
    try {
      await AppData.instance.transferirAdmin(m);
      if (context.mounted) {
        _aviso(context, '${m.nome} agora administra a casa');
      }
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  Future<void> _sairDaCasa(BuildContext context) async {
    final data = AppData.instance;
    final eu = data.meuMorador;
    if (eu == null) return;
    final motivo = data.permissoes.motivoNaoPodeSair(
      meuSaldo: data.saldoDe(eu.id),
      outrosComConta:
          data.moradores.where((m) => m.temConta && m.id != eu.id).length,
    );
    if (motivo != null) {
      _aviso(context, motivo);
      return;
    }
    final ok = await _confirmar(
      context,
      titulo: 'Sair da casa',
      texto: 'Você deixa de ver os gastos de "${data.nomeCasa}". Para voltar, '
          'vai precisar do código de convite. Precisa de internet.',
      botao: 'Sair da casa',
      perigoso: true,
    );
    if (!ok || !context.mounted) return;
    try {
      // Ao sair, a tela inicial leva para "Sua casa" sozinha.
      await data.sairDaCasa();
    } catch (e) {
      if (context.mounted) _aviso(context, mensagemErro(e));
    }
  }

  // ---------------- Tela ----------------

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return Scaffold(
      floatingActionButton: ListenableBuilder(
        listenable: data,
        builder: (context, _) {
          final casa = data.casa;
          if (casa == null) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => _compartilhar(context, casa),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Convidar'),
          );
        },
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: data,
          builder: (context, _) {
            final casa = data.casa;
            final perm = data.permissoes;
            final admin = data.adminMorador;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                Row(
                  children: [
                    SquareIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.pop(context)),
                    const Expanded(
                      child: Text('Moradores',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 20),

                // Código de convite
                if (casa != null) _cartaoConvite(context, casa, perm),

                const SectionHeader('Quem mora aqui'),
                AppCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < data.moradores.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: AppColors.divider),
                        _linha(context, data, perm, data.moradores[i]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  perm.souAdmin
                      ? 'Você administra a casa: pode remover moradores, '
                          'transferir a administração e gerar um novo código '
                          'de convite. Novos moradores entram pelo código.'
                      : 'Quem administra a casa${admin == null ? '' : ' (${admin.nome})'} '
                          'pode remover moradores e gerar um novo código. '
                          'Novos moradores entram pelo código de convite.',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                if (data.meuMorador != null)
                  OutlinedButton.icon(
                    onPressed: () => _sairDaCasa(context),
                    icon: const Icon(Icons.logout, size: 20),
                    label: const Text('Sair da casa'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.negative,
                      side: const BorderSide(color: Color(0xFFFECACA)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cartaoConvite(BuildContext context, Casa casa, Permissoes perm) {
    return AppCard(
      color: AppColors.primaryLight,
      border: const Border(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(casa.nome,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Código de convite',
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                    Text(casa.codigoConvite,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                            color: AppColors.primary)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copiar código',
                icon: Icon(Icons.copy, color: AppColors.primary),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: casa.codigoConvite));
                  _aviso(context, 'Código copiado');
                },
              ),
              IconButton(
                tooltip: 'Compartilhar convite',
                icon:
                    Icon(Icons.share_outlined, color: AppColors.primary),
                onPressed: () => _compartilhar(context, casa),
              ),
            ],
          ),
          if (perm.podeGerarCodigo)
            TextButton.icon(
              onPressed: () => _novoCodigo(context),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Gerar novo código'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linha(
      BuildContext context, AppData data, Permissoes perm, Morador m) {
    final souEu = m.id == data.euId;
    final ehAdmin = perm.ehAdmin(m);
    final String subtitulo;
    if (ehAdmin) {
      subtitulo = 'Administrador';
    } else if (m.temConta) {
      subtitulo = 'Morador';
    } else {
      subtitulo = 'Sem conta no app (cadastro antigo)';
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Avatar(m, size: 38),
      title: Row(
        children: [
          Flexible(
            child: Text(souEu ? '${m.nome} (você)' : m.nome,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (ehAdmin) ...[
            const SizedBox(width: 6),
            const _SeloAdmin(),
          ],
        ],
      ),
      subtitle: Text(
          m.temConta
              ? '$subtitulo · ${m.chavePix != null ? 'PIX cadastrado' : 'sem PIX'}'
              : subtitulo,
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (souEu)
            IconButton(
              tooltip: 'Minha chave PIX',
              icon: Icon(Icons.pix,
                  color: m.chavePix != null ? AppColors.primary : null),
              onPressed: () => editarMinhaChavePix(context),
            ),
          if (perm.podeEditarMorador(m))
            IconButton(
              tooltip: 'Editar nome',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editarNome(context, m),
            ),
          if (perm.souAdmin && !souEu)
            PopupMenuButton<String>(
              tooltip: 'Mais opções',
              onSelected: (op) {
                if (op == 'admin') _tornarAdmin(context, m);
                if (op == 'remover') _remover(context, m);
              },
              itemBuilder: (context) => [
                if (perm.podeTornarAdmin(m))
                  const PopupMenuItem(
                    value: 'admin',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.shield_outlined),
                      title: Text('Tornar administrador'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'remover',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.person_remove_outlined,
                        color: AppColors.negative),
                    title: Text('Remover da casa',
                        style: TextStyle(color: AppColors.negative)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SeloAdmin extends StatelessWidget {
  const _SeloAdmin();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('Admin',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary)),
    );
  }
}
