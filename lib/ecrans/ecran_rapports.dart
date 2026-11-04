import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/bilans_repo.dart';
import '../data/ventes_repo.dart';
import '../metier/analyse_rapports.dart';
import '../services/excel_rapports.dart';
import '../services/pdf_banque.dart';
import '../services/pdf_marge.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogue_periode.dart';
import '../widgets/dialogues.dart';
import '../widgets/graphique_barres.dart';
import '../widgets/mise_en_page_module.dart';
import '../widgets/toast.dart';
import 'dialogue_dossier_banque.dart';
import 'rapport_flash.dart';

/// Module Rapports (« Marge & Bénéfice du Boss ») : à gauche la saisie des charges du mois et les actions,
/// à droite les résultats (indicateurs, graphiques, comparaison) ou les archives des bilans.
class EcranRapports extends StatefulWidget {
  const EcranRapports({super.key});

  @override
  State<EcranRapports> createState() => _EcranRapportsState();
}

class _EcranRapportsState extends State<EcranRapports> {
  final _revenu = TextEditingController();
  final _loyer = TextEditingController();
  final _elec = TextEditingController();
  final _transport = TextEditingController();
  final _salaires = TextEditingController();
  final _divers = TextEditingController();

  List<Vente> _ventes = [];
  RevenuCaisse? _revenuMois;
  double _revenuAutoInit = 0;
  String? _erreurChargement;

  BilanMarge? _bilan;
  ResultatFinancier? _res;
  SynthesePeriodes? _synthese;
  String? _sigCalcul; // empreinte de la saisie au moment du calcul : détecte un bilan devenu obsolète

