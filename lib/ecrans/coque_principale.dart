import 'package:flutter/material.dart';

import '../securite/licence_locale.dart';
import '../session.dart';
import '../widgets/dialogues.dart';
import '../theme/palette.dart';
import '../widgets/entete_menu.dart';
import '../widgets/icones.dart';
import '../services/mise_a_jour.dart';
import '../cloud/service_cloud.dart';
import '../widgets/indicateur_cloud.dart';
import '../widgets/pastille_mise_a_jour.dart';
import 'ecran_accueil.dart';
import 'ecran_credits.dart';
import 'ecran_elevage.dart';
import 'ecran_expert_ia.dart';
import 'ecran_parametres.dart';
import 'ecran_previsions.dart';
import 'ecran_rapports.dart';
import 'ecran_resume_jour.dart';
import 'ecran_stocks.dart';
import 'ecran_ventes.dart';
import 'page_provisoire.dart';

/// Le cadre de toute l'application une fois connecté (équivalent de construire_armature_principale).
///  • Accueil et Paramètres : le menu latéral est visible.
///  • Dans un module : le menu glisse hors de l'écran, le module occupe tout l'espace et un bouton
///    « ← Vue d'ensemble » apparaît (comme dans le logiciel actuel).
class CoquePrincipale extends StatefulWidget {
  final VoidCallback onBasculerTheme;
  final Future<void> Function() onDeconnexionTotale;
  const CoquePrincipale({super.key, required this.onBasculerTheme, required this.onDeconnexionTotale});

  @override
  State<CoquePrincipale> createState() => _CoquePrincipaleState();
}

class _EntreeMenu {
  final String cle, libelle, icone;
  final bool visible, verrouille;
  const _EntreeMenu(this.cle, this.libelle, this.icone, this.visible, this.verrouille);
}

class _CoquePrincipaleState extends State<CoquePrincipale> {
  String _page = 'accueil';

  @override
  void dispose() {
    ServiceCloud.versionNomFerme.removeListener(_nomChange);
    MiseAJour.arreter();
    super.dispose();
  }

  void _nomChange() {
    if (mounted) setState(() {}); // le nom de la ferme a changé sur un autre PC
  }

