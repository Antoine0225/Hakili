import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../metier/previsions_pondeuses.dart' show dateLongue;
import '../metier/projet_base.dart';
import '../session.dart';
import '../utilitaires/formats.dart';
import '../utilitaires/texte_pdf.dart';
import 'logo_pdf.dart';

/// Prévision d'un projet (poulet de chair, reproducteurs) en PDF : verdict, chiffres, seuils, scénarios, trésorerie.
class PdfProjet {
  PdfProjet._();

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

  static pw.Widget _lig(String a, String b, {bool gras = false, PdfColor? couleur}) {
    final st = pw.TextStyle(fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(children: [
        pw.Expanded(flex: 6, child: pw.Text(_t(a), style: st)),
        pw.Expanded(flex: 4, child: pw.Text(_t(b), textAlign: pw.TextAlign.right, style: st)),
      ]),
    );
  }

  static pw.Widget _ligN(List<String> cases, List<int> flex, {bool gras = false, PdfColor? couleur}) {
    final st = pw.TextStyle(fontSize: 8.5, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (var i = 0; i < cases.length; i++)
          pw.Expanded(flex: flex[i], child: pw.Text(_t(cases[i]), textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right, style: st)),
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

  static pw.Widget _trait() => pw.Container(height: 0.6, color: PdfColors.grey500, margin: const pw.EdgeInsets.symmetric(vertical: 2));

  static pw.Widget _puce(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('- ', style: const pw.TextStyle(fontSize: 9)),
          pw.Expanded(child: pw.Text(_t(t), style: const pw.TextStyle(fontSize: 9))),
        ]),
      );

  static String _cumul(double c) => c < 0 ? '${_f(c.abs())} avances' : '${_f(c)} gagnes';

