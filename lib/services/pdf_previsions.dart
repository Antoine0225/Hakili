import 'dart:io';

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../metier/previsions.dart';
import '../session.dart';
import '../utilitaires/formats.dart';

/// « Audit financier & recettes » en PDF (graphiques de rentabilité, répartition du capital, projection sur 6 mois).
class PdfPrevisions {
  PdfPrevisions._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _gris = PdfColor.fromHex('#8a9c91');
  static final _emeraude = PdfColor.fromHex('#2f7d4f');
  static const _palette = ['#123229', '#2f7d4f', '#6f7d75', '#b8651f', '#c2691f', '#8a6d2f', '#b3372a', '#4d5f56'];

  static pw.Widget _titre(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)),
      );

  static pw.Widget _barres(List<String> noms, List<double> valeurs) {
    final vmax = valeurs.reduce((a, b) => a > b ? a : b);
    final (pas, nb) = echelleAgreable(vmax, 5);
    return pw.SizedBox(
      height: 210,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(noms, marginStart: 40, marginEnd: 40),
          yAxis: pw.FixedAxis([for (var i = 0; i <= nb; i++) i * pas], format: (v) => formaterAxe(v.toDouble()), divisions: true),
        ),
        datasets: [
          pw.BarDataSet(color: _vert, width: 40, data: [for (var i = 0; i < valeurs.length; i++) pw.PointChartValue(i.toDouble(), valeurs[i])]),
        ],
      ),
    );
  }

  static Future<bool> exporter() async {
    final doc = pw.Document();
    final sujetsActifs = (Previsions.nbSujets - Previsions.nbPertes) < 0 ? 0 : Previsions.nbSujets - Previsions.nbPertes;
    final r = await Previsions.calculer();
    final logo = await LogoPdf.widget();
    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('AUDIT FINANCIER & RECETTES - ${Session.nomFerme.toUpperCase()}',
          style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 14),
    ];
    if (r.chair) {
      final totalPoussins = Previsions.nbSujets * Previsions.prixPoussin;
      final totalSante = sujetsActifs * Previsions.fraisSante;
      final totalAliment = r.cout - totalPoussins - totalSante;
      contenu.add(pw.Text("Duree d'elevage evaluee : ${Previsions.libelleDuree}", style: const pw.TextStyle(fontSize: 10)));
      contenu.add(_titre('Graphique : Rentabilite de la Bande de Chair (FCFA)'));
      contenu.add(_barres(['Capital Investi', "Chiffre d'Affaires", 'Benefice Net'], [r.cout, r.recette, r.benefice < 0 ? 0 : r.benefice]));
      contenu.add(_titre('Graphique : Repartition du Capital Investi'));
      final parts = {
        'Aliment (Demarrage/Croissance/Finition)': totalAliment,
        'Achat des Poussins': totalPoussins,
        'Frais de Sante': totalSante,
      };
      var k = 0;
      contenu.add(pw.SizedBox(
        height: 250,
        child: pw.Chart(
          grid: pw.PieGrid(),
          datasets: [
            for (final e in parts.entries)
              if (e.value > 0)
                pw.PieDataSet(
                  legend: '${e.key} (${milliersAnglais(e.value)} F)', value: e.value,
                  color: PdfColor.fromHex(_palette[k++ % _palette.length]),
                  legendStyle: const pw.TextStyle(fontSize: 8), innerRadius: 40),
          ],
        ),
      ));
    } else {
      contenu.add(_titre('Graphique : Equilibre Comptable Mensuel Reproducteurs (FCFA)'));
      contenu.add(_barres(['Charges Aliment', 'Revenu Brut', 'Benefice Net'], [r.cout, r.recette, r.benefice < 0 ? 0 : r.benefice]));
      contenu.add(_titre('Graphique : Projection du Benefice Cumule sur 6 Mois'));
      final cumul = [for (var i = 1; i <= 6; i++) r.benefice * i];
      final vmax = cumul.reduce((a, b) => a > b ? a : b);
      final vmin = cumul.reduce((a, b) => a < b ? a : b);
      final plafond = vmax > 0 ? vmax : (vmin < 0 ? 0.0 : 1.0);
      final (pas, nb) = echelleAgreable(plafond <= 0 ? 1 : plafond, 5);
      contenu.add(pw.SizedBox(
        height: 220,
        child: pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis.fromStrings([for (var i = 1; i <= 6; i++) 'Mois $i'], marginStart: 30, marginEnd: 30, ticks: true),
            yAxis: pw.FixedAxis([for (var i = (vmin < 0 ? -nb : 0); i <= nb; i++) i * pas], format: (v) => formaterAxe(v.toDouble()), divisions: true),
          ),
          datasets: [
            pw.LineDataSet(
              legend: 'FCFA cumules', color: _emeraude, drawPoints: true, isCurved: false,
              data: [for (var i = 0; i < 6; i++) pw.PointChartValue(i.toDouble(), cumul[i])],
            ),
          ],
        ),
      ));
    }
    contenu.add(pw.SizedBox(height: 20));
    contenu.add(pw.Text('Genere par Hakili de Antoine Software.', style: pw.TextStyle(fontSize: 8, color: _gris)));

    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.letter, margin: const pw.EdgeInsets.all(36), build: (_) => contenu));
    final lieu = await getSaveLocation(
      suggestedName: 'Audit_Financier_${Session.nomFerme.replaceAll(' ', '_')}.pdf',
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