  bool _voirArchives = false;
  List<BilanArchive> _archives = [];
  String _filtreArchives = 'tous';
  String _rechercheArchives = '';
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    for (final c in [_revenu, _loyer, _elec, _transport, _salaires, _divers]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ données
  static String _f(num v) => fmtF(v, unite: 'FCFA');
  static String _pct(double v) => '${v.toStringAsFixed(1)} %';
  static String _texteSaisie(double v) => milliersAnglais(v).replaceAll(',', ' ');

  DateTime get _debutMois {
    final n = DateTime.now();
    return DateTime(n.year, n.month, 1);
  }

  DateTime get _finAujourdhui {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
  }

  Future<void> _initialiser() async {
    try {
      final v = await VentesRepo.toutes();
      final a = await BilansRepo.archives();
      final r = VentesRepo.revenuPeriode(v, _debutMois, _finAujourdhui);
      if (!mounted) return;
      setState(() {
        _ventes = v;
        _archives = a;
        _revenuMois = r;
        _revenuAutoInit = r.beneficePur;
        _revenu.text = _texteSaisie(r.beneficePur);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreurChargement = "Impossible de lire les ventes de la Caisse : $e");
    }
  }

  // ------------------------------------------------------------------ saisie et validation
  MontantLu _lireRevenu() => AnalyseRapports.lireMontant(_revenu.text, negatifPermis: true, videPermis: false);
  MontantLu _lireCharge(TextEditingController c) => AnalyseRapports.lireMontant(c.text);

  List<String> _erreursSaisie() {
    final e = <String>[];
    final r = _lireRevenu();
    if (!r.valide) e.add('Bénéfice pur de la Caisse : ${r.erreur}');
    final champs = {
      'Loyer': _loyer, 'Électricité & Énergie': _elec, 'Transport & Logistique': _transport,
      "Salaires & Main d'œuvre": _salaires, 'Divers & Imprévus': _divers,
    };
    champs.forEach((nom, c) {
      final l = _lireCharge(c);
      if (!l.valide) e.add('$nom : ${l.erreur}');
    });
    return e;
  }

  String _signature() {
    String s(MontantLu m) => m.valeur?.toStringAsFixed(2) ?? 'x';
    return [
      s(_lireRevenu()), s(_lireCharge(_loyer)), s(_lireCharge(_elec)), s(_lireCharge(_transport)), s(_lireCharge(_salaires)), s(_lireCharge(_divers)),
    ].join('|');
  }

  bool get _obsolete => _bilan != null && _sigCalcul != _signature();

  Future<void> _calculer() async {
    if (_occupe) return;
    final erreurs = _erreursSaisie();
    if (erreurs.isNotEmpty) {
      await Dialogues.avertissement(context, 'Saisie à corriger',
          'Corrigez les points suivants avant de calculer :\n\n${erreurs.map((e) => '• $e').join('\n')}');
      return;
    }
    setState(() => _occupe = true);
    try {
      var ca = _lireRevenu().valeur!;
      final loyer = _lireCharge(_loyer).valeur!, elec = _lireCharge(_elec).valeur!, transport = _lireCharge(_transport).valeur!;
      final salaires = _lireCharge(_salaires).valeur!, divers = _lireCharge(_divers).valeur!;
      final etaitAuto = (ca - _revenuAutoInit).abs() <= 1.0; // la personne n'a pas touché au revenu pré-rempli

      // On relit toujours les ventes : le bilan ne doit jamais reposer sur des chiffres périmés.
      final ventes = await VentesRepo.toutes();
      final archives = await BilansRepo.archives();
      if (!mounted) return;
      final n = DateTime.now();
      final detail = VentesRepo.revenuPeriode(ventes, _debutMois, _finAujourdhui);
      var actualise = false;
      if (etaitAuto) {
        final neuf = detail.beneficePur.roundToDouble();
        actualise = (neuf - ca).abs() > 0.5;
        ca = neuf;
        _revenu.text = _texteSaisie(ca);
      }
      _revenuAutoInit = detail.beneficePur;
      final modifie = !etaitAuto;
      final total = loyer + elec + transport + salaires + divers;
      final res = ResultatFinancier.calculer(benefice: ca, charges: total, caBrut: detail.caBrut, coutAchat: detail.coutAchat);
      final synthese = AnalyseRapports.construire(
          ventes: ventes, archives: archives, debut: _debutMois, fin: _finAujourdhui, res: res);
      setState(() {
        _ventes = ventes;
        _archives = archives;
        _revenuMois = detail;
        _voirArchives = false;
        _res = res;
        _synthese = synthese;
        _bilan = BilanMarge(
          ca: ca, loyer: loyer, elec: elec, transport: transport, salaires: salaires, divers: divers,
          totalCharges: total, netPoche: res.net, margePct: res.margePct,
          periode: AnalyseRapports.cleMois(n), revenuModifie: modifie, detailCaisse: modifie ? null : detail,
        );
        _sigCalcul = _signature();
      });
      if (actualise) {
        Toast.afficher(context, 'Revenu actualisé avec les dernières ventes de la Caisse.', couleur: Palette.de(context).succes);
      }
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur de calcul', "Le bilan n'a pas pu être calculé : $e");
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Vérifie qu'un bilan existe ET correspond à la saisie actuelle ; propose de recalculer sinon.
  Future<bool> _assurerBilanAJour(String action) async {
    if (_bilan == null) {
      await Dialogues.avertissement(context, 'Bilan manquant',
          "Calculez d'abord le bénéfice du mois (bouton « Calculer le résultat ») avant de $action.");
      return false;
    }
    if (_obsolete) {
      final ok = await Dialogues.confirmer(
          context,
          'Montants modifiés',
          'Vous avez modifié des montants depuis le dernier calcul : le bilan affiché ne correspond plus à votre saisie.\n\n'
          'Recalculer maintenant avant de $action ?',
          oui: 'Recalculer', non: 'Annuler');
      if (!ok || !mounted) return false;
      await _calculer();
      return mounted && _bilan != null && !_obsolete;
    }
    return true;
  }

  // ------------------------------------------------------------------ actions
  Future<void> _archiver() async {
    if (_occupe) return;
    if (!await _assurerBilanAJour('archiver')) return;
    if (!mounted) return;
    final b = _bilan!;
    final existantes = await BilansRepo.archives();
    if (!mounted) return;
    final doublons = existantes.where((a) => a.periode.trim() == b.periode).toList();
    final avertDoublon = doublons.isEmpty
        ? ''
        : '\n\n⚠️ Un bilan de cette période existe déjà (archivé le ${doublons.first.dateArchivage}, '
            'net : ${_f(doublons.first.net)}). Un deuxième enregistrement sera créé.';
    final ok = await Dialogues.confirmer(
        context,
        'Archiver ce bilan ?',
        'Période : ${AnalyseRapports.libelleMois(b.periode)}\n'
        'Bénéfice pur retenu : ${_f(b.ca)}\n'
        'Charges totales : ${_f(b.totalCharges)}\n'
        'Bénéfice net : ${_f(b.netPoche)} (${_pct(b.margePct)})$avertDoublon',
        oui: 'Archiver', non: 'Annuler');
    if (!ok || !mounted) return;
    setState(() => _occupe = true);
    try {
      final r = await BilansRepo.archiver(b);
      if (!mounted) return;
      final p = Palette.de(context);
      if (r.startsWith('erreur:')) {
        Dialogues.erreur(context, 'Erreur', "Impossible d'enregistrer le bilan localement : ${r.substring(7)}");
      } else if (r == 'cloud') {
        Toast.afficher(context, '🔥 Bilan archivé dans le Cloud !', couleur: p.succes);
      } else if (r == 'local') {
        Dialogues.avertissement(context, 'Archivé localement',
            "💾 Le bilan est sauvegardé sur ce PC, mais l'envoi vers Supabase a échoué (il sera visible dans vos archives locales).");
      } else {
        Dialogues.avertissement(context, 'Archivé localement',
            "💾 Le bilan est sauvegardé sur ce PC (pas d'accès Internet pour l'instant).");
      }
      if (!r.startsWith('erreur:')) {
        final a = await BilansRepo.archives();
        if (mounted) setState(() => _archives = a);
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _ouvrirArchives() async {
    final a = await BilansRepo.archives();
    if (mounted) {
      setState(() {
        _archives = a;
        _voirArchives = true;
      });
    }
  }

  Future<void> _exporterPdf() async {
    if (_occupe) return;
    if (!await _assurerBilanAJour('exporter en PDF')) return;
    if (!mounted) return;
    final b = _bilan!;
    final periode = await choisirPeriode(context,
        titre: '📅 PÉRIODE DU BILAN DE MARGE', texteBouton: '📄 Générer le PDF', moisCourantParDefaut: true);
    if (periode == null || !mounted) return;
    setState(() => _occupe = true);
    try {
      final ok = await PdfMarge.exporter(b, _ventes, periode.debut, periode.fin, periode.texteDebut, periode.texteFin);
      if (ok && mounted) Toast.afficher(context, '🔥 Bilan exporté et classé !', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', "Détails de l'exportation : $e");
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _exporterExcel() async {
    if (_occupe) return;
    if (!await _assurerBilanAJour('exporter en Excel')) return;
    if (!mounted) return;
    setState(() => _occupe = true);
    try {
      final archives = await BilansRepo.archives();
      final ok = await ExcelRapports.exporter(
          bilan: _bilan!, res: _res!, synthese: _synthese!, archives: archives, nomFerme: Session.nomFerme);
      if (ok && mounted) Toast.afficher(context, 'Classeur Excel enregistré avec succès.', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur Excel', 'Impossible de créer le classeur : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _dossierBanque() async {
    final choix = await choisirDossierBanque(context);
    if (choix == null || !mounted) return;
    try {
      final ok = await PdfBanque.exporter(choix);
      if (ok && mounted) Toast.afficher(context, '🏦 Dossier pour la banque enregistré !', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', "Détails de l'exportation : $e");
    }
  }

  void _reprendreCharges(BilanArchive a) {
    final somme = a.loyer + a.elec + a.transport + a.salaires + a.divers;
    if (somme <= 0) {
      Dialogues.info(context, 'Détail indisponible',
          "Ce bilan (${AnalyseRapports.libelleMois(a.periode)}) a été archivé sans le détail des charges : "
          "seul le total (${_f(a.totalCharges)}) est connu.");
      return;
    }
    setState(() {
      _loyer.text = a.loyer > 0 ? _texteSaisie(a.loyer) : '';
      _elec.text = a.elec > 0 ? _texteSaisie(a.elec) : '';
      _transport.text = a.transport > 0 ? _texteSaisie(a.transport) : '';
      _salaires.text = a.salaires > 0 ? _texteSaisie(a.salaires) : '';
      _divers.text = a.divers > 0 ? _texteSaisie(a.divers) : '';
      _voirArchives = false;
    });
    Toast.afficher(context, 'Charges de ${AnalyseRapports.libelleMois(a.periode)} reprises : cliquez sur « Calculer le résultat ».',
        couleur: Palette.de(context).succes, dureeMs: 3200);
  }

  // ================================================================== construction
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return MiseEnPageModule(
      droitePapier: true,
      gauche: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.bordure)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: p.cuivre.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.insights_rounded, color: p.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('RAPPORTS FINANCIERS',
                    style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold, color: p.accent)),
                const SizedBox(height: 2),
                Text('Bilan du mois en cours : ${_libelleMoisCourant()}\nBasé sur les ventes de la Caisse et vos charges.',
                    style: TextStyle(fontSize: 11, color: p.txtDoux)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(child: _saisie(p)),
          ),
        ),
      ]),
      droite: _bilanOuArchives(Palette.papier),
    );
  }

  String _libelleMoisCourant() {
    final n = DateTime.now();
    return '${moisNomsRapport[n.month - 1]} ${n.year} (jusqu\'au ${n.day})';
  }

  // ------------------------------------------------------------------ colonne de gauche
  Widget _titreSection(Palette p, IconData icone, String texte, Color couleur, {double haut = 14}) => Padding(
        padding: EdgeInsets.fromLTRB(15, haut, 15, 8),
        child: Row(children: [
          Icon(icone, size: 16, color: couleur),
          const SizedBox(width: 7),
          Text(texte, style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: couleur)),
        ]),
      );

  Widget _champMontant(Palette p, TextEditingController c, String label, IconData icone,
      {bool negatifOk = false, bool obligatoire = false}) {
    final lu = AnalyseRapports.lireMontant(c.text, negatifPermis: negatifOk, videPermis: !obligatoire);
    final vide = c.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.txtDoux)),
        ),
        TextField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: true, signed: negatifOk),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 .,\-\u00A0\u202F]'))],
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '0',
            isDense: true,
            prefixIcon: Icon(icone, size: 17),
            suffixText: 'FCFA',
            errorText: lu.erreur,
            helperText: (lu.valide && !vide && lu.valeur != 0) ? '= ${_f(lu.valeur!)}' : null,
          ),
        ),
      ]),
    );
  }

  Widget _saisie(Palette p) {
    final r = _revenuMois;
    final revenuLu = _lireRevenu();
    final ecartAuto = revenuLu.valide && r != null && (revenuLu.valeur! - r.beneficePur).abs() > 1.0;
    final charges = [_loyer, _elec, _transport, _salaires, _divers].map(_lireCharge).toList();
    final chargesOk = charges.every((c) => c.valide);
    final totalSaisi = chargesOk ? charges.fold<double>(0, (s, c) => s + c.valeur!) : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreSection(p, Icons.south_west_rounded, 'REVENUS', p.succes, haut: 16),
      if (_erreurChargement != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
          child: Text('⚠️ $_erreurChargement', style: TextStyle(fontSize: 11, color: p.danger)),
        ),
      _champMontant(p, _revenu, 'Bénéfice pur de la Caisse du mois', Icons.payments_outlined, negatifOk: true, obligatoire: true),
      if (r != null)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(15, 0, 15, 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(9), border: Border.all(color: p.bordure)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('↻ Calculé depuis la Caisse : ${_f(r.beneficePur)}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 2),
            Text("${r.nbVentes} vente(s) · chiffre d'affaires ${_f(r.caBrut)}", style: TextStyle(fontSize: 10.5, color: p.txtDoux)),
            if (r.nbSansCout > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    "⚠️ ${r.nbSansCout} vente(s) sans prix d'achat connu (${_f(r.caSansCout)}) ne sont pas comptées dans ce bénéfice.",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.alerte)),
              ),
            if (ecartAuto)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _revenu.text = _texteSaisie(r.beneficePur)),
                  icon: const Icon(Icons.restore_rounded, size: 15),
                  label: const Text('Rétablir la valeur de la Caisse', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                ),
              ),
          ]),
        ),
      _carteCharges(p, totalSaisi),
      if (totalSaisi == 0 && chargesOk)
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
          child: Text("ℹ️ Aucune charge saisie : le bénéfice net sera égal au bénéfice pur.",
              style: TextStyle(fontSize: 10.5, color: p.txtGris)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 2, 15, 8),
        child: _grosBouton(Icons.calculate_outlined, 'Calculer le résultat', p.cuivre, _occupe ? null : _calculer, chargement: _occupe),
      ),
      if (_obsolete)
        Container(
          margin: const EdgeInsets.fromLTRB(15, 4, 15, 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: p.alerte.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9), border: Border.all(color: p.alerte)),
          child: Text('⚠️ Les montants ont changé depuis le dernier calcul. Cliquez sur « Calculer le résultat » pour mettre les résultats à jour.',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.txtPrinc)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
        child: _grosBouton(Icons.save_outlined, 'Enregistrer le rapport', p.succes, _occupe ? null : _archiver),
      ),
      _titreSection(p, Icons.folder_open_rounded, 'EXPORTER', p.accent, haut: 6),
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
        child: Row(children: [
          _btnAction(p, Icons.picture_as_pdf_outlined, 'PDF', p.cuivre, _exporterPdf, 'Exporter le bilan en PDF'),
          const SizedBox(width: 8),
          _btnAction(p, Icons.table_view_outlined, 'Excel', p.succes, _exporterExcel, 'Exporter le classeur Excel (5 feuilles)'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
        child: SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _ouvrirArchives,
            icon: const Icon(Icons.archive_outlined, size: 17),
            label: Text(_archives.isEmpty ? 'Consulter les archives' : 'Consulter les archives (${_archives.length})',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
                foregroundColor: p.txtPrinc, side: BorderSide(color: p.bordure),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
          ),
        ),
      ),
      _titreSection(p, Icons.description_outlined, 'AUTRES RAPPORTS', p.accent, haut: 4),
      _tuile(p, '🐣 Rapport Flash — bandes & œufs',
          "Coût de revient, marge réelle et vitesse d'écoulement, bande par bande. Protégé par votre code PIN Boss.",
          '🔒 Ouvrir le Rapport Flash (PIN)', p.cuivre, () => ouvrirRapportFlash(context)),
      _tuile(p, '🏦 Dossier pour la banque',
          'Un PDF propre avec vos ventes, bénéfices, dettes et votre élevage sur 3, 6 ou 12 mois.',
          '📄 Préparer le dossier', p.succes, _dossierBanque),
    ]);
  }

  /// Petit champ de la carte « Charges mensuelles » : icône + nom au-dessus, case de saisie avec FCFA à droite.
  Widget _champCharge(Palette p, TextEditingController c, String label, IconData icone) {
    final lu = AnalyseRapports.lireMontant(c.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          Icon(icone, size: 13, color: p.cuivre),
          const SizedBox(width: 5),
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.txtDoux)),
          ),
        ]),
      ),
      TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 .,  ]'))],
        style: const TextStyle(fontSize: 13),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '0',
          isDense: true,
          suffixText: 'FCFA',
          suffixStyle: TextStyle(fontSize: 10.5, color: p.txtGris),
          errorText: lu.erreur,
          errorMaxLines: 2,
        ),
      ),
    ]);
  }

  /// La carte « Charges mensuelles » : les montants sont rangés sur deux colonnes.
  Widget _carteCharges(Palette p, double? totalSaisi) {
    Widget ligne(Widget a, Widget b) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ]),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(15, 4, 15, 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
      decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.bordure)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: p.cuivre.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.home_work_outlined, size: 17, color: p.accent),
            ),
            const SizedBox(width: 9),
            Text('Charges mensuelles',
                style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold, color: p.accent)),
          ]),
        ),
        ligne(_champCharge(p, _loyer, 'Loyer', Icons.home_outlined),
            _champCharge(p, _elec, 'Électricité & énergie', Icons.bolt_outlined)),
        ligne(_champCharge(p, _transport, 'Transport & logistique', Icons.local_shipping_outlined),
            _champCharge(p, _salaires, "Salaires & main-d'œuvre", Icons.groups_outlined)),
        ligne(
          _champCharge(p, _divers, 'Divers & imprévus', Icons.inventory_2_outlined),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('Total des charges', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.txtDoux)),
            ),
            Container(
              height: 42,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
              child: Text(totalSaisi == null ? '—' : _f(totalSaisi),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: policeTexte, fontSize: 12.5, fontWeight: FontWeight.bold, color: p.danger)),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Grand bouton pleine largeur : icône à gauche, texte au centre, flèche à droite.
  Widget _grosBouton(IconData icone, String texte, Color couleur, VoidCallback? onTap, {bool chargement = false}) => SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(backgroundColor: couleur, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            chargement
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(icone, size: 19),
            const SizedBox(width: 10),
            Text(texte, style: const TextStyle(fontFamily: policeTexte, fontSize: 13.5, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_rounded, size: 17),
          ]),
        ),
      );

  Widget _btnAction(Palette p, IconData icone, String texte, Color couleur, VoidCallback onTap, String aide) => Expanded(
        child: Tooltip(
          message: aide,
          child: SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _occupe ? null : onTap,
              style: FilledButton.styleFrom(
                  backgroundColor: couleur, padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icone, size: 19),
                const SizedBox(height: 2),
                Text(texte, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ),
      );

  Widget _tuile(Palette p, String titre, String texte, String bouton, Color couleur, VoidCallback onTap) => Container(
        margin: const EdgeInsets.fromLTRB(15, 0, 15, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
          const SizedBox(height: 3),
          Text(texte, style: TextStyle(fontSize: 10.5, color: p.txtDoux)),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(backgroundColor: couleur, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(bouton, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      );

  // ------------------------------------------------------------------ colonne de droite
  Widget _bilanOuArchives(Palette p) {
    return Column(children: [
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _voirArchives ? _vueArchives(p) : _vueResultats(p),
        ),
      ),
    ]);
  }

  Widget _carte(Palette p, String titre, Widget contenu, {IconData? icone, String? sousTitre}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.carte,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.bordure),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icone != null) ...[Icon(icone, size: 16, color: p.accent), const SizedBox(width: 7)],
            Expanded(child: Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc))),
          ]),
          if (sousTitre != null)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(sousTitre, style: TextStyle(fontSize: 10.5, color: p.txtGris))),
          const SizedBox(height: 12),
          contenu,
        ]),
      );

  Widget _puce(String texte, Color couleur, {bool surFonce = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: surFonce ? Colors.white.withValues(alpha: 0.14) : couleur.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(20)),
        child: Text(texte,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: surFonce ? Colors.white : couleur)),
      );

  Color _couleurEvolution(Palette p, LigneComparaison l) {
    final f = l.favorable;
    return f == null ? p.txtGris : (f ? p.succes : p.danger);
  }

  String _texteEvolution(LigneComparaison l) {
    final e = l.evolution;
    if (l.precedent == null) return '—';
    if (e == null) return 'n/d';
    final fleche = e.abs() < 0.05 ? '=' : (e > 0 ? '▲' : '▼');
    final signe = e > 0 ? '+' : '';
    final v = l.enPourcent ? '$signe${e.toStringAsFixed(1)} pts' : '$signe${e.toStringAsFixed(1)} %';
    return '$fleche $v';
  }

  Widget _kpi(Palette p, double largeur, {
    required IconData icone, required String titre, required String valeur, required Color couleur,
    String? sous, LigneComparaison? evolution, bool fort = false, Widget? extra,
  }) {
    final txtDoux = fort ? p.menuDoux : p.txtGris;
    final couleurValeur = fort ? (couleur == p.danger ? const Color(0xFFFFB4A8) : Colors.white) : couleur;
    final chip = (evolution != null && evolution.precedent != null)
        ? _puce('${_texteEvolution(evolution)} vs préc.',
            fort ? Colors.white : _couleurEvolution(p, evolution), surFonce: fort)
        : null;
    return Container(
      width: largeur,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fort ? p.menu : p.carte,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fort ? p.menu : p.bordure),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: fort ? 0.12 : 0.035), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: fort ? Colors.white.withValues(alpha: 0.12) : couleur.withValues(alpha: 0.13)),
            child: Icon(icone, size: 15, color: fort ? p.menuTxt : couleur),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(titre,
                maxLines: 2,
                style: TextStyle(fontFamily: policeTexte, fontSize: 10.5, fontWeight: FontWeight.bold, color: txtDoux)),
          ),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(valeur, style: TextStyle(fontFamily: policeTexte, fontSize: 22, fontWeight: FontWeight.bold, color: couleurValeur)),
        ),
        if (sous != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sous, style: TextStyle(fontSize: 10.5, color: txtDoux))),
        if (chip != null) Padding(padding: const EdgeInsets.only(top: 8), child: chip),
        if (extra != null) Padding(padding: const EdgeInsets.only(top: 8), child: extra),
      ]),
    );
  }

  Widget _vueResultats(Palette p) {
    final b = _bilan;
    final res = _res;
    final syn = _synthese;
    return SingleChildScrollView(
      key: const ValueKey('resultats'),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
      child: LayoutBuilder(builder: (context, c) {
        final largeur = c.maxWidth;
        if (b == null || res == null || syn == null) return _etatVide(p);
        final colonnes = largeur >= 760 ? 4 : 2;
        final w = (largeur - (colonnes - 1) * 12) / colonnes;
        final positif = res.net >= 0;
        final coulNet = positif ? p.succes : p.danger;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('📊 RÉSULTATS FINANCIERS',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _puce('📅 ${AnalyseRapports.libelleMois(b.periode)} · jusqu\'au ${DateTime.now().day}', p.txtDoux),
            if (b.revenuModifie) _puce('✏️ Revenu ajusté à la main', p.alerte),
            _obsolete ? _puce('⚠️ Obsolète : recalculez', p.danger) : _puce('✔ À jour', p.succes),
          ]),
          if (_obsolete)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Les chiffres ci-dessous correspondent à la saisie du dernier calcul, pas à celle affichée à gauche.',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: p.danger)),
            ),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _kpi(p, w, icone: Icons.storefront_outlined, titre: "CHIFFRE D'AFFAIRES", valeur: _f(res.caBrut), couleur: p.courbe1,
                sous: '${syn.detail.nbVentes} vente(s) facturée(s)', evolution: syn.comparaison[0]),
            _kpi(p, w, icone: Icons.receipt_long_outlined, titre: 'CHARGES TOTALES', valeur: _f(res.charges), couleur: p.danger,
                sous: res.benefice > 0 ? '${_pct(res.charges / res.benefice * 100)} du bénéfice pur' : 'Charges mensuelles saisies',
                evolution: syn.comparaison[3]),
            _kpi(p, w, icone: Icons.workspace_premium_outlined, titre: 'BÉNÉFICE NET', valeur: _f(res.net), couleur: coulNet,
                sous: 'Bénéfice pur − charges', evolution: syn.comparaison[4], fort: true),
            _kpi(p, w, icone: Icons.percent_rounded, titre: 'MARGE NETTE', valeur: _pct(res.margePct), couleur: coulNet,
                sous: "Net ÷ chiffre d'affaires", evolution: syn.comparaison[5],
                extra: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: (res.margePct / 100).clamp(0.0, 1.0).toDouble(), minHeight: 6, color: coulNet, backgroundColor: p.bordure),
                )),
          ]),
          _carte(p, 'Du chiffre d\'affaires au bénéfice net', _chaineCalcul(p, b, res, syn),
              icone: Icons.account_tree_outlined, sousTitre: 'Chaque ligne se déduit de la précédente : rien n\'est caché.'),
          _carte(p, 'Évolution sur 6 mois', _graphTendance(p, syn),
              icone: Icons.show_chart_rounded, sousTitre: "Chiffre d'affaires et bénéfice pur, issus de vos ventes enregistrées"),
          if (largeur >= 760)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _carte(p, 'Du bénéfice pur au net', _graphCascade(p, res), icone: Icons.bar_chart_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _carte(p, 'Répartition des charges', _repartitionCharges(p, b), icone: Icons.pie_chart_outline_rounded)),
            ])
          else ...[
            _carte(p, 'Du bénéfice pur au net', _graphCascade(p, res), icone: Icons.bar_chart_rounded),
            _carte(p, 'Répartition des charges', _repartitionCharges(p, b), icone: Icons.pie_chart_outline_rounded),
          ],
          _carte(p, 'Comparaison avec la période précédente', _tableauComparaison(p, syn),
              icone: Icons.compare_arrows_rounded,
              sousTitre: 'Actuelle : ${syn.libelleActuel}  ·  Précédente : ${syn.libellePrecedent}'),
        ]);
      }),
    );
  }

  Widget _etatVide(Palette p) {
    final r = _revenuMois;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('📊 RÉSULTATS FINANCIERS',
          style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      const SizedBox(height: 14),
      _carte(
        p,
        'Pas encore de bilan',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in const [
            '1.  Vérifiez le bénéfice pur pré-rempli (issu de la Caisse).',
            '2.  Saisissez vos charges du mois à gauche.',
            '3.  Cliquez sur « Calculer le résultat » : indicateurs, graphiques et comparaison apparaissent ici.',
          ])
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(e, style: TextStyle(fontSize: 12, color: p.txtDoux))),
        ]),
        icone: Icons.info_outline_rounded,
      ),
      _carte(
        p,
        'Aperçu des ventes du mois en cours',
        r == null
            ? Text(_erreurChargement ?? 'Chargement…', style: TextStyle(fontSize: 12, color: p.txtGris))
            : r.nbVentes == 0
                ? Text("Aucune vente enregistrée ce mois-ci. Le chiffre d'affaires et le bénéfice pur sont à 0.",
                    style: TextStyle(fontSize: 12, color: p.txtGris))
                : Wrap(spacing: 24, runSpacing: 10, children: [
                    _mini(p, "Chiffre d'affaires", _f(r.caBrut)),
                    _mini(p, "Coût d'achat", _f(r.coutAchat)),
                    _mini(p, 'Bénéfice pur', _f(r.beneficePur)),
                    _mini(p, 'Ventes', '${r.nbVentes}'),
                  ]),
        icone: Icons.storefront_outlined,
        sousTitre: 'Données réelles de la Caisse, avant saisie des charges',
      ),
    ]);
  }

  Widget _mini(Palette p, String t, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: TextStyle(fontSize: 10.5, color: p.txtGris)),
        const SizedBox(height: 2),
        Text(v, style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      ]);

  // ------------------------------------------------------------------ blocs de la vue résultats
  Widget _ligneCalcul(Palette p, String op, String libelle, String valeur, {bool gras = false, Color? couleur, bool fond = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(color: fond ? p.panneau2 : null, borderRadius: BorderRadius.circular(7)),
        child: Row(children: [
          SizedBox(width: 22, child: Text(op, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.txtGris))),
          Expanded(
              child: Text(libelle,
                  style: TextStyle(fontSize: 12, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: p.txtPrinc))),
          Text(valeur,
              style: TextStyle(
                  fontFamily: policeTexte, fontSize: 12.5, fontWeight: gras ? FontWeight.bold : FontWeight.w600,
                  color: couleur ?? p.txtPrinc)),
        ]),
      );

  Widget _chaineCalcul(Palette p, BilanMarge b, ResultatFinancier res, SynthesePeriodes syn) {
    final d = syn.detail;
    final coulNet = res.net >= 0 ? p.succes : p.danger;
    return Column(children: [
      _ligneCalcul(p, '', "Chiffre d'affaires facturé (ventes du mois)", _f(d.caBrut)),
      if (d.caSansCout > 0) _ligneCalcul(p, '−', "Ventes sans prix d'achat connu (non comptées)", _f(d.caSansCout)),
      _ligneCalcul(p, '−', "Coût d'achat des marchandises vendues", _f(d.coutAchat)),
      _ligneCalcul(p, '=', 'Bénéfice pur de la Caisse', _f(d.beneficePur), gras: true, fond: true),
      if (b.revenuModifie) _ligneCalcul(p, '±', 'Ajustement manuel du revenu', _f(b.ca - d.beneficePur), couleur: p.alerte),
      _ligneCalcul(p, '−', 'Charges totales', _f(res.charges), couleur: p.danger),
      _ligneCalcul(p, '=', 'Bénéfice net (poche du Boss)', _f(res.net), gras: true, fond: true, couleur: coulNet),
      _ligneCalcul(p, '%', "Marge nette = net ÷ chiffre d'affaires", _pct(res.margePct), gras: true, couleur: coulNet),
      if (d.nbSansCout > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
              "⚠️ ${d.nbSansCout} vente(s) sans prix d'achat connu : elles sont dans le chiffre d'affaires (donc dans le dénominateur de la marge) "
              'mais pas dans le bénéfice. Renseignez leurs arrivages pour une marge plus fidèle.',
              style: TextStyle(fontSize: 10.5, color: p.alerte)),
        ),
      if (d.beneficeEnAttente > 0.5)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Text('dont ${_f(d.beneficeEnAttente)} de marge sur des crédits pas encore recouvrés',
              style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: p.alerte)),
        ),
    ]);
  }

  Widget _graphTendance(Palette p, SynthesePeriodes syn) {
    final t = syn.tendance;
    final vide = t.every((m) => m.ca == 0 && m.benefice == 0);
    if (vide) {
      return Text('Aucune vente enregistrée sur les 6 derniers mois : pas de graphique.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GraphiqueBarres(
        palette: p,
        hauteur: 210,
        etiquettes: [for (final m in t) m.etiquette],
        series: [
          SerieBarres("Chiffre d'affaires", p.courbe1, [for (final m in t) m.ca]),
          SerieBarres('Bénéfice pur', p.cuivre, [for (final m in t) m.benefice]),
        ],
      ),
      const SizedBox(height: 4),
      Text('Le mois en cours est partiel (jusqu\'à aujourd\'hui).', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.txtGris)),
    ]);
  }

  Widget _graphCascade(Palette p, ResultatFinancier res) {
    return GraphiqueBarres(
      palette: p,
      hauteur: 190,
      legende: false,
      etiquettes: const ['Revenu retenu', 'Charges', 'Net'],
      series: [
        SerieBarres('Montants', p.courbe1, [res.benefice, res.charges, res.net],
            couleursParBarre: [p.courbe1, p.danger, res.net >= 0 ? p.succes : p.danger]),
      ],
    );
  }

  Widget _repartitionCharges(Palette p, BilanMarge b) {
    final postes = [
      ('🏠 Loyer', b.loyer), ('⚡ Électricité & énergie', b.elec), ('🚚 Transport & logistique', b.transport),
      ("👷 Salaires & main d'œuvre", b.salaires), ('🧰 Divers & imprévus', b.divers),
    ];
    if (b.totalCharges <= 0) {
      return Text('Aucune charge saisie pour ce bilan.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris));
    }
    return Column(children: [
      for (final e in postes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(e.$1, style: TextStyle(fontSize: 11.5, color: p.txtPrinc))),
              Text('${_f(e.$2)}  ·  ${_pct(e.$2 / b.totalCharges * 100)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtDoux)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(value: (e.$2 / b.totalCharges).clamp(0.0, 1.0).toDouble(), minHeight: 7,
                  color: p.danger, backgroundColor: p.bordure),
            ),
          ]),
        ),
    ]);
  }

  Widget _tableauComparaison(Palette p, SynthesePeriodes syn) {
    TextStyle ent() => TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: p.txtGris);
    Widget cel(String t, {TextStyle? style, TextAlign align = TextAlign.right}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(t, textAlign: align, style: style ?? TextStyle(fontSize: 11.5, color: p.txtPrinc)),
        );
    String m(LigneComparaison l, double v) => l.enPourcent ? _pct(v) : _f(v);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Table(
        columnWidths: const {0: FlexColumnWidth(2.3), 1: FlexColumnWidth(1.6), 2: FlexColumnWidth(1.6), 3: FlexColumnWidth(1.3)},
        border: TableBorder(horizontalInside: BorderSide(color: p.bordure)),
        children: [
          TableRow(children: [
            cel('Indicateur', style: ent(), align: TextAlign.left),
            cel('Actuelle', style: ent()),
            cel('Précédente', style: ent()),
            cel('Évolution', style: ent()),
          ]),
          for (final l in syn.comparaison)
            TableRow(children: [
              cel(l.libelle, align: TextAlign.left),
              cel(m(l, l.actuel), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              cel(l.precedent == null ? '—' : m(l, l.precedent!), style: TextStyle(fontSize: 11.5, color: p.txtDoux)),
              cel(_texteEvolution(l),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _couleurEvolution(p, l))),
            ]),
        ],
      ),
      const SizedBox(height: 8),
      if (syn.precedentVide)
        Text('Aucune vente enregistrée sur la période précédente : les évolutions ne sont pas calculables (« n/d »).',
            style: TextStyle(fontSize: 10.5, color: p.alerte)),
      Text(
          syn.archivePrecedente == null
              ? "Charges, bénéfice net et marge : aucun bilan archivé pour la période précédente. Archivez chaque mois pour alimenter cette comparaison."
              : 'Charges, bénéfice net et marge : comparés au bilan archivé de la période précédente (mois complet).',
          style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: p.txtGris)),
      Text("Pour les charges, une baisse est favorable (vert) ; pour le coût d'achat, l'évolution reste neutre (liée au volume).",
          style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: p.txtGris)),
    ]);
  }

  // ------------------------------------------------------------------ archives
  List<BilanArchive> _archivesFiltrees() {
    var l = _archives.toList();
    if (_filtreArchives == 'sync') l = l.where((a) => a.envoye).toList();
    if (_filtreArchives == 'local') l = l.where((a) => !a.envoye).toList();
    final q = _rechercheArchives.trim().toLowerCase();
    if (q.isNotEmpty) {
      l = l
          .where((a) =>
              a.periode.toLowerCase().contains(q) ||
              AnalyseRapports.libelleMois(a.periode).toLowerCase().contains(q) ||
              a.dateArchivage.toLowerCase().contains(q))
          .toList();
    }
    // du plus récent au plus ancien (période), à égalité l'ordre d'archivage d'origine
    final indexees = [for (var i = 0; i < l.length; i++) (i, l[i])];
    indexees.sort((x, y) {
      final kx = AnalyseRapports.clePeriode(x.$2.periode) ?? 0;
      final ky = AnalyseRapports.clePeriode(y.$2.periode) ?? 0;
      return ky != kx ? ky.compareTo(kx) : x.$1.compareTo(y.$1);
    });
    return [for (final e in indexees) e.$2];
  }

  Widget _vueArchives(Palette p) {
    final uniques = AnalyseRapports.dernieresParPeriode(_archives);
    final doublons = _archives.length - uniques.length;
    final cumul = uniques.fold<double>(0, (s, a) => s + a.net);
    BilanArchive? meilleur;
    for (final a in uniques) {
      if (meilleur == null || a.net > meilleur.net) meilleur = a;
    }
    final liste = _archivesFiltrees();
    final chrono = uniques.where((a) => AnalyseRapports.clePeriode(a.periode) != null).toList()
      ..sort((x, y) => AnalyseRapports.clePeriode(x.periode)!.compareTo(AnalyseRapports.clePeriode(y.periode)!));
    final dernieres = chrono.length > 12 ? chrono.sublist(chrono.length - 12) : chrono;

    return SingleChildScrollView(
      key: const ValueKey('archives'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _voirArchives = false),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Retour au bilan', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(foregroundColor: p.txtPrinc, side: BorderSide(color: p.bordure), minimumSize: const Size(0, 34)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('🗄️ ARCHIVES DES BILANS MENSUELS',
                style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          ),
        ]),
        if (_archives.isEmpty)
          _carte(
              p, 'Aucun bilan archivé',
              Text("Calculez un bilan puis cliquez sur « Enregistrer le rapport » : il apparaîtra ici, prêt à être consulté, comparé et repris le mois suivant.",
                  style: TextStyle(fontSize: 12, color: p.txtDoux)),
              icone: Icons.archive_outlined)
        else ...[
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 10, children: [
            _resumeArchive(p, 'Bilans', '${uniques.length}${doublons > 0 ? ' (+$doublons en double)' : ''}', Icons.folder_copy_outlined, p.txtPrinc),
            _resumeArchive(p, 'Cumul du bénéfice net', _f(cumul), Icons.savings_outlined, cumul >= 0 ? p.succes : p.danger),
            if (meilleur != null)
              _resumeArchive(p, 'Meilleur mois', '${AnalyseRapports.libelleMois(meilleur.periode)} · ${_f(meilleur.net)}',
                  Icons.emoji_events_outlined, p.or),
          ]),
          if (doublons > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Le cumul ne compte qu\'un bilan par période (le plus récent).',
                  style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: p.txtGris)),
            ),
          if (dernieres.length >= 2)
            _carte(
              p, 'Bénéfice net par mois archivé',
              GraphiqueBarres(
                palette: p, hauteur: 170, legende: false,
                etiquettes: [for (final a in dernieres) _etiquetteCourte(a.periode)],
                series: [
                  SerieBarres('Net', p.succes, [for (final a in dernieres) a.net],
                      couleursParBarre: [for (final a in dernieres) a.net >= 0 ? p.succes : p.danger]),
                ],
              ),
              icone: Icons.bar_chart_rounded,
              sousTitre: '12 derniers mois archivés au maximum',
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _rechercheArchives = v),
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                    hintText: 'Rechercher un mois (ex. septembre, 09/2026)…', isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _rechercheArchives.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () => setState(() => _rechercheArchives = ''))),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final f in const [('tous', 'Tous'), ('sync', '☁️ Synchronisés'), ('local', '💾 Locaux uniquement')])
              ChoiceChip(
                label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                selected: _filtreArchives == f.$1,
                onSelected: (_) => setState(() => _filtreArchives = f.$1),
              ),
          ]),
          const SizedBox(height: 10),
          if (liste.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text('Aucun bilan ne correspond à votre recherche.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris))),
            )
          else
            for (var i = 0; i < liste.length; i++) _carteArchive(p, liste[i], i),
        ],
      ]),
    );
  }

  /// « 09/2026 » -> « 09/26 » (texte inchangé s'il n'est pas lisible).
  String _etiquetteCourte(String periode) {
    final m = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(periode.trim());
    if (m == null) return periode;
    return '${m[1]!.padLeft(2, '0')}/${m[2]!.substring(2)}';
  }

  Widget _resumeArchive(Palette p, String t, String v, IconData icone, Color couleur) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 20, color: couleur),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(fontSize: 10.5, color: p.txtGris)),
            Text(v, style: TextStyle(fontFamily: policeTexte, fontSize: 13.5, fontWeight: FontWeight.bold, color: couleur)),
          ]),
        ]),
      );

  Widget _carteArchive(Palette p, BilanArchive a, int i) {
    final coul = a.net >= 0 ? p.succes : p.danger;
    Widget ligne(String t, String v, {bool gras = false, Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11.5, color: p.txtDoux))),
            Text(v, style: TextStyle(fontSize: 11.5, fontWeight: gras ? FontWeight.bold : FontWeight.w600, color: c ?? p.txtPrinc)),
          ]),
        );
    final detailConnu = a.loyer + a.elec + a.transport + a.salaires + a.divers > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('arch-$i-${a.periode}-${a.dateArchivage}'),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(children: [
            Expanded(
              child: Text('📅 ${AnalyseRapports.libelleMois(a.periode)}',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
            Text(_f(a.net), style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: coul)),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(spacing: 10, runSpacing: 2, children: [
              Text('Archivé le ${a.dateArchivage}', style: TextStyle(fontSize: 10.5, color: p.txtGris)),
              Text('Marge ${_pct(a.margePct)}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: coul)),
              Text(a.envoye ? '☁️ Synchronisé' : '💾 Local uniquement', style: TextStyle(fontSize: 10.5, color: p.txtGris)),
            ]),
          ),
          children: [
            const Divider(height: 8),
            ligne('Bénéfice pur retenu', _f(a.ca)),
            if (detailConnu) ...[
              if (a.loyer > 0) ligne('   🏠 Loyer', _f(a.loyer)),
              ligne('   ⚡ Électricité & énergie', _f(a.elec)),
              ligne('   🚚 Transport & logistique', _f(a.transport)),
              ligne("   👷 Salaires & main d'œuvre", _f(a.salaires)),
              ligne('   🧰 Divers & imprévus', _f(a.divers)),
            ],
            ligne('Charges totales', _f(a.totalCharges), c: p.danger),
            ligne('Bénéfice net', _f(a.net), gras: true, c: coul),
            ligne('Marge nette', _pct(a.margePct), gras: true, c: coul),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _reprendreCharges(a),
                icon: const Icon(Icons.content_copy_rounded, size: 15),
                label: const Text('Reprendre ces charges dans la saisie', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(foregroundColor: p.txtPrinc, side: BorderSide(color: p.bordure)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
