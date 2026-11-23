import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../routes.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'fluxo.dart';

/// Aba Ajustes: perfil, senha, cor do app, sobre, sair e excluir a conta.
class AjustesScreen extends StatelessWidget {
  const AjustesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final eu = data.meuMorador;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            const Text('Ajustes',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Perfil
            AppCard(
              child: Row(
                children: [
                  if (eu != null) Avatar(eu, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(eu?.nome ?? data.nomeUsuario,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(data.emailDaConta,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar nome',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editarNome(context, eu?.nome ?? ''),
                  ),
                ],
              ),
            ),

            const SectionHeader('Conta'),
            _Grupo([
              _Item(
                icone: Icons.lock_reset,
                titulo: data.temSenha ? 'Trocar senha' : 'Criar senha',
                subtitulo: data.temSenha
                    ? null
                    : 'Para entrar também com e-mail e senha',
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _DialogoSenha(temSenha: data.temSenha),
                ),
              ),
              _Item(
                icone: Icons.logout,
                titulo: 'Sair da conta',
                onTap: () => _sair(context),
              ),
            ]),

            const SectionHeader('Cor do app'),
            const _CoresDoApp(),

            const SectionHeader('Sobre'),
            _Grupo([
              _Item(
                icone: Icons.info_outline,
                titulo: 'Sobre o ApêSync',
                subtitulo: 'Versão 1.0.0',
                onTap: () => Navigator.pushNamed(context, Rotas.sobre),
              ),
            ]),

            const SizedBox(height: 24),
            _Grupo([
              _Item(
                icone: Icons.delete_forever_outlined,
                titulo: 'Excluir conta',
                subtitulo: 'Apaga sua conta de vez',
                cor: AppColors.negative,
                onTap: () => _excluirConta(context),
              ),
            ]),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Peças da lista
// -----------------------------------------------------------------------------

class _Grupo extends StatelessWidget {
  final List<Widget> itens;
  const _Grupo(this.itens);

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < itens.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.divider),
              itens[i],
            ],
          ],
        ),
      );
}

class _Item extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? subtitulo;
  final Color? cor;
  final VoidCallback onTap;
  const _Item({
    required this.icone,
    required this.titulo,
    required this.onTap,
    this.subtitulo,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    final c = cor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: cor == null
                      ? AppColors.primaryLight
                      : AppColors.negativeLight,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icone, color: c, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cor ?? AppColors.text)),
                  if (subtitulo != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitulo!,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.hint),
          ],
        ),
      ),
    );
  }
}

/// Bolinhas de cor. A cor fica salva na conta (precisa de internet).
class _CoresDoApp extends StatefulWidget {
  const _CoresDoApp();

  @override
  State<_CoresDoApp> createState() => _CoresDoAppState();
}

class _CoresDoAppState extends State<_CoresDoApp> {
  String? _salvando;

