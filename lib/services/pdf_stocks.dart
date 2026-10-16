import 'dart:io';

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/arrivages_repo.dart';
import '../data/stock_repo.dart';
import '../session.dart';
import '../utilitaires/formats.dart';

/// Rapport PDF « Arrivages & Stocks » (mêmes sections que le logiciel actuel).
class PdfStocks {
  PdfStocks._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _doux = PdfColor.fromHex('#4d5f56');
  static final _gris = PdfColor.fromHex('#8a9c91');
  static final _grille = PdfColor.fromHex('#d8d1c2');
  static final _creme = PdfColor.fromHex('#faf8f5');
  static const _palette = ['#123229', '#2f7d4f', '#b8651f', '#b98a1e', '#516758', '#c2691f', '#8a9c91', '#4fb37a'];

  static pw.Widget _cell(String t, {bool gras = false, bool gauche = false, PdfColor? couleur}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        child: pw.Text(t,
            textAlign: gauche ? pw.TextAlign.left : pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur ?? _vert)),
      );

  static pw.Widget _tableau(List<String> colonnes, List<double> largeurs, List<List<pw.Widget>> lignes) {
    return pw.Table(
      border: pw.TableBorder.all(color: _grille, width: 0.5),
      columnWidths: {for (var i = 0; i < largeurs.length; i++) i: pw.FixedColumnWidth(largeurs[i])},
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _vert),
          repeat: true,
          children: [for (final c in colonnes) _cell(c, gras: true, couleur: PdfColors.grey100)],
        ),
        for (var i = 0; i < lignes.length; i++)
          pw.TableRow(decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _creme), children: lignes[i]),
      ],
    );
  }

  static pw.Widget _section(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)),
      );

  static Future<bool> exporterArrivages(
      List<Arrivage> arrivages, DateTime debut, DateTime fin, String texteDebut, String texteFin) async {
    final doc = pw.Document();
    final nbJours = (fin.difference(debut).inDays + 1) < 1 ? 1 : fin.difference(debut).inDays + 1;
    final n = DateTime.now();
    final genere = '${jourEnTexte(n)} a ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';

    final logo = await LogoPdf.widget();
    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('RAPPORT DES ARRIVAGES & STOCKS - ${Session.nomFerme.toUpperCase()}',
          style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 6),
      pw.Text('Periode : du $texteDebut au $texteFin  -  Genere le $genere', style: pw.TextStyle(fontSize: 10, color: _doux)),
      pw.SizedBox(height: 16),
    ];

    if (arrivages.isEmpty) {
      contenu.add(pw.Text('Aucun arrivage enregistre sur cette periode.',
          style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: _vert)));
    } else {
      // synthèse par produit
      final synthese = <String, ({int nb, double qte, double depense, bool kilos, double sacs})>{};
      for (final a in arrivages) {
        final kilos = a.unite == 'kilo' || a.unite == 'sac';
        final s = synthese[a.produit] ?? (nb: 0, qte: 0.0, depense: 0.0, kilos: kilos, sacs: 0.0);
        synthese[a.produit] = (
          nb: s.nb + 1,
          qte: s.qte + a.quantiteAjoutee,
          depense: s.depense + a.totalAchete,
          kilos: kilos,
          sacs: s.sacs + (a.poidsSac > 0 ? a.quantiteSaisie : 0),
        );
      }
      final tries = synthese.entries.toList()..sort((a, b) => b.value.depense.compareTo(a.value.depense));

      contenu.add(_section('QUANTITES DE MARCHANDISES RECUES PAR PRODUIT'));
      var depenseTotale = 0.0;
      final lignes1 = <List<pw.Widget>>[];
      for (final e in tries) {
        final s = e.value;
        final u = s.kilos ? 'kg' : 'piece(s)';
        final coutMoyen = s.qte > 0 ? s.depense / s.qte : 0.0;
        depenseTotale += s.depense;
        lignes1.add([
          _cell(e.key, gras: true, gauche: true),
          _cell('${s.nb}'),
          _cell('${milliersAnglais(s.qte, 1)} $u${s.sacs > 0 ? '\n(${milliersAnglais(s.sacs)} sac(s))' : ''}', gras: true),
          _cell(milliersAnglais(s.depense)),
          _cell(milliersAnglais(coutMoyen)),
          _cell('${milliersAnglais(s.qte / nbJours, 2)} $u'),
        ]);
      }
      contenu.add(_tableau(
          ['Produit', 'Nb arrivages', 'Quantite totale recue', 'Depense totale (F)', 'Cout moyen unitaire (F)', 'Moyenne / jour'],
          [130, 55, 105, 90, 85, 75], lignes1));
      contenu.add(pw.SizedBox(height: 4));
      contenu.add(pw.Text('Moyenne / jour calculee sur les $nbJours jour(s) de la periode.',
          style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColor.fromHex('#6f7d75'))));

      // donut des dépenses
      var k = 0;
      contenu.add(pw.SizedBox(height: 8));
      contenu.add(pw.SizedBox(
        height: 250,
        child: pw.Chart(
          grid: pw.PieGrid(),
          datasets: [
            for (final e in tries)
              if (e.value.depense > 0)
                pw.PieDataSet(
                  legend: '${e.key} (${milliersAnglais(e.value.depense)} F)',
                  value: e.value.depense,
                  color: PdfColor.fromHex(_palette[k++ % _palette.length]),
                  legendStyle: const pw.TextStyle(fontSize: 8),
                  innerRadius: 40,
                ),
          ],
        ),
      ));

      // dépense cumulée
      if (nbJours > 1) {
        final parJour = <DateTime, double>{};
        for (final a in arrivages) {
          final d = lireJma(a.date);
          if (d == null) continue;
          final j = DateTime(d.year, d.month, d.day);
          parJour[j] = (parJour[j] ?? 0) + a.totalAchete;
        }
        final jours = parJour.keys.toList()..sort();
        if (jours.length >= 2) {
          var cumul = 0.0;
          final valeurs = <double>[];
          for (final j in jours) {
            cumul += parJour[j]!;
            valeurs.add(cumul);
          }
          final (pas, nb) = echelleAgreable(valeurs.last, 5);
          final pasLabel = (jours.length / 8).ceil();
          contenu.add(pw.SizedBox(height: 10));
          contenu.add(pw.SizedBox(
            height: 200,
            child: pw.Chart(
              grid: pw.CartesianGrid(
                xAxis: pw.FixedAxis.fromStrings(
                  [for (var i = 0; i < jours.length; i++) (i % pasLabel == 0) ? '${jours[i].day}/${jours[i].month}' : ''],
                  marginStart: 20, marginEnd: 20, ticks: true),
                yAxis: pw.FixedAxis([for (var i = 0; i <= nb; i++) i * pas],
                    format: (v) => formaterAxe(v.toDouble()), divisions: true),
              ),
              datasets: [
                pw.LineDataSet(
                  legend: 'FCFA cumules', color: _cuivre, drawPoints: true, isCurved: false,
                  data: [for (var i = 0; i < jours.length; i++) pw.PointChartValue(i.toDouble(), valeurs[i])],
                ),
              ],
            ),
          ));
        }
      }

      // détail
      contenu.add(_section('DETAIL DES ARRIVAGES'));
      final lignes2 = <List<pw.Widget>>[];
      for (final a in arrivages) {
        final u = StockRepo.libelleUnite(a.unite);
        final detail = a.poidsSac > 0
            ? '${milliersAnglais(a.quantiteSaisie)} sac(s) x ${milliersAnglais(a.poidsSac, 1)} kg = ${milliersAnglais(a.quantiteAjoutee, 1)} kg'
            : '${milliersAnglais(a.quantiteAjoutee, 1)} $u';
        lignes2.add([
          _cell(a.date),
          _cell(a.produit, gras: true, gauche: true),
          _cell(detail),
          _cell('${milliersAnglais(a.coutUnitaire)} / ${u == 'kg' ? 'kg' : 'piece'}'),
          _cell(milliersAnglais(a.totalAchete), gras: true),
        ]);
      }
      contenu.add(_tableau(
          ['Date', 'Produit', 'Quantite recue', 'Cout unitaire (F)', 'Total achete (F)'], [65, 150, 135, 90, 100], lignes2));
      contenu.add(pw.SizedBox(height: 16));
      contenu.add(pw.Text('BILAN DE LA PERIODE :', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)));
      contenu.add(pw.SizedBox(height: 6));
      contenu.add(pw.Text(
          "- Nombre d'arrivages enregistres : ${arrivages.length}\n"
          "- Depense totale d'achat : ${milliersAnglais(depenseTotale)} FCFA",
          style: pw.TextStyle(fontSize: 10, color: _vert)));
    }
    contenu.add(pw.SizedBox(height: 25));
    contenu.add(pw.Text('Genere par Hakili de Antoine Software.',
        style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: _gris)));

    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.letter, margin: const pw.EdgeInsets.all(36), build: (_) => contenu));

    final lieu = await getSaveLocation(
      suggestedName: 'Arrivages_Stock_${texteDebut.replaceAll('/', '-')}_au_${texteFin.replaceAll('/', '-')}.pdf',
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
