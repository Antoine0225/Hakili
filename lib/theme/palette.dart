import 'package:flutter/material.dart';

/// Les couleurs de Hakili (reprises de config_systeme.py).
/// Utilisation dans un écran :  final p = Palette.de(context);  puis  p.cuivre, p.txtPrinc...
class Palette extends ThemeExtension<Palette> {
  final Color fond, panneau, panneau2, carte, saisie, bordure;
  final Color txtPrinc, txtDoux, txtGris, accent;
  final Color succes, alerte, danger;
  final Color menu, menuTxt, menuDoux, menuActif;
  final Color cuivre, cuivreSurvol, or;
  final Color neutre, survol, survol2, menuHover, menuLigne;
  final Color succesSurvol, dangerSurvol, alerteSurvol;
  final Color creme, iconeVert, iconeOr, courbe1, courbe2, voyantAttente;

  const Palette({
    required this.fond, required this.panneau, required this.panneau2,
    required this.carte, required this.saisie, required this.bordure,
    required this.txtPrinc, required this.txtDoux, required this.txtGris,
    required this.accent, required this.succes, required this.alerte,
    required this.danger, required this.menu, required this.menuTxt,
    required this.menuDoux, required this.menuActif, required this.cuivre,
    required this.cuivreSurvol, required this.or,
    required this.neutre, required this.survol, required this.survol2,
    required this.menuHover, required this.menuLigne,
    required this.succesSurvol, required this.dangerSurvol, required this.alerteSurvol,
    required this.creme, required this.iconeVert, required this.iconeOr,
    required this.courbe1, required this.courbe2, required this.voyantAttente,
  });

  static const clair = Palette(
    fond: Color(0xFFFAF8F5), panneau: Color(0xFFFFFFFF), panneau2: Color(0xFFF1EDE5),
    carte: Color(0xFFFBF9F4), saisie: Color(0xFFFFFFFF), bordure: Color(0xFFE8E2D7),
    txtPrinc: Color(0xFF123229), txtDoux: Color(0xFF4D5F56), txtGris: Color(0xFF6F7D75),
    accent: Color(0xFFB8651F), succes: Color(0xFF2F7D4F), alerte: Color(0xFFC2691F),
    danger: Color(0xFFB3372A), menu: Color(0xFF123229), menuTxt: Color(0xFFF4F1E6),
    menuDoux: Color(0xFFA9BDB0), menuActif: Color(0xFF516758), cuivre: Color(0xFFBC6B2D),
    cuivreSurvol: Color(0xFFA45A22), or: Color(0xFFB98A1E),
    neutre: Color(0xFFE3DDD0), survol: Color(0xFFE9E3D6), survol2: Color(0xFFDCD4C2),
    menuHover: Color(0xFF1D4136), menuLigne: Color(0xFF244035),
    succesSurvol: Color(0xFF256B42), dangerSurvol: Color(0xFF932C21), alerteSurvol: Color(0xFFA85817),
    creme: Color(0xFFFDF8EE), iconeVert: Color(0xFFEEF2EA), iconeOr: Color(0xFFFDF3DC),
    courbe1: Color(0xFF123229), courbe2: Color(0xFFA9A45C), voyantAttente: Color(0xFFA3AAA4),
  );

  static const sombre = Palette(
    fond: Color(0xFF0B1C18), panneau: Color(0xFF10221C), panneau2: Color(0xFF1A2F28),
    carte: Color(0xFF0D1F19), saisie: Color(0xFF0F211B), bordure: Color(0xFF1F342C),
    txtPrinc: Color(0xFFF4F1E6), txtDoux: Color(0xFFA4B5AA), txtGris: Color(0xFF8A9C91),
    accent: Color(0xFFE2B23C), succes: Color(0xFF4FB37A), alerte: Color(0xFFD18A26),
    danger: Color(0xFFE2574C), menu: Color(0xFF0D1E1B), menuTxt: Color(0xFFF3EFE2),
    menuDoux: Color(0xFF8FA397), menuActif: Color(0xFF3B4A3F), cuivre: Color(0xFFC4952F),
    cuivreSurvol: Color(0xFFD6A63C), or: Color(0xFFE2B23C),
    neutre: Color(0xFF2B4038), survol: Color(0xFF22392F), survol2: Color(0xFF2C453A),
    menuHover: Color(0xFF152A25), menuLigne: Color(0xFF1C2F29),
    succesSurvol: Color(0xFF3D9A66), dangerSurvol: Color(0xFFC9453B), alerteSurvol: Color(0xFFB87720),
    creme: Color(0xFF10221C), iconeVert: Color(0xFF1E382B), iconeOr: Color(0xFF2C301D),
    courbe1: Color(0xFF4FB37A), courbe2: Color(0xFFE6B03E), voyantAttente: Color(0xFF66766C),
  );

