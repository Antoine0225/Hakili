import 'package:flutter/material.dart';

import '../data/bilans_repo.dart';
import '../data/ventes_repo.dart';
import '../services/pdf_banque.dart';
import '../services/pdf_marge.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogue_periode.dart';
import '../widgets/dialogues.dart';
import '../widgets/mise_en_page_module.dart';
import '../widgets/toast.dart';
import 'dialogue_dossier_banque.dart';
import 'rapport_flash.dart';

/// Module Rapports (« Marge & Bénéfice du Boss ») : à gauche la saisie des charges du mois,
/// à droite les résultats ou les archives des bilans.
class EcranRapports extends StatefulWidget {
  const EcranRapports({super.key});

  @override
  State<EcranRapports> createState() => _EcranRapportsState();
}

class _EcranRapportsState extends State<EcranRapports> {
  final _revenu = TextEditingController();
  final _elec = TextEditingController();
  final _transport = TextEditingController();
  final _salaires = TextEditingController();
  final _divers = TextEditingController();

  List<Vente> _ventes = [];
  RevenuCaisse? _revenuMois;
  double _revenuAutoInit = 0;
  BilanMarge? _bilan;
  bool _voirArchives = false;
  List<BilanArchive> _archives = [];

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    for (final c in [_revenu, _elec, _transport, _salaires, _divers]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initialiser() async {
    final v = await VentesRepo.toutes();
    final n = DateTime.now();
    final r = VentesRepo.revenuPeriode(v, DateTime(n.year, n.month, 1), DateTime(n.year, n.month, n.day, 23, 59, 59, 999));
    if (!mounted) return;
    setState(() {
      _ventes = v;
      _revenuMois = r;
      _revenuAutoInit = r.beneficePur;
      _revenu.text = milliersAnglais(r.beneficePur).replaceAll(',', ' ');
    });
  }

  double _lire(TextEditingController c) {
    final t = c.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    return t.isEmpty ? 0.0 : (double.tryParse(t) ?? 0.0);
  }

  void _calculer() {
    final ca = _lire(_revenu);
    final elec = _lire(_elec), transport = _lire(_transport), salaires = _lire(_salaires), divers = _lire(_divers);
    final n = DateTime.now();
    final detail = VentesRepo.revenuPeriode(
        _ventes, DateTime(n.year, n.month, 1), DateTime(n.year, n.month, n.day, 23, 59, 59, 999));
    final modifie = (ca - _revenuAutoInit).abs() > 1.0;
    final base = detail.caBrut > 0 ? detail.caBrut : ca;
    final total = elec + transport + salaires + divers;
    final net = ca - total;
    final pct = base > 0 ? net / base * 100 : 0.0;
    setState(() {
      _voirArchives = false;
      _bilan = BilanMarge(
        ca: ca, elec: elec, transport: transport, salaires: salaires, divers: divers,
        totalCharges: total, netPoche: net, margePct: pct,
        periode: '${n.month.toString().padLeft(2, '0')}/${n.year}',
        revenuModifie: modifie, detailCaisse: modifie ? null : detail,
      );
    });
  }

  Future<void> _archiver() async {
    final b = _bilan;
    if (b == null) {
      Dialogues.avertissement(context, 'Bilan manquant', '⚠️ Calculez d\'abord le bénéfice du mois avant d\'archiver.');
      return;
    }
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
    final b = _bilan;
    if (b == null) {
      Dialogues.avertissement(context, 'Bilan manquant', '⚠️ Calculez d\'abord le bénéfice du mois avant d\'exporter.');
      return;
    }
    final periode = await choisirPeriode(context,
        titre: '📅 PÉRIODE DU BILAN DE MARGE', texteBouton: '📄 Générer le PDF', moisCourantParDefaut: true);
    if (periode == null || !mounted) return;
    try {
      final ok = await PdfMarge.exporter(b, _ventes, periode.debut, periode.fin, periode.texteDebut, periode.texteFin);
      if (ok && mounted) Toast.afficher(context, '🔥 Bilan exporté et classé !', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', "Détails de l'exportation : $e");
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

  // ------------------------------------------------------------------ construction
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
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('💰 SAISIE DES CHARGES DU MOIS',
                style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold, color: p.accent)),
            const SizedBox(height: 2),
            Text('Calcule la rentabilité réelle à partir des flux de la Caisse\n(ventes enregistrées) et de vos charges mensuelles.',
                style: TextStyle(fontSize: 11, color: p.txtDoux)),
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

  Widget _champ(Palette p, TextEditingController c, {double hauteur = 36, String? indice}) => Padding(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 10),
        child: SizedBox(
          height: hauteur,
          child: TextField(
            controller: c, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(hintText: indice, isDense: true),
          ),
        ),
      );

  Widget _lib(Palette p, String t, {Color? couleur, bool gras = false, double haut = 0}) => Padding(
        padding: EdgeInsets.fromLTRB(15, haut, 15, 0),
        child: Text(t, style: TextStyle(fontSize: gras ? 12 : 11, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: couleur ?? p.txtDoux)),
      );

  Widget _saisie(Palette p) {
    final r = _revenuMois;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lib(p, '📥 REVENUS', couleur: p.succes, gras: true, haut: 15),
      const SizedBox(height: 5),
      _lib(p, 'Bénéfice pur de la Caisse du mois (FCFA)'),
      _champ(p, _revenu, hauteur: 38),
      _lib(p, '↻ Pré-rempli automatiquement : bénéfice pur '),
      const SizedBox(height: 10),
      if (r != null && r.nbSansCout > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
          child: Text(
              "⚠️ ${r.nbSansCout} vente(s) sans prix d'achat connu (${milliersAnglais(r.caSansCout)} F) ne sont pas comptées dans ce bénéfice.",
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: p.alerte)),
        ),
      _lib(p, '📤 CHARGES FIXES MENSUELLES', couleur: p.danger, gras: true, haut: 10),
      const SizedBox(height: 5),
      _lib(p, '⚡ Électricité & Énergie (FCFA)'),
      _champ(p, _elec, indice: '0'),
      _lib(p, '🚚 Transport & Logistique (FCFA)'),
      _champ(p, _transport, indice: '0'),
      _lib(p, "👷 Salaires & Main d'œuvre (FCFA)"),
      _champ(p, _salaires, indice: '0'),
      _lib(p, '🧰 Divers & Imprévus (FCFA)'),
      _champ(p, _divers, indice: '0'),
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
        child: SizedBox(
          width: double.infinity, height: 44,
          child: FilledButton(
            onPressed: _calculer,
            style: FilledButton.styleFrom(backgroundColor: p.cuivre, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('📊 Calculer le Bénéfice du Boss',
                style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
        child: Column(children: [
          SizedBox(
            width: double.infinity, height: 36,
            child: FilledButton(
              onPressed: _archiver,
              style: FilledButton.styleFrom(backgroundColor: p.succes, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('💾 Archiver dans Supabase', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: _ouvrirArchives,
                  style: FilledButton.styleFrom(backgroundColor: p.panneau2, foregroundColor: p.txtPrinc,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text('🗄️ Archives', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: _exporterPdf,
                  style: FilledButton.styleFrom(backgroundColor: p.panneau2, foregroundColor: p.txtPrinc,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text('📄 Exporter en PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(15, 0, 15, 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🐣 RAPPORT FLASH — PERFORMANCE BANDE & ŒUFS',
              style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
          const SizedBox(height: 2),
          Text('Accès protégé par votre code PIN Boss — coût de revient, marge réelle et\nvitesse d\'écoulement, bande par bande (Module 3).',
              style: TextStyle(fontSize: 10, color: p.txtDoux)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 38,
            child: FilledButton(
              onPressed: () => ouvrirRapportFlash(context),
              style: FilledButton.styleFrom(backgroundColor: p.cuivre, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('🔒 Ouvrir le Rapport Flash (PIN)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(15, 0, 15, 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🏦 DOSSIER POUR LA BANQUE',
              style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
          const SizedBox(height: 2),
          Text('Un PDF propre avec vos ventes, votre bénéfice, vos dettes et votre élevage sur 3, 6 ou 12 mois — prêt à présenter à une banque ou à une microfinance.',
              style: TextStyle(fontSize: 10, color: p.txtDoux)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 38,
            child: FilledButton(
              onPressed: _dossierBanque,
              style: FilledButton.styleFrom(backgroundColor: p.succes, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('📄 Préparer le dossier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ------------------------------------------------------------------ résultats à droite
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

  Widget _carteRes(Palette p, String titre, String valeur, Color couleur) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 14),
        width: double.infinity,
        decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.bordure)),
        child: Column(children: [
          Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtGris)),
          const SizedBox(height: 2),
          Text(valeur, style: TextStyle(fontFamily: policeTexte, fontSize: 24, fontWeight: FontWeight.bold, color: couleur)),
        ]),
      );

  Widget _vueResultats(Palette p) {
    final b = _bilan;
    return SingleChildScrollView(
      key: const ValueKey('resultats'),
      child: Column(children: [
        const SizedBox(height: 25),
        Text('📊 RÉSULTATS FINANCIERS',
            style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        const SizedBox(height: 20),
        if (b == null)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text('Renseignez vos charges à gauche puis cliquez sur\n« 📊 Calculer le Bénéfice du Boss » pour voir le résultat ici.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris)),
          )
        else ...[
          _carteRes(p, '💸 TOTAL DES CHARGES DU MOIS', '${milliersAnglais(b.totalCharges)} FCFA', p.danger),
          _carteRes(p, '👑 NET DANS LA POCHE DU BOSS', '${milliersAnglais(b.netPoche)} FCFA', b.netPoche >= 0 ? p.succes : p.danger),
          _carteRes(p, '📈 POURCENTAGE DE MARGE NETTE', '${b.margePct.toStringAsFixed(1)} %', b.netPoche >= 0 ? p.succes : p.danger),
          const SizedBox(height: 10),
          Text('Revenu pris en compte (bénéfice pur de la Caisse) : ${milliersAnglais(b.ca)} FCFA',
              style: TextStyle(fontSize: 11, color: p.txtDoux)),
          if (b.detailCaisse != null) ...[
            const SizedBox(height: 2),
            Text(
                'Ventes du mois : ${milliersAnglais((b.detailCaisse as RevenuCaisse).caBrut - (b.detailCaisse as RevenuCaisse).caSansCout)} F  −  '
                "Prix d'achat des marchandises vendues : ${milliersAnglais((b.detailCaisse as RevenuCaisse).coutAchat)} F",
                style: TextStyle(fontSize: 10, color: p.txtGris)),
            if ((b.detailCaisse as RevenuCaisse).beneficeEnAttente > 0.5)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    'dont ${milliersAnglais((b.detailCaisse as RevenuCaisse).beneficeEnAttente)} F de marge sur crédits pas encore recouvrés',
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.alerte)),
              ),
          ],
          const SizedBox(height: 20),
        ],
      ]),
    );
  }

  Widget _vueArchives(Palette p) {
    return Column(key: const ValueKey('archives'), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 5),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 100, height: 28,
            child: FilledButton(
              onPressed: () => setState(() => _voirArchives = false),
              style: FilledButton.styleFrom(backgroundColor: p.cuivre, padding: EdgeInsets.zero),
              child: const Text('⬅️ Retour', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 10),
        child: Text('🗄️ ARCHIVES DES BILANS MENSUELS',
            style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: _archives.isEmpty
              ? Center(child: Text("Aucun bilan archivé pour l'instant.",
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris)))
              : ListView(padding: const EdgeInsets.all(4), children: [
                  for (final a in _archives)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                      padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('📅 Période ${a.periode} — archivé le ${a.dateArchivage}',
                            style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                        const SizedBox(height: 2),
                        Text(
                            'Revenu : ${milliersAnglais(a.ca)} F   •   Charges : ${milliersAnglais(a.totalCharges)} F   •   '
                            'Net : ${milliersAnglais(a.net)} F (${a.margePct.toStringAsFixed(1)} %)   •   '
                            '${a.envoye ? '☁️ Synchronisé' : '💾 Local uniquement'}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: a.net >= 0 ? p.succes : p.danger)),
                      ]),
                    ),
                ]),
        ),
      ),
    ]);
  }
}
