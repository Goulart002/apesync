import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_data.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// CRUD de moradores + código de convite da casa.
class MoradoresScreen extends StatelessWidget {
  const MoradoresScreen({super.key});

  Future<void> _editar(BuildContext context, {Morador? m}) async {
    final controle = TextEditingController(text: m?.nome ?? '');
    final nome = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(m == null ? 'Novo morador' : 'Editar morador'),
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
    if (nome == null || nome.isEmpty) return;
    await AppData.instance.salvarMorador(id: m?.id, nome: nome);
  }

  Future<void> _excluir(BuildContext context, Morador m) async {
    final data = AppData.instance;
    final messenger = ScaffoldMessenger.of(context);
    if (data.moradorEmUso(m.id)) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Esse morador aparece em gastos ou pagamentos. Exclua-os antes.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover morador'),
        content: Text('Remover ${m.nome} da casa?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: AppColors.negative),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await data.excluirMorador(m.id);
    messenger.showSnackBar(SnackBar(content: Text('${m.nome} removido')));
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Adicionar'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: data,
          builder: (context, _) {
            final casa = data.casa;
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
                if (casa != null)
                  AppCard(
                    color: AppColors.primaryLight,
                    border: const Border(),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(casa.nome,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              const Text('Código de convite',
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.muted)),
                              Text(casa.codigoConvite,
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 4,
                                      color: AppColors.primary)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar código',
                          icon: const Icon(Icons.copy, color: AppColors.primary),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: casa.codigoConvite));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Código copiado')));
                          },
                        ),
                      ],
                    ),
                  ),

                const SectionHeader('Quem mora aqui'),
                AppCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < data.moradores.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: AppColors.divider),
                        _linha(context, data, data.moradores[i]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Moradores sem conta no app também podem participar dos gastos. '
                  'Quem entrar com o código aparece aqui automaticamente.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _linha(BuildContext context, AppData data, Morador m) {
    final souEu = m.id == data.euId;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Avatar(m, size: 38),
      title: Text(souEu ? '${m.nome} (você)' : m.nome,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(m.temConta ? 'Tem conta no app' : 'Sem conta no app',
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editar(context, m: m),
          ),
          if (!souEu)
            IconButton(
              tooltip: 'Remover',
              icon: const Icon(Icons.delete_outline, color: AppColors.negative),
              onPressed: () => _excluir(context, m),
            ),
        ],
      ),
    );
  }
}
