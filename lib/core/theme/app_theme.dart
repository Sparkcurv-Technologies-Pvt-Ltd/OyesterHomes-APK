import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// Radii from the web (`--radius: 0.625rem`): cards 10 (rounded-lg), buttons 8, inputs 8, sheets 14.
class Radii {
  static const card = 10.0;
  static const control = 8.0;
  static const sheet = 14.0;
}

const _tabular = [FontFeature.tabularFigures()];

/// Tabular figures for any number people compare (web: `tabular-nums` on every table and figure).
TextStyle tabular(TextStyle? base) => (base ?? const TextStyle()).copyWith(fontFeatures: _tabular);

/// The JetBrains Mono used on the web for codes (company chip, gear numbers, refs).
const monoFamily = 'JetBrainsMono';

class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.darkPalette, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: p.primaryBtn,
      onPrimary: p.onPrimaryBtn,
      secondary: p.accent,
      onSecondary: p.onAccent,
      error: p.danger,
      onError: Colors.white,
      surface: p.card,
      onSurface: p.fg,
      surfaceContainerHighest: p.muted,
      surfaceContainerHigh: p.muted,
      surfaceContainer: p.card,
      surfaceContainerLow: p.card,
      surfaceContainerLowest: p.card,
      onSurfaceVariant: p.fgMuted,
      outline: p.inputBorder,
      outlineVariant: p.border,
      tertiary: p.info,
      onTertiary: Colors.white,
    );

    TextStyle t(double size, FontWeight w, {double? height, double ls = 0, Color? c}) =>
        TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: w, height: height, letterSpacing: ls, color: c ?? p.fg);

    // Headings: Inter bold with tight tracking (web .font-heading + tracking-tight).
    final text = TextTheme(
      headlineLarge: t(28, FontWeight.w700, height: 1.15, ls: -0.6),
      headlineMedium: t(24, FontWeight.w700, height: 1.15, ls: -0.5),
      headlineSmall: t(20, FontWeight.w700, height: 1.2, ls: -0.4),
      titleLarge: t(18, FontWeight.w600, height: 1.25, ls: -0.3),
      titleMedium: t(15.5, FontWeight.w600, height: 1.3, ls: -0.1),
      titleSmall: t(14, FontWeight.w600, height: 1.3),
      bodyLarge: t(15.5, FontWeight.w400, height: 1.45),
      bodyMedium: t(14, FontWeight.w400, height: 1.45),
      bodySmall: t(12.5, FontWeight.w400, height: 1.4, c: p.fgMuted),
      labelLarge: t(14, FontWeight.w600, ls: 0.1),
      labelMedium: t(12, FontWeight.w600, c: p.fgMuted),
      labelSmall: t(10.5, FontWeight.w600, ls: 1.6, c: p.fgMuted),
    );

    OutlineInputBorder ib(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.control), borderSide: BorderSide(color: c, width: w));

    final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control));
    final btnText = t(14, FontWeight.w700, ls: 0.3);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: 'Inter',
      textTheme: text,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.border,
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: p.card,
        foregroundColor: p.fg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle: t(17, FontWeight.w700, ls: -0.3),
        shape: Border(bottom: BorderSide(color: p.border)),
        systemOverlayStyle: (p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: p.card,
              systemNavigationBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
            ),
      ),
      cardTheme: CardTheme(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card), side: BorderSide(color: p.border)),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primaryBtn,
          foregroundColor: p.onPrimaryBtn,
          disabledBackgroundColor: p.primaryBtn.withValues(alpha: 0.4),
          disabledForegroundColor: p.onPrimaryBtn.withValues(alpha: 0.8),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: btnShape,
          textStyle: btnText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primaryBtn,
          foregroundColor: p.onPrimaryBtn,
          elevation: 0,
          minimumSize: const Size(64, 48),
          shape: btnShape,
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.fg,
          side: BorderSide(color: p.inputBorder),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: btnShape,
          textStyle: t(14, FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accentText,
          minimumSize: const Size(48, 44),
          shape: btnShape,
          textStyle: t(14, FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: p.fgMuted, minimumSize: const Size(44, 44))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primaryBtn,
        foregroundColor: p.onPrimaryBtn,
        elevation: 3,
        highlightElevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        extendedTextStyle: btnText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.dark ? Slate.s900 : Colors.white,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: t(14.5, FontWeight.w400, c: p.fgSubtle),
        labelStyle: t(14, FontWeight.w500, c: p.fgMuted),
        floatingLabelStyle: t(14, FontWeight.w600, c: p.accentText),
        helperStyle: t(12, FontWeight.w400, c: p.fgMuted),
        errorStyle: t(12, FontWeight.w500, c: p.danger),
        prefixIconColor: p.fgMuted,
        suffixIconColor: p.fgMuted,
        border: ib(p.inputBorder),
        enabledBorder: ib(p.inputBorder),
        disabledBorder: ib(p.border),
        focusedBorder: ib(p.accent, 2),
        errorBorder: ib(p.danger),
        focusedErrorBorder: ib(p.danger, 2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.card,
        selectedColor: p.primaryBtn,
        disabledColor: p.muted,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: t(13, FontWeight.w600, c: p.fgMuted),
        secondaryLabelStyle: t(13, FontWeight.w700, c: p.onPrimaryBtn),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      tabBarTheme: TabBarTheme(
        tabAlignment: TabAlignment.start,
        labelColor: p.fg,
        unselectedLabelColor: p.fgMuted,
        labelStyle: t(12, FontWeight.w700, ls: 1.2),
        unselectedLabelStyle: t(12, FontWeight.w600, ls: 1.2),
        indicatorColor: p.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: p.border,
        overlayColor: WidgetStatePropertyAll(p.muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: p.accent.withValues(alpha: p.dark ? 0.16 : 0.2),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(size: 23, color: s.contains(WidgetState.selected) ? p.accentText : p.fgMuted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? t(11.5, FontWeight.w700, c: p.fg)
            : t(11.5, FontWeight.w500, c: p.fgMuted)),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent, width: 304),
      listTileTheme: ListTileThemeData(
        iconColor: p.fgMuted,
        textColor: p.fg,
        minVerticalPadding: 10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: t(14.5, FontWeight.w600),
        subtitleTextStyle: t(12.5, FontWeight.w400, c: p.fgMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.card,
        showDragHandle: true,
        dragHandleColor: p.inputBorder,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet), side: BorderSide(color: p.border)),
        titleTextStyle: t(18, FontWeight.w700, ls: -0.3),
        contentTextStyle: t(14, FontWeight.w400, height: 1.45, c: p.fgMuted),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card), side: BorderSide(color: p.border)),
        textStyle: t(14, FontWeight.w500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.dark ? Slate.s800 : Slate.s900,
        contentTextStyle: t(14, FontWeight.w500, c: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.muted, circularTrackColor: p.muted),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.fgMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.muted),
        trackOutlineColor: WidgetStatePropertyAll(p.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: BorderSide(color: p.inputBorder, width: 1.5),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.inputBorder)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.card,
          foregroundColor: p.fgMuted,
          selectedBackgroundColor: p.primaryBtn,
          selectedForegroundColor: p.onPrimaryBtn,
          side: BorderSide(color: p.inputBorder),
          textStyle: t(13, FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.dark ? Slate.s950 : Slate.s900,
        headerForegroundColor: Colors.white,
        todayBorder: BorderSide(color: p.accent),
        dayBackgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : null),
        dayForegroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : null),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: p.accentText),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.fgMuted),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: p.fgMuted,
        collapsedIconColor: p.fgMuted,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
    );
  }
}
