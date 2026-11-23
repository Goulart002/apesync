import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../routes.dart';
import '../theme.dart';

/// Card branco com borda, raio 16 (padrão de todos os cards do app).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.card,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: border ?? Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Rótulo acima de um campo de formulário.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.muted)),
      );
}

/// Botão quadrado 40x40 com ícone (voltar, fechar, notificações...).
class SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const SquareIconButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
            width: 40, height: 40, child: Icon(icon, size: 22)),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  final Morador morador;
  final double size;
  const Avatar(this.morador, {super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: morador.color,
      child: Text(
        morador.inicial,
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.4),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ),
        ],
      ),
    );
  }
}

/// Linha de gasto usada no Início e na lista de Gastos.
class GastoTile extends StatelessWidget {
  final Gasto gasto;
  const GastoTile(this.gasto, {super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;
    final pagador = data.nomeDe(gasto.pagoPorId);
    final minhaParte = gasto.parteDe(data.euId);
    final euPaguei = gasto.pagoPorId == data.euId;

    final String detalhe;
    final Color corDetalhe;
    if (euPaguei) {
      detalhe = 'te devem ${formatarReais(gasto.valorCentavos - minhaParte)}';
      corDetalhe = AppColors.positive;
    } else {
      detalhe = 'sua parte ${formatarReais(minhaParte)}';
      corDetalhe = AppColors.muted;
    }

    return InkWell(
      // Toque no gasto abre a edição (UPDATE / DELETE).
      onTap: () =>
          Navigator.pushNamed(context, Rotas.novoGasto, arguments: gasto),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: gasto.categoria.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(gasto.categoria.icon,
                color: gasto.categoria.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gasto.descricao,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    gasto.recorrenciaId != null
                        ? '$pagador pagou · fixo'
                        : '$pagador pagou',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatarReais(gasto.valorCentavos),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detalhe,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: corDetalhe)),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

/// Card com uma lista de gastos separados por divisória.
class GastosCard extends StatelessWidget {
  final List<Gasto> gastos;
  const GastosCard(this.gastos, {super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < gastos.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            GastoTile(gastos[i]),
          ],
        ],
      ),
    );
  }
}

/// Card pequeno de estatística (rótulo + valor).
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  const StatCard(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Logo do app (quadrado verde com ícone de casa).
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.cottage_outlined,
          color: Colors.white, size: size * 0.55),
    );
  }
}
