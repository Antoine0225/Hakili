import 'dart:io';

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../metier/calendrier_fetes.dart';
import '../metier/plan_fete.dart';
import '../session.dart';
import '../utilitaires/formats.dart';

/// Le planning d'une fête en PDF (résumé, chiffres, calendrier des achats et des soins).
/// Le texte reste simple (pas d'émojis) car le PDF n'utilise que les polices de base.
class PdfPlanning {
  PdfPlanning._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _gris = PdfColor.fromHex('#6f7d75');

  static pw.Widget _titre(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)),
      );

  static pw.Widget _ligne(String a, String b, {bool fort = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(a, style: pw.TextStyle(fontSize: 10, fontWeight: fort ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(b, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static Future<bool> exporter(PlanFete plan, ChiffresPlan c) async {
    final doc = pw.Document();
    final auj = aujourdhui();
    final etapes = plan.etapes(chiffres: c);
    final logo = await LogoPdf.widget();
    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('PLANNING ${plan.occasion.toUpperCase()} - ${Session.nomFerme.toUpperCase()}',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 4),
      pw.Text('Fete le ${jourEnTexte(plan.dateFete)} - ${plan.cible} poulets a vendre - cycle ${dureesChairLibelle(plan.cycle)}',
          style: pw.TextStyle(fontSize: 10, color: _gris)),
      _titre('Les dates a retenir'),
      _ligne('Reception des poussins', jourEnTexte(plan.dateReception), fort: true),
      _ligne('Poulets prets a vendre', jourEnTexte(plan.dateVente), fort: true),
      _ligne('Poussins a commander (avec ${plan.mortalitePct.toStringAsFixed(0)} % de pertes prevues)', '${c.poussins}'),
      _titre('Aliment a prevoir'),
      _ligne('Demarrage', '${c.kgDemarrage.toStringAsFixed(0)} kg  -  ${c.sacsDemarrage} sac(s)'),
      _ligne('Croissance', '${c.kgCroissance.toStringAsFixed(0)} kg  -  ${c.sacsCroissance} sac(s)'),
      _ligne('Finition', '${c.kgFinition.toStringAsFixed(0)} kg  -  ${c.sacsFinition} sac(s)'),
      _ligne('Total', '${c.kgTotal.toStringAsFixed(0)} kg  -  ${c.sacsTotal} sac(s) de 50 kg', fort: true),
      _titre('Estimation financiere (avec vos prix de la page Previsions)'),
      _ligne('Achat des poussins', fmtF(c.coutPoussins, unite: 'FCFA')),
      _ligne("Alimentation", fmtF(c.coutAliment, unite: 'FCFA')),
      _ligne('Sante', fmtF(c.coutSante, unite: 'FCFA')),
      _ligne('Capital a investir', fmtF(c.capital, unite: 'FCFA'), fort: true),
      _ligne("Chiffre d'affaires prevu", fmtF(c.recette, unite: 'FCFA'), fort: true),
      _ligne('Benefice net estime', fmtF(c.benefice, unite: 'FCFA'), fort: true),
      _titre('Calendrier'),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromHex('#d9d3c5'), width: 0.5),
        columnWidths: {0: const pw.FixedColumnWidth(62), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(4), 3: const pw.FixedColumnWidth(50)},
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _vert),
            children: [
              for (final t in ['Date', 'Etape', 'Detail', 'Dans'])
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                ),
            ],
          ),
          for (final e in etapes)
            pw.TableRow(children: [
              for (final t in [
                jourEnTexte(e.date),
                _sansEmoji(e.titre),
                _sansEmoji(e.detail),
                () {
                  final n = CalendrierFetes.jours(auj, e.date);
                  return n < 0 ? 'passe' : (n == 0 ? "aujourd'hui" : '$n j');
                }(),
              ])
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t, style: const pw.TextStyle(fontSize: 9))),
            ]),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Text(
          'Dates des fetes musulmanes indicatives (selon la lune, a 1 jour pres). Chiffres estimes : ils dependent des prix saisis dans Previsions.',
          style: pw.TextStyle(fontSize: 8, color: _gris)),
      pw.SizedBox(height: 4),
      pw.Text('Genere par Hakili de Antoine Software.', style: pw.TextStyle(fontSize: 8, color: _gris)),
    ];

    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(36), build: (_) => contenu));
    final lieu = await getSaveLocation(
      suggestedName: 'Planning_${plan.occasion.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_${plan.dateFete.year}.pdf',
      acceptedTypeGroups: const [XTypeGroup(label: 'Documents PDF', extensions: ['pdf'])],
      confirmButtonText: 'Enregistrer',
    );
    if (lieu == null) return false;
    var chemin = lieu.path;
    if (!chemin.toLowerCase().endsWith('.pdf')) chemin = '$chemin.pdf';
    await File(chemin).writeAsBytes(await doc.save());
    return true;
  }

  static String dureesChairLibelle(String cycle) => cycle == '45' ? '30-45 jours' : '3 mois';

  /// Retire les accents hors Latin-1 et les symboles que la police de base du PDF ne sait pas dessiner.
  static String _sansEmoji(String t) => t
      .replaceAll('œ', 'oe')
      .replaceAll('Œ', 'Oe')
      .replaceAll('’', "'")
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'[^ -ÿ]'), '')
      .trim();
}
