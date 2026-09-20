import 'package:flutter/material.dart';

/// 信封图标目录（DESIGN.md §20 的 12 个图标）。
/// v1 用 Material 圆角描边图标近似设计稿的 2dp 圆头描边风格；
/// id 存库，后续如换成自定义 SVG 路径，只改本文件的图标映射。
class EnvelopeIconDef {
  const EnvelopeIconDef(this.id, this.icon);
  final String id;
  final IconData icon;
}

/// 12 个信封图标，顺序与设计稿一致
const List<EnvelopeIconDef> kEnvelopeIcons = [
  EnvelopeIconDef('food', Icons.restaurant_rounded), // 餐饮
  EnvelopeIconDef('transport', Icons.directions_bus_rounded), // 交通
  EnvelopeIconDef('daily', Icons.shopping_basket_rounded), // 日用
  EnvelopeIconDef('fun', Icons.sports_esports_rounded), // 娱乐
  EnvelopeIconDef('social', Icons.redeem_rounded), // 人情
  EnvelopeIconDef('saving', Icons.savings_rounded), // 储蓄
  EnvelopeIconDef('telecom', Icons.wifi_rounded), // 通讯
  EnvelopeIconDef('medical', Icons.medical_services_rounded), // 医疗
  EnvelopeIconDef('rent', Icons.home_rounded), // 房租
  EnvelopeIconDef('education', Icons.school_rounded), // 教育
  EnvelopeIconDef('travel', Icons.flight_rounded), // 旅行
  EnvelopeIconDef('pet', Icons.pets_rounded), // 宠物
];

/// 按 id 查图标，未知 id 回落到餐饮
IconData envelopeIconById(String id) => kEnvelopeIcons
    .firstWhere((d) => d.id == id, orElse: () => kEnvelopeIcons.first)
    .icon;