  static pw.Widget _graphique(ResultatSimu r) {
    final cumul = [for (final f in r.flux) f.cumul];
    final vmax = cumul.fold<double>(0, math.max);
    final vmin = cumul.fold<double>(0, math.min);
    final plafond = math.max(1.0, math.max(vmax, -vmin));
    final (pas, nb) = echelleAgreable(plafond, 4);
    final bas = vmin < 0 ? -nb : 0;
    return pw.SizedBox(
      height: 200,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings([for (var i = 0; i < r.flux.length; i++) '${i + 1}'], marginStart: 20, marginEnd: 20, ticks: true),
          yAxis: pw.FixedAxis([for (var i = bas; i <= nb; i++) i * pas], format: (v) => formaterAxe(v.toDouble()), divisions: true),
        ),
        datasets: [
          pw.LineDataSet(
            legend: _t('Argent cumule (FCFA) par ${r.periodeNom == 'Semaine' ? 'semaine' : 'mois'}'),
            color: _emeraude, drawPoints: true, isCurved: false,
            data: [for (var i = 0; i < cumul.length; i++) pw.PointChartValue(i.toDouble(), cumul[i])],
          ),
        ],
      ),
    );
  }

  static Future<bool> exporter(ModeleProjet m, Valeurs v, String race) async {
    final r = m.calculer(v);
    final sc = AnalyseProjet.scenarios(m, v);
    final vd = AnalyseProjet.verdict(m, v, sc);
    final seuils = AnalyseProjet.seuils(m, v, r);
    final logo = await LogoPdf.widget();
    final arr = arriveeDe(v);
    final nomFerme = _t(Session.nomFerme.trim().isEmpty ? 'Exploitation avicole' : Session.nomFerme.trim());
    final cv = vd.niveau == 2 ? _emeraude : (vd.niveau == 1 ? _orange : _rouge);
    final titreDoc = _t(m.titre.replaceAll(RegExp(r'[^\x00-\x7FÀ-ÿŒœ]'), '')).trim();

    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('${titreDoc.toUpperCase()} - ${nomFerme.toUpperCase()}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 4),
      pw.Text(_t('Race ou souche : $race'), style: pw.TextStyle(fontSize: 9, color: _gris)),
      if (arr != null) pw.Text(_t('Arrivee des poussins : ${dateLongue(arr)}'), style: pw.TextStyle(fontSize: 9, color: _gris)),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: cv, width: 1.5), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_t(vd.titre), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: cv)),
          pw.SizedBox(height: 4),
          pw.Text(_t(vd.resume), style: const pw.TextStyle(fontSize: 9.5)),
        ]),
      ),
      _titre('L\'ESSENTIEL'),
      for (final c in r.cartes) _lig(c.titre.toLowerCase(), c.valeur, gras: true, couleur: c.ton == 2 ? _rouge : null),
      _titre('SEUIL DE RENTABILITE : LES LIMITES A NE PAS DEPASSER'),
      for (var i = 0; i < seuils.length; i++) _lig(seuils[i].$1, seuils[i].$2, gras: i == 0),
      _titre('CE QU\'IL FAUT RETENIR'),
      for (final c in vd.constats) _puce(c),
      for (final s in r.sections) ...[
        _titre(s.titre),
        for (final l in s.lignes) _lig(l.$1, l.$2),
        if (s.total != null) ...[_trait(), _lig(s.total!.$1, s.total!.$2, gras: true)],
      ],
      for (final t in r.tableaux) ...[
        _titre(t.titre),
        _note(t.note),
        _ligN(t.entetes, t.flex, gras: true),
        _trait(),
        for (final l in t.lignes) _ligN(l, t.flex),
      ],
      _titre('TROIS SITUATIONS POSSIBLES'),
      _ligN(['Situation', 'Argent a avoir', 'Benefice', 'Prix de revient'], [3, 3, 3, 3], gras: true),
      _trait(),
      for (final s in sc) ...[
        _ligN([s.nom, _f(s.r.besoinFinancement), _f(s.r.benefice), _f(s.r.coutUnitaire)], [3, 3, 3, 3], gras: s.nom == 'Normal', couleur: s.r.benefice >= 0 ? null : _rouge),
        pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: pw.Text(_t(s.description), style: pw.TextStyle(fontSize: 7.5, color: _gris))),
      ],
      _titre('TRESORERIE ${r.periodeNom == 'Semaine' ? 'SEMAINE PAR SEMAINE' : 'MOIS PAR MOIS'} (depuis l\'arrivee des poussins)'),
      _note('Ce tableau compte depuis le jour ou les poussins arrivent. Depenses : ce que vous payez sur la periode. Recettes : ce que vous encaissez. '
          'Argent depuis le debut : total gagne moins total depense ; "avances" = de l\'argent est encore investi, "gagnes" = tout est recupere et vous etes en benefice.'),
      _graphique(r),
      pw.SizedBox(height: 6),
      _ligN([r.periodeNom, 'Depenses', 'Recettes', 'Argent depuis le debut'], [4, 3, 3, 4], gras: true),
      _trait(),
      for (final f in r.flux) _ligN([f.label, _f(f.depenses), _f(f.recettes), _cumul(f.cumul)], [4, 3, 3, 4], couleur: f.cumul < 0 ? _rouge : _emeraude),
      _titre('POINTS D\'ATTENTION'),
      for (final a in vd.attention) _puce(a),
      pw.SizedBox(height: 14),
      pw.Text(_t('Simulation faite avec les chiffres saisis dans le logiciel : ce n\'est pas une garantie de resultat. Genere par Hakili de Antoine Software.'),
          style: pw.TextStyle(fontSize: 8, color: _gris)),
    ];

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(36), build: (_) => contenu));
    final lieu = await getSaveLocation(
      suggestedName: 'Prevision_${m.cle}_${Session.nomFerme.replaceAll(' ', '_')}.pdf',
      acceptedTypeGroups: const [XTypeGroup(label: 'Documents PDF', extensions: ['pdf'])],
      confirmButtonText: 'Enregistrer',
    );
    if (lieu == null) return false;
    var chemin = lieu.path;
    if (!chemin.toLowerCase().endsWith('.pdf')) chemin = '$chemin.pdf';
    await File(chemin).writeAsBytes(await doc.save());
    return true;
  }
}
