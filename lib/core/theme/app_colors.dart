import 'package:flutter/material.dart';

/// The web's tailwind palette (frontend/tailwind.config.js): `slate` is the navy-black of the
/// brand UI and `amber` is the logo's gold.
class Slate {
  static const s50 = Color(0xFFF5F7FA), s100 = Color(0xFFECEFF4), s200 = Color(0xFFDADFE8), s300 = Color(0xFFB7C0CE);
  static const s400 = Color(0xFF8B96A8), s500 = Color(0xFF637087), s600 = Color(0xFF4A556B), s700 = Color(0xFF333D51);
  static const s800 = Color(0xFF1E2738), s900 = Color(0xFF0F1623), s950 = Color(0xFF090E18);
}

class Gold {
  static const g50 = Color(0xFFFBF7EE), g100 = Color(0xFFF6ECD4), g200 = Color(0xFFEDD8A8), g300 = Color(0xFFE3C37C);
  static const g400 = Color(0xFFDAB468), g500 = Color(0xFFD1A658), g600 = Color(0xFFB88D3F), g700 = Color(0xFF93702F);
}

/// Colour meaning for chips and figures. Mirrors the web's badge styles: emerald = done/approved,
/// amber = waiting, red = refused/overdue, sky = in motion, orange = on hold, neutral = draft/closed.
enum Tone { neutral, success, warning, danger, info, orange, accent }

/// Semantic colours for the current theme. Read with `context.pal`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg, card, muted, fg, fgMuted, fgSubtle, border, inputBorder;
  final Color accent, accentText, onAccent, primaryBtn, onPrimaryBtn;
  final Color success, warning, danger, info, orange;
  final bool dark;

  const AppPalette({
    required this.bg,
    required this.card,
    required this.muted,
    required this.fg,
    required this.fgMuted,
    required this.fgSubtle,
    required this.border,
    required this.inputBorder,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.primaryBtn,
    required this.onPrimaryBtn,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.orange,
    required this.dark,
  });

  /// index.css :root. Primary buttons are slate-900 with white text (web: `bg-slate-900 text-white`).
  static const light = AppPalette(
    bg: Slate.s50,
    card: Colors.white,
    muted: Slate.s100,
    fg: Slate.s900,
    fgMuted: Slate.s500,
    fgSubtle: Slate.s400,
    border: Slate.s200,
    inputBorder: Slate.s300,
    accent: Gold.g500,
    accentText: Gold.g700,
    onAccent: Slate.s950,
    primaryBtn: Slate.s900,
    onPrimaryBtn: Colors.white,
    success: Color(0xFF047857),
    warning: Gold.g700,
    danger: Color(0xFFB91C1C),
    info: Color(0xFF0369A1),
    orange: Color(0xFFC2410C),
    dark: false,
  );

  /// index.css .dark. Primary buttons are gold with near-black text (web: `dark:bg-amber-500 dark:text-slate-950`).
  static const darkPalette = AppPalette(
    bg: Slate.s950,
    card: Slate.s900,
    muted: Color(0xFF151D2B),
    fg: Color(0xFFE8ECF2),
    fgMuted: Slate.s400,
    fgSubtle: Slate.s500,
    border: Slate.s800,
    inputBorder: Slate.s700,
    accent: Gold.g500,
    accentText: Gold.g400,
    onAccent: Slate.s950,
    primaryBtn: Gold.g500,
    onPrimaryBtn: Slate.s950,
    success: Color(0xFF34D399),
    warning: Gold.g400,
    danger: Color(0xFFF87171),
    info: Color(0xFF38BDF8),
    orange: Color(0xFFFB923C),
    dark: true,
  );

  Color tone(Tone t) => switch (t) {
        Tone.neutral => fgMuted,
        Tone.success => success,
        Tone.warning => warning,
        Tone.danger => danger,
        Tone.info => info,
        Tone.orange => orange,
        Tone.accent => accentText,
      };

  /// Chip / badge fill for a tone (10% in light, 12% in dark, as `bg-x-50` / `bg-x-500/10`).
  Color toneFill(Tone t) => t == Tone.neutral ? muted : tone(t).withValues(alpha: dark ? 0.12 : 0.09);

  /// Chip / badge outline for a tone.
  Color toneBorder(Tone t) => t == Tone.neutral ? border : tone(t).withValues(alpha: dark ? 0.35 : 0.3);

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => t < 0.5 ? this : (other as AppPalette? ?? this);
}

extension PaletteContext on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>()!;
}