  /// Le style « carte papier » (skin_papier.py) : feuille ivoire, texte encre, identique en clair et en sombre.
  static const papier = Palette(
    fond: Color(0xFFFDFAF3), panneau: Color(0xFFFDFAF3), panneau2: Color(0xFFF2EDE0),
    carte: Color(0xFFF2EDE0), saisie: Color(0xFFFFFFFF), bordure: Color(0xFFE6DFCD),
    txtPrinc: Color(0xFF1A1F1C), txtDoux: Color(0xFF6F7065), txtGris: Color(0xFF8B8C80),
    accent: Color(0xFFB8651F), succes: Color(0xFF2F7D4F), alerte: Color(0xFFC2691F),
    danger: Color(0xFFB3372A), menu: Color(0xFF123229), menuTxt: Color(0xFFF4F1E6),
    menuDoux: Color(0xFFA9BDB0), menuActif: Color(0xFF516758), cuivre: Color(0xFFBC6B2D),
    cuivreSurvol: Color(0xFFA45A22), or: Color(0xFFB98A1E),
    neutre: Color(0xFFD9D2BF), survol: Color(0xFFECE6D6), survol2: Color(0xFFE0D8C4),
    menuHover: Color(0xFF1D4136), menuLigne: Color(0xFF244035),
    succesSurvol: Color(0xFF256B42), dangerSurvol: Color(0xFF932C21), alerteSurvol: Color(0xFFA85817),
    creme: Color(0xFFFDF8EE), iconeVert: Color(0xFFEEF2EA), iconeOr: Color(0xFFFDF3DC),
    courbe1: Color(0xFF123229), courbe2: Color(0xFFA9A45C), voyantAttente: Color(0xFFA3AAA4),
  );

  static Palette de(BuildContext context) => Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) =>
      other is Palette && t >= 0.5 ? other : this;
}

const String policeTitre = 'Georgia';
const String policeTexte = 'Segoe UI';

/// Fabrique le thème complet (clair ou sombre) à partir d'une palette.
ThemeData construireTheme(Palette p, Brightness luminosite) {
  return ThemeData(
    useMaterial3: true,
    brightness: luminosite,
    scaffoldBackgroundColor: p.fond,
    fontFamily: policeTexte,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.cuivre, brightness: luminosite,
      surface: p.panneau, primary: p.cuivre, onPrimary: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: p.panneau, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.bordure),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: p.saisie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.bordure)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.bordure)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.cuivre, width: 1.6)),
      labelStyle: TextStyle(color: p.txtDoux),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.cuivre, foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        animationDuration: const Duration(milliseconds: 160),
      ),
    ),
    // Douceur générale : survol discret, ondulation fine au clic, barre de défilement fine et arrondie.
    splashFactory: InkRipple.splashFactory,
    hoverColor: p.cuivre.withValues(alpha: 0.06),
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.standard,
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.hovered) ? 9 : 6),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.resolveWith((e) =>
          p.txtDoux.withValues(alpha: e.contains(WidgetState.hovered) ? 0.55 : 0.32)),
      crossAxisMargin: 2,
      interactive: true,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        animationDuration: const Duration(milliseconds: 160),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        animationDuration: const Duration(milliseconds: 160),
      ),
    ),
    tooltipTheme: TooltipThemeData(waitDuration: const Duration(milliseconds: 350)),
    dialogTheme: DialogThemeData(
      backgroundColor: p.panneau, elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
    ),
    extensions: [p],
  );
}
