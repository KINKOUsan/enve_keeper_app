// 信封编辑的公共选择件 — 图标格与色点（新建/编辑信封弹层共用）。
import 'package:flutter/material.dart';

import '../../theme/envelope_icons.dart';
import '../../theme/tokens.dart';

// 图标选择格：44dp，选中 = 信封主色实底 + 白图标
class IconCell extends StatelessWidget {
  const IconCell({
    super.key,
    required this.def,
    required this.colorId,
    required this.selected,
    required this.onTap,
  });

  final EnvelopeIconDef def;
  final String colorId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = envelopeColorById(colorId);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? color.main : T.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          def.icon,
          size: 20,
          color: selected ? Colors.white : const Color(0xFF6E675C),
        ),
      ),
    );
  }
}

// 色点：36dp 圆，选中带描边环
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final EnvelopeColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.main,
          border: selected ? Border.all(color: T.textPrimary, width: 2) : null,
        ),
      ),
    );
  }
}