  @override
  void initState() {
    super.initState();
    ServiceCloud.versionNomFerme.addListener(_nomChange);
    MiseAJour.demarrer(); // cherche une nouvelle version 6 secondes après l'ouverture, puis toutes les 3 heures
    // Mode « Compagne Hors-Ligne » : avertissement affiché une seule fois à l'ouverture
    if (Licence.messageHorsLigne.isNotEmpty) {
      final message = Licence.messageHorsLigne;
      Licence.messageHorsLigne = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Dialogues.avertissement(context, 'Mode Compagne Hors-Ligne', message);
      });
    }
  }

  static const _titres = {
    'previsions': 'Prévisions',
    'elevage': 'Élevage',
    'ventes': 'Ventes',
    'stocks': 'Stocks',
    'rapports': 'Rapports',
    'credits': 'Crédits',
    'expert_ia': 'Expert IA',
    'resume': 'Résumé du jour',
  };

  bool get _menuVisible => _page == 'accueil' || _page == 'parametres';

  List<_EntreeMenu> get _entrees {
    final patron = Session.estPatron;
    return [
      const _EntreeMenu('accueil', "Vue d'ensemble", 'accueil', true, false),
      _EntreeMenu('previsions', 'Prévisions', 'previsions', true, !patron),
      _EntreeMenu('elevage', 'Élevage', 'elevage', Session.peutVoirModule3, false),
      const _EntreeMenu('ventes', 'Ventes', 'ventes', true, false),
      _EntreeMenu('stocks', 'Stocks', 'stocks', patron, false),
      _EntreeMenu('rapports', 'Rapports', 'rapports', patron, false),
      _EntreeMenu('credits', 'Crédits', 'credits', patron, false),
      _EntreeMenu('resume', 'Résumé du jour', 'cloche', patron, false),
      _EntreeMenu('expert_ia', 'Expert IA', 'expert_ia', patron, false),
    ];
  }

  /// Point d'entrée UNIQUE de la navigation (menu, cartes de l'accueil, boutons rapides).
  void naviguer(String cle) {
    final patron = Session.estPatron;
    if (['previsions', 'stocks', 'rapports', 'credits', 'expert_ia', 'resume'].contains(cle) && !patron) {
      _accesRefuse('⚠️ Accès refusé. Cette section est réservée au Patron.');
      return;
    }
    if (cle == 'elevage' && !Session.peutVoirModule3) {
      _accesRefuse("⚠️ Accès refusé à la section Élevage.");
      return;
    }
    if (cle == _page) return;
    setState(() => _page = cle);
  }

  void _accesRefuse(String message) {
    final p = Palette.de(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        title: Row(children: [
          Icon(Icons.error_outline, color: p.danger),
          const SizedBox(width: 10),
          Text('Accès Restreint', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        ]),
        content: Text(message, style: TextStyle(color: p.txtPrinc)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  // ------------------------------------------------------------------ pages
  Widget _contenu() {
    switch (_page) {
      case 'accueil':
        return EcranAccueil(key: const ValueKey('accueil'), onNaviguer: naviguer);
      case 'parametres':
        return EcranParametres(
          key: const ValueKey('parametres'),
          onBasculerTheme: widget.onBasculerTheme,
          onRoleChange: () => setState(() {}),
          onDeconnexionTotale: widget.onDeconnexionTotale,
        );
      case 'previsions':
        return EcranPrevisions(key: const ValueKey('previsions'));
      case 'elevage':
        return EcranElevage(key: const ValueKey('elevage'));
      case 'rapports':
        return EcranRapports(key: const ValueKey('rapports'));
      case 'resume':
        return EcranResumeJour(key: const ValueKey('resume'));
      case 'expert_ia':
        return EcranExpertIa(key: const ValueKey('expert_ia'));
      case 'credits':
        return EcranCredits(key: const ValueKey('credits'));
      case 'stocks':
        return EcranStocks(key: const ValueKey('stocks'));
      case 'ventes':
        return EcranVentes(key: const ValueKey('ventes'));
      default:
        return PageProvisoire(
            key: ValueKey(_page), titre: _titres[_page] ?? _page, message: 'Ce module sera reconstruit prochainement.');
    }
  }

  // ------------------------------------------------------------------ affichage
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Scaffold(
      backgroundColor: p.fond,
      body: Stack(
        children: [
          // La zone de travail change de taille d'un coup (aucun recalcul pendant l'animation)...
          Positioned.fill(
            left: _menuVisible ? largeurMenu : 0,
            child: _zoneDroite(p),
          ),
          // ...et c'est le menu qui glisse en douceur par-dessus (simple déplacement d'image, très léger).
          Positioned(
            left: 0, top: 0, bottom: 0, width: largeurMenu,
            child: IgnorePointer(
              ignoring: !_menuVisible,
              child: AnimatedSlide(
                offset: _menuVisible ? Offset.zero : const Offset(-1, 0),
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeInOutCubic,
                child: RepaintBoundary(child: _menu(p)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoneDroite(Palette p) {
    final enModule = !_menuVisible;
    return Column(
      children: [
        // barre du haut : pastille Cloud à droite
        SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 26, top: 5),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                PastilleMiseAJour(),
                SizedBox(width: 10),
                IndicateurCloud(),
              ]),
            ),
          ),
        ),
        // en-tête de module : « ← Vue d'ensemble » + titre (apparaît / s'efface en fondu)
        SizedBox(
          height: enModule ? 64 : 0,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            layoutBuilder: (actuel, precedents) => Stack(
              alignment: Alignment.topLeft,
              children: [...precedents, if (actuel != null) actuel],
            ),
            child: enModule
                ? SizedBox(
                    key: const ValueKey('entete'),
                    height: 64,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Row(children: [
                        SizedBox(
                          width: 140, height: 34,
                          child: OutlinedButton.icon(
                            onPressed: () => naviguer('accueil'),
                            icon: IconeFine('chevron_gauche', couleur: p.txtPrinc, taille: 14),
                            label: const Text("Vue d'ensemble",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: p.panneau, foregroundColor: p.txtPrinc,
                              side: BorderSide(color: p.bordure),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(_titres[_page] ?? '',
                            style: TextStyle(fontFamily: policeTitre, fontSize: 21,
                                fontWeight: FontWeight.bold, color: p.txtPrinc)),
                      ]),
                    ),
                  )
                : const SizedBox(key: ValueKey('vide'), width: double.infinity, height: 0),
          ),
        ),
        // zone de travail : fondu croisé doux, la nouvelle page monte très légèrement
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 8, 26, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 340),
              switchInCurve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
              switchOutCurve: const Interval(0, 0.6, curve: Curves.easeIn),
              transitionBuilder: (enfant, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.018), end: Offset.zero).animate(anim),
                  child: enfant,
                ),
              ),
              layoutBuilder: (actuel, precedents) => Stack(
                fit: StackFit.expand,
                children: [...precedents, if (actuel != null) actuel],
              ),
              child: RepaintBoundary(key: ValueKey('rb$_page'), child: _contenu()),
            ),
          ),
        ),
        _pied(p),
      ],
    );
  }

  // ------------------------------------------------------------------ pied de page
  Widget _pied(Palette p) {
    const contact = '📞 Tél : +223 60 51 10 46\n✉️ Email : antoinemalle6051@gmail.com\n🔥 Assistance Premium Antoine Software';
    Widget lien(Widget enfant) => Tooltip(
          message: contact,
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
              color: p.panneau, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.accent, width: 2)),
          textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc),
          child: MouseRegion(cursor: SystemMouseCursors.click, child: enfant),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("© Antoine Software — Édition Premium — Protégé par Droits d'Auteur",
            style: TextStyle(fontSize: 11, color: p.txtDoux)),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          lien(Row(mainAxisSize: MainAxisSize.min, children: [
            IconeFine('telephone', couleur: p.accent, taille: 14),
            Text(" Besoin d'assistance ?", style: TextStyle(fontSize: 11, color: p.accent)),
          ])),
          Text('   |   ', style: TextStyle(fontSize: 11, color: p.txtGris)),
          lien(Text('Contactez le développeur', style: TextStyle(fontSize: 11, color: p.accent))),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------------ menu latéral
  static String _titreCase(String t) => t
      .toLowerCase()
      .split(' ')
      .map((m) => m.isEmpty ? m : m[0].toUpperCase() + m.substring(1))
      .join(' ');

  Widget _menu(Palette p) {
    final nom = Session.nomFerme.trim().isEmpty ? 'ANTOINE SOFTWARE' : Session.nomFerme.trim();
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final patron = Session.estPatron;
    final nomAffiche = _titreCase(nom);
    return Container(
      width: largeurMenu,
      color: p.menu,
      child: Column(
        children: [
          EnteteMenu(nomFerme: nom),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(13, 4, 13, 0),
              child: Column(children: [
                for (final e in _entrees.where((e) => e.visible))
                  _BoutonMenu(
                    libelle: e.libelle,
                    icone: e.verrouille ? 'cadenas' : e.icone,
                    couleurIcone: e.verrouille ? const Color(0xFF8FA397) : const Color(0xFFF4F1E6),
                    couleurTexte: e.verrouille ? p.menuDoux : p.menuTxt,
                    actif: _page == e.cle,
                    onTap: () => naviguer(e.cle),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
                  child: Container(height: 1, color: p.menuLigne),
                ),
                _BoutonMenu(
                  libelle: 'Paramètres', icone: 'parametres', couleurIcone: const Color(0xFFF4F1E6),
                  couleurTexte: p.menuTxt, actif: _page == 'parametres', onTap: () => naviguer('parametres'),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Column(children: [
              // carte profil
              Material(
                color: p.menu,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.menuLigne)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => naviguer('parametres'),
                  child: SizedBox(
                    height: 64,
                    child: Row(children: [
                      const SizedBox(width: 12),
                      Container(
                        width: 36, height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sombre ? const Color(0xFF2C4333) : const Color(0xFF40664A)),
                        child: Text(nom[0].toUpperCase(),
                            style: TextStyle(fontFamily: policeTitre, fontSize: 16,
                                fontWeight: FontWeight.bold, color: p.menuTxt)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nomAffiche.length < 18 ? nomAffiche : '${nomAffiche.substring(0, 16)}…',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: policeTexte, fontSize: 12,
                                    fontWeight: FontWeight.bold, color: p.menuTxt)),
                            Text('Espace de travail',
                                style: TextStyle(fontFamily: policeTexte, fontSize: 10, color: p.menuDoux)),
                          ],
                        ),
                      ),
                      const IconeFine('chevron_bas', couleur: Color(0xFFA9BDB0), taille: 14),
                      const SizedBox(width: 10),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // badge de session
              SizedBox(
                width: double.infinity, height: 40,
                child: FilledButton.icon(
                  onPressed: () => naviguer('parametres'),
                  icon: const IconeFine('session', couleur: Colors.white, taille: 16),
                  label: Text(patron ? 'Session Patron' : 'Session Ouvrier',
                      style: const TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: patron ? p.cuivre : p.alerte,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ).copyWith(
                    overlayColor: WidgetStatePropertyAll(
                        (patron ? p.cuivreSurvol : p.alerteSurvol).withValues(alpha: 0.55)),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Un bouton du menu : fond transparent, vert doux au survol, vert actif quand la page est ouverte.
class _BoutonMenu extends StatefulWidget {
  final String libelle, icone;
  final Color couleurIcone, couleurTexte;
  final bool actif;
  final VoidCallback onTap;
  const _BoutonMenu({
    required this.libelle, required this.icone, required this.couleurIcone,
    required this.couleurTexte, required this.actif, required this.onTap,
  });

  @override
  State<_BoutonMenu> createState() => _BoutonMenuState();
}

class _BoutonMenuState extends State<_BoutonMenu> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final fond = widget.actif ? p.menuActif : (_survol ? p.menuHover : Colors.transparent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _survol = true),
        onExit: (_) => setState(() => _survol = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 42,
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              IconeFine(widget.icone, couleur: widget.couleurIcone, taille: 20),
              Expanded(
                child: Text('  ${widget.libelle}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: policeTitre, fontSize: 15, color: widget.couleurTexte)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
