import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../metier/financement.dart';
import '../metier/previsions_pondeuses.dart';
import '../metier/projet_base.dart' show tableauConso;
import '../session.dart';
import '../utilitaires/formats.dart';
import '../utilitaires/texte_pdf.dart';
import 'logo_pdf.dart';

/// Prévision « pondeuses d'œufs de table » en PDF : verdict, chiffres, scénarios, trésorerie mois par mois.
class PdfPondeuses {
  PdfPondeuses._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _gris = PdfColor.fromHex('#6f7d75');
  static final _emeraude = PdfColor.fromHex('#2f7d4f');
  static final _rouge = PdfColor.fromHex('#b3372a');
  static final _orange = PdfColor.fromHex('#c2691f');

  static String _t(String s) => sansAccents(s);
  static String _f(num v) => _t(fmtF(v));

  static pw.Widget _titre(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
        child: pw.Text(_t(t), style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _vert)),
      );

  static pw.Widget _lig(String a, String b, {bool gras = false, String c = '', String d = '', PdfColor? couleur}) {
    final st = pw.TextStyle(fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(children: [
        pw.Expanded(flex: 5, child: pw.Text(_t(a), style: st)),
        if (c.isNotEmpty) pw.Expanded(flex: 2, child: pw.Text(_t(c), textAlign: pw.TextAlign.right, style: st)),
        if (d.isNotEmpty) pw.Expanded(flex: 2, child: pw.Text(_t(d), textAlign: pw.TextAlign.right, style: st)),
        pw.Expanded(flex: 3, child: pw.Text(_t(b), textAlign: pw.TextAlign.right, style: st)),
      ]),
    );
  }

  static pw.Widget _ligN(List<(String, int)> cases, {bool gras = false, PdfColor? couleur}) {
    final st = pw.TextStyle(fontSize: 8.5, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (var i = 0; i < cases.length; i++)
          pw.Expanded(flex: cases[i].$2, child: pw.Text(_t(cases[i].$1), textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right, style: st)),
      ]),
    );
  }

  static pw.Widget _note(String t) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Text(_t(t), style: const pw.TextStyle(fontSize: 8)),
      );

  static String _cumul(double c) => c < 0 ? '${_f(c.abs())} avances' : '${_f(c)} gagnes';

  static pw.Widget _trait() => pw.Container(height: 0.6, color: PdfColors.grey500, margin: const pw.EdgeInsets.symmetric(vertical: 2));

  static pw.Widget _puce(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('- ', style: const pw.TextStyle(fontSize: 9)),
          pw.Expanded(child: pw.Text(_t(t), style: const pw.TextStyle(fontSize: 9))),
        ]),
      );

  static String _n(double v) => milliersAnglais(v.round());

  static Future<bool> exporter(ParamsPondeuses p, String race) async {
    final r = PrevisionPondeuses.calculer(p);
    final sc = AnalysePondeuses.scenarios(p);
    final v = AnalysePondeuses.verdict(p, sc);
    final profil = AnalysePondeuses.profilPonte(p, r);
    final seuils = AnalysePondeuses.seuils(p, r);
    final arr = p.arrivee;
    final logo = await LogoPdf.widget();
    final nomFerme = _t(Session.nomFerme.trim().isEmpty ? 'Exploitation avicole' : Session.nomFerme.trim());
    final couleurVerdict = v.niveau == 2 ? _emeraude : (v.niveau == 1 ? _orange : _rouge);
    final gain = r.benefice >= 0;

    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('PREVISION PONDEUSES D\'OEUFS DE TABLE - ${nomFerme.toUpperCase()}',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 4),
      pw.Text(_t('Race : $race - ${_n(p.poussins)} poussins - ponte de ${p.dureePonteSem.round()} semaines a partir de $semainesDebutPonte semaines'),
          style: pw.TextStyle(fontSize: 9, color: _gris)),
      if (arr != null)
        pw.Text(_t('Arrivee des poussins : ${dateLongue(arr)} - premiers oeufs vers le ${dateLongue(arr.add(const Duration(days: semainesDebutPonte * 7)))}'),
            style: pw.TextStyle(fontSize: 9, color: _gris)),
      pw.Text(_t(p.alimentMaison ? 'Aliment : fabrique par l\'eleveur' : 'Aliment : achete tout fait'), style: pw.TextStyle(fontSize: 9, color: _gris)),
      pw.SizedBox(height: 10),
      // verdict
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: couleurVerdict, width: 1.5), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_t(v.titre), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: couleurVerdict)),
          pw.SizedBox(height: 4),
          pw.Text(_t(v.resume), style: const pw.TextStyle(fontSize: 9.5)),
        ]),
      ),
      _titre('L\'ESSENTIEL'),
      _lig('Cout d\'une poule prete a pondre (19 semaines)', _f(r.coutParPoule), gras: true),
      _lig('Cout de revient d\'un plateau de 30 oeufs', _f(r.coutPlateau), gras: true),
      _lig('Prix de vente prevu d\'un plateau', _f(p.prixPlateau)),
      _lig(gain ? 'Benefice du cycle' : 'Perte du cycle', _f(r.benefice), gras: true, couleur: gain ? _emeraude : _rouge),
      _lig('Benefice moyen par mois de ponte', _f(r.beneficeMensuelPonte)),
      _lig('Argent a avoir avant de commencer', _f(r.besoinFinancement), gras: true),
      _lig('Mois ou tout l\'argent avance est recupere', r.moisPointMort == null ? 'Pas dans ce cycle' : '${libelleMois(arr, r.moisPointMort!)} sur ${r.moisTotal}'),
      _titre('SEUIL DE RENTABILITE : LES LIMITES A NE PAS DEPASSER'),
      _lig('Prix minimum d\'un plateau', _f(seuils.prixPlateauMin), gras: true),
      _lig('Votre prix prevu', _f(p.prixPlateau)),
      _lig('Plateaux a vendre au minimum', '${_n(seuils.plateauxMinTotal.ceilToDouble())} sur ${_n(r.plateaux)} (${seuils.pctProduction.round()} %)'),
      _lig('Plateaux minimum par jour de ponte', seuils.plateauxMinJour.toStringAsFixed(1)),
      _lig('Taux de ponte maximal minimum', seuils.picMin == null ? 'Impossible, meme a 99 %' : '${seuils.picMin!.round()} %'),
      _lig('Hausse maximale du prix de l\'aliment', r.benefice <= 0 ? 'Deja depassee' : (seuils.hausseAlimentMax == null ? 'Plus de 500 %' : '${seuils.hausseAlimentMax!.round()} %')),
      _lig('Pertes maximales pendant l\'elevage', r.benefice <= 0 ? 'Deja depassees' : (seuils.pertesElevageMax == null ? 'Plus de 90 %' : '${seuils.pertesElevageMax!.round()} %')),
      _titre('CE QU\'IL FAUT RETENIR'),
      for (final c in v.constats) _puce(c),
      _titre('1. DU POUSSIN A 19 SEMAINES (ELEVAGE)'),
      _lig('Etape', 'Cout', c: 'Sacs', d: 'kg/poule', gras: true),
      _trait(),
      for (final e in r.etapes)
        _lig(e.nom, _f(e.cout), c: e.sacs.toStringAsFixed(1), d: e.kgParPoule.toStringAsFixed(2)),
      for (final a in r.autresCoutsA) _lig(a.$1, _f(a.$2)),
      _trait(),
      _lig('Total elevage', _f(r.totalA), gras: true),
      _lig('Poules vivantes a 19 semaines', _n(r.survivantes)),
      _titre('2. LA PONTE'),
      _lig('Oeufs vendables (apres casse)', _n(r.oeufs)),
      _lig('Plateaux de 30', _n(r.plateaux)),
      _lig('Aliment consomme', '${_n(r.kgAlimentB)} kg (${_n(r.sacsB)} sacs)'),
      for (final a in r.coutsB) _lig(a.$1, _f(a.$2)),
      _trait(),
      _lig('Total ponte', _f(r.totalB), gras: true),
      _titre('3. CE QUE VOUS ENCAISSEZ'),
      _lig('Vente des plateaux', _f(r.recettePlateaux)),
      _lig('Vente de ${_n(r.pouleReforme)} poules de reforme', _f(r.recetteReforme)),
      _trait(),
      _lig('Total recettes', _f(r.recetteTotale), gras: true),
      _lig('Total depenses', _f(r.coutTotal), gras: true),
      _lig(gain ? 'Benefice' : 'Perte', _f(r.benefice), gras: true, couleur: gain ? _emeraude : _rouge),
      _titre('4. TROIS SITUATIONS POSSIBLES'),
      _lig('Situation', 'Benefice', c: 'Cout plateau', d: 'Argent a avoir', gras: true),
      _trait(),
      for (final s in sc) ...[
        _lig(s.nom, _f(s.r.benefice), c: _f(s.r.coutPlateau), d: _f(s.r.besoinFinancement), gras: s.nom == 'Normal',
            couleur: s.r.benefice >= 0 ? null : _rouge),
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(_t(s.description), style: pw.TextStyle(fontSize: 7.5, color: _gris)),
        ),
      ],
      _titre('5. PRODUCTION PENDANT LA PONTE (mois de ponte)'),
      _note('Ce tableau ne parle que de la ponte. Le mois de ponte 1 est le premier mois ou les poules pondent : il commence '
          '$semainesDebutPonte semaines apres l\'arrivee des poussins. Poules vivantes : combien il reste de poules. '
          'Taux de ponte : sur 100 poules, combien pondent chaque jour (90 % = 90 oeufs par jour pour 100 poules). '
          'Plateaux par jour : ce qu\'il y a a vendre chaque jour. Plateaux dans le mois : le total du mois.'),
      _ligN([('Mois de ponte', 4), ('Poules vivantes', 2), ('Taux de ponte', 2), ('Plateaux par jour', 2), ('Plateaux dans le mois', 2)], gras: true),
      _trait(),
      for (final m in profil)
        _ligN([
          (libelleMois(arr, m.mois, decalageSemaines: semainesDebutPonte, prefixe: 'Mois de ponte'), 4),
          (_n(m.poules), 2),
          ('${m.taux.round()} %', 2),
          (_n(m.plateauxJour), 2),
          (_n(m.plateauxMois), 2),
        ]),
      _titre('6. ARGENT MOIS PAR MOIS (depuis l\'arrivee des poussins)'),
      _note('Ce tableau compte depuis le jour ou les poussins arrivent : le mois 1 est donc le premier mois d\'elevage, avant que les poules ne pondent. '
          'Ce n\'est pas le meme comptage que le tableau de production. Depenses du mois : ce que vous payez ce mois-la. '
          'Recettes du mois : ce que vous encaissez ce mois-la. Argent depuis le debut : total gagne moins total depense depuis le debut ; '
          '"avances" = de l\'argent est encore investi, "gagnes" = tout est recupere et vous etes en benefice.'),
      _graphique(r),
      pw.SizedBox(height: 6),
      _ligN([('Mois', 4), ('Etape', 3), ('Depenses du mois', 3), ('Recettes du mois', 3), ('Argent depuis le debut', 4)], gras: true),
      _trait(),
      for (final m in r.mois)
        _ligN([
          (libelleMois(arr, m.mois), 4),
          (AnalysePondeuses.phaseMois(m.mois), 3),
          (_f(m.depenses), 3),
          (_f(m.recettes), 3),
          (_cumul(m.cumul), 4),
        ], couleur: m.cumul < 0 ? _rouge : _emeraude),
      ..._conso(r),
      ..._credit(r),
      _titre('POINTS D\'ATTENTION'),
      for (final a in v.attention) _puce(a),
      pw.SizedBox(height: 14),
      pw.Text(_t('Simulation faite avec les chiffres saisis dans le logiciel : ce n\'est pas une garantie de resultat. Genere par Hakili de Antoine Software.'),
          style: pw.TextStyle(fontSize: 8, color: _gris)),
    ];

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(36), build: (_) => contenu));
    final lieu = await getSaveLocation(
      suggestedName: 'Prevision_Pondeuses_${Session.nomFerme.replaceAll(' ', '_')}.pdf',
      acceptedTypeGroups: const [XTypeGroup(label: 'Documents PDF', extensions: ['pdf'])],
      confirmButtonText: 'Enregistrer',
    );
    if (lieu == null) return false;
    var chemin = lieu.path;
    if (!chemin.toLowerCase().endsWith('.pdf')) chemin = '$chemin.pdf';
    await File(chemin).writeAsBytes(await doc.save());
    return true;
  }

  static List<pw.Widget> _credit(ResultatPondeuses r) {
    final e = r.credit;
    if (e == null) return [];
    final s = sectionCredit(e, r.besoinFinancement);
    final t = tableauCredit(e);
    return [
      _titre('8. CREDIT (FINANCEMENT)'),
      for (final l in s.lignes) _lig(l.$1, l.$2),
      _trait(),
      _lig(s.total!.$1, s.total!.$2, gras: true),
      _titre('9. ECHEANCIER DU CREDIT'),
      _note(t.note),
      _ligN([for (var i = 0; i < t.entetes.length; i++) (t.entetes[i], t.flex[i])], gras: true),
      _trait(),
      for (final l in t.lignes) _ligN([for (var i = 0; i < l.length; i++) (l[i], t.flex[i])]),
    ];
  }

  static List<pw.Widget> _conso(ResultatPondeuses r) {
    final t = tableauConso('7. ALIMENT MOIS PAR MOIS (depuis l\'arrivee des poussins)',
        'Le mois 1 commence le jour de l\'arrivee des poussins. Par jour = moyenne du mois pour tout le troupeau, puis pour une seule poule. Les sacs sont des sacs de 50 kg.',
        r.conso, periode: 'Mois');
    return [
      _titre(t.titre),
      _note(t.note),
      _ligN([for (var i = 0; i < t.entetes.length; i++) (t.entetes[i], t.flex[i])], gras: true),
      _trait(),
      for (final l in t.lignes) _ligN([for (var i = 0; i < l.length; i++) (l[i], t.flex[i])]),
    ];
  }

  static pw.Widget _graphique(ResultatPondeuses r) {
    final cumul = [for (final m in r.mois) m.cumul];
    final vmax = cumul.fold<double>(0, math.max);
    final vmin = cumul.fold<double>(0, math.min);
    final plafond = math.max(1.0, math.max(vmax, -vmin));
    final (pas, nb) = echelleAgreable(plafond, 4);
    final bas = vmin < 0 ? -nb : 0;
    return pw.SizedBox(
      height: 200,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings([for (final m in r.mois) '${m.mois}'], marginStart: 20, marginEnd: 20, ticks: true),
          yAxis: pw.FixedAxis([for (var i = bas; i <= nb; i++) i * pas], format: (v) => formaterAxe(v.toDouble()), divisions: true),
        ),
        datasets: [
          pw.LineDataSet(
            legend: 'Argent cumule (FCFA) par mois', color: _emeraude, drawPoints: true, isCurved: false,
            data: [for (var i = 0; i < cumul.length; i++) pw.PointChartValue(i.toDouble(), cumul[i])],
          ),
        ],
      ),
    );
  }
}