  Future<void> _escolher(Paleta p) async {
    if (_salvando != null || p.id == AppColors.paleta.value.id) return;
    setState(() => _salvando = p.id);
    try {
      await AppData.instance.salvarCorDoApp(p.id);
      AppColors.usarPaleta(p.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
      }
    } finally {
      if (mounted) setState(() => _salvando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final atual = AppColors.paleta.value.id;
    return AppCard(
      child: Wrap(
        spacing: 8,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        children: [
          for (final p in AppColors.paletas)
            SizedBox(
              width: 64,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _escolher(p),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: p.cor,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: p.id == atual ? AppColors.text : p.suave,
                            width: p.id == atual ? 3 : 2),
                      ),
                      child: _salvando == p.id
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : p.id == atual
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                    ),
                    const SizedBox(height: 6),
                    Text(p.nome,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: p.id == atual
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppColors.text)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Ações
// -----------------------------------------------------------------------------

Future<void> _editarNome(BuildContext context, String nomeAtual) async {
  final controle = TextEditingController(text: nomeAtual);
  final novo = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Seu nome'),
      content: TextField(
        controller: controle,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Como a casa te chama'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controle.text),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  controle.dispose();
  if (novo == null || novo.trim() == nomeAtual || !context.mounted) return;
  try {
    await AppData.instance.editarMeuNome(novo);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nome atualizado')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro(e))));
    }
  }
}

Future<void> _sair(BuildContext context) async {
  final data = AppData.instance;
  final pendentes = await data.contarPendentes();
  if (!context.mounted) return;
  if (pendentes > 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta'),
        content: Text('Há $pendentes alteração(ões) ainda não sincronizada(s). '
            'Elas ficam guardadas neste celular e sobem quando você entrar de '
            'novo. Sair mesmo assim?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await data.sair();
  if (!context.mounted) return;
  Navigator.of(context).pushNamedAndRemoveUntil(Rotas.login, (_) => false);
}

Future<void> _excluirConta(BuildContext context) async {
  final data = AppData.instance;
  final motivo = data.motivoNaoPodeExcluirConta;
  if (motivo != null) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ainda não dá para excluir'),
        content: Text(motivo),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    return;
  }
  final mensageiro =
      ScaffoldMessenger.of(context); // continua após trocar de tela
  final excluiu = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DialogoExcluir(),
  );
  if (excluiu != true || !context.mounted) return;
  Navigator.of(context).pushNamedAndRemoveUntil(Rotas.login, (_) => false);
  mensageiro
      .showSnackBar(const SnackBar(content: Text('Sua conta foi excluída.')));
}

// -----------------------------------------------------------------------------
// Diálogos
// -----------------------------------------------------------------------------

class _DialogoSenha extends StatefulWidget {
  final bool temSenha;
  const _DialogoSenha({required this.temSenha});

  @override
  State<_DialogoSenha> createState() => _DialogoSenhaState();
}

class _DialogoSenhaState extends State<_DialogoSenha> {
  final _form = GlobalKey<FormState>();
  final _atual = TextEditingController();
  final _nova = TextEditingController();
  final _confirmar = TextEditingController();
  bool _carregando = false;
  bool _visivel = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_atual, _nova, _confirmar]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await AppData.instance.trocarSenha(
        atual: widget.temSenha ? _atual.text : null,
        nova: _nova.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(widget.temSenha ? 'Senha alterada!' : 'Senha criada!')));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Widget _campo(TextEditingController c, String rotulo,
          String? Function(String?) validar) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          obscureText: !_visivel,
          decoration: InputDecoration(
            labelText: rotulo,
            suffixIcon: IconButton(
              icon: Icon(_visivel
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () => setState(() => _visivel = !_visivel),
            ),
          ),
          validator: validar,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.temSenha ? 'Trocar senha' : 'Criar senha'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.temSenha)
                _campo(
                    _atual,
                    'Senha atual',
                    (v) => (v == null || v.isEmpty)
                        ? 'Informe a senha atual'
                        : null),
              _campo(
                  _nova,
                  'Nova senha',
                  (v) => (v == null || v.length < 8)
                      ? 'Use 8 caracteres ou mais'
                      : null),
              _campo(_confirmar, 'Repita a nova senha',
                  (v) => v != _nova.text ? 'As senhas não conferem' : null),
              if (_erro != null)
                Text(_erro!, style: const TextStyle(color: AppColors.negative)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _carregando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _carregando ? null : _salvar,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: _carregando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Confirmação de excluir a conta: precisa digitar EXCLUIR.
class _DialogoExcluir extends StatefulWidget {
  const _DialogoExcluir();

  @override
  State<_DialogoExcluir> createState() => _DialogoExcluirState();
}

class _DialogoExcluirState extends State<_DialogoExcluir> {
  final _confirmacao = TextEditingController();
  bool _carregando = false;
  String? _erro;

  bool get _confirmado => _confirmacao.text.trim().toUpperCase() == 'EXCLUIR';

  @override
  void dispose() {
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _excluir() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await AppData.instance.excluirConta();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = mensagemErro(e);
          _carregando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    final casa = data.casa;
    // Admin que passou na regra = mora sozinho: a casa vai junto.
    final casaVaiJunto = casa != null && data.souAdmin;
    return AlertDialog(
      title: const Text('Excluir conta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              casaVaiJunto
                  ? 'A casa "${casa.nome}" e todos os gastos, pagamentos e '
                      'tarefas dela serão apagados junto com a sua conta.'
                  : casa != null
                      ? 'Nos gastos antigos da casa "${casa.nome}" você vai '
                          'aparecer como "Ex-morador", para as contas dos '
                          'outros continuarem certas.'
                      : 'Sua conta será apagada.',
            ),
            const SizedBox(height: 8),
            const Text('Isso não pode ser desfeito.',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmacao,
              enabled: !_carregando,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Digite EXCLUIR para confirmar'),
              onChanged: (_) => setState(() {}),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: const TextStyle(color: AppColors.negative)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _carregando ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _carregando || !_confirmado ? null : _excluir,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.negative,
              minimumSize: const Size(0, 44)),
          child: _carregando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Excluir'),
        ),
      ],
    );
  }
}
