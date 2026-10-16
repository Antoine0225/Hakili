import 'dart:io';

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/ventes_repo.dart';
import '../session.dart';
import '../utilitaires/formats.dart';

/// Les documents PDF de la caisse (même contenu que le logiciel actuel).
/// Les PDF utilisent la police standard (sans emojis) : les symboles sont remplacés par du texte.
class PdfCaisse {
  PdfCaisse._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _vertSucces = PdfColor.fromHex('#2f7d4f');
  static final _orange = PdfColor.fromHex('#c2691f');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _doux = PdfColor.fromHex('#4d5f56');
  static final _gris = PdfColor.fromHex('#8a9c91');
  static final _grille = PdfColor.fromHex('#d8d1c2');
  static final _creme = PdfColor.fromHex('#faf8f5');

  /// Demande où enregistrer puis écrit le fichier. Renvoie le chemin, ou null si on annule.
  static Future<String?> _enregistrer(String nomDefaut, String titre, List<int> octets) async {
    final lieu = await getSaveLocation(
      suggestedName: nomDefaut,
      acceptedTypeGroups: const [XTypeGroup(label: 'Documents PDF', extensions: ['pdf'])],
      confirmButtonText: 'Enregistrer',
    );
    if (lieu == null) return null;
    var chemin = lieu.path;
    if (!chemin.toLowerCase().endsWith('.pdf')) chemin = '$chemin.pdf';
    await File(chemin).writeAsBytes(octets);
    return chemin;
  }

  static const _palette = [
    '#123229', '#2f7d4f', '#b8651f', '#b98a1e', '#516758', '#c2691f', '#8a9c91', '#4fb37a'
  ];

  // ------------------------------------------------------------------ JOURNAL ANALYTIQUE
  /// Renvoie true si le fichier a été enregistré.
  static Future<bool> exporterJournal(
      List<Vente> ventes, DateTime debut, DateTime fin, String texteDebut, String texteFin) async {
    final doc = pw.Document();
    final nom = Session.nomFerme.toUpperCase();

    final dansPeriode = <Vente>[];
    for (final v in ventes) {
      final d = lireJma(v.date.trim());
      if (d != null && !d.isBefore(debut) && !d.isAfter(fin)) dansPeriode.add(v);
    }

    var encaisse = 0.0, creances = 0.0, ca = 0.0;
    final caParProduit = <String, double>{};
    final encaisseParJour = <DateTime, double>{};
    for (final v in dansPeriode) {
      final horsCA = ligneEstHorsChiffreAffaires(v.type);
      if (!horsCA) {
        ca += v.total;
        caParProduit[v.type] = (caParProduit[v.type] ?? 0) + v.total;
      }
      if (v.estCredit) {
        creances += (v.total - v.montantRegle) < 0 ? 0 : (v.total - v.montantRegle);
      } else {
        encaisse += v.total;
        final d = lireJma(v.date.trim())!;
        final j = DateTime(d.year, d.month, d.day);
        encaisseParJour[j] = (encaisseParJour[j] ?? 0) + v.total;
      }
    }
    caParProduit.removeWhere((_, v) => v <= 0);

    pw.Widget cellule(String t, {bool gras = false, bool gauche = false, PdfColor? couleur}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 3),
          child: pw.Text(t,
              textAlign: gauche ? pw.TextAlign.left : pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur ?? _vert)),
        );

    final logo = await LogoPdf.widget();
    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('JOURNAL ANALYTIQUE DE CAISSE - $nom',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _vertSucces)),
      pw.SizedBox(height: 6),
      pw.Text("Periode d'audit : du $texteDebut au $texteFin", style: pw.TextStyle(fontSize: 10, color: _doux)),
      pw.SizedBox(height: 20),
    ];

    if (dansPeriode.isEmpty) {
      contenu.add(pw.Text('Aucune operation comptable recensee sur cette plage de dates.',
          style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: _vert)));
    } else {
      final lignes = <pw.TableRow>[
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _vert),
          children: [
            for (final t in ['Date', 'Designation Marchandise / Client', 'Quantite', 'P.U. (F)', 'Reglement', 'Total (FCFA)'])
              cellule(t, gras: true, couleur: PdfColors.grey100),
          ],
        ),
      ];
      for (var i = 0; i < dansPeriode.length; i++) {
        final v = dansPeriode[i];
        final client = v.client.isEmpty ? 'Client Comptant' : v.client;
        lignes.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _creme),
          children: [
            cellule(v.date),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 3),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(v.type, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _vert)),
                pw.Text(v.estCredit ? 'Debiteur : $client' : 'Client : $client',
                    style: pw.TextStyle(fontSize: 8, color: v.estCredit ? _orange : PdfColor.fromHex('#6f7d75'))),
              ]),
            ),
            cellule(milliersAnglais(v.qte)),
            cellule(milliersAnglais(v.pu)),
            cellule(v.reglement.replaceAll('À', 'A')),
            cellule(milliersAnglais(v.total), gras: true),
          ],
        ));
      }
      contenu.add(pw.Table(
        border: pw.TableBorder.all(color: _grille, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(60), 1: pw.FixedColumnWidth(185), 2: pw.FixedColumnWidth(55),
          3: pw.FixedColumnWidth(60), 4: pw.FixedColumnWidth(70), 5: pw.FixedColumnWidth(90),
        },
        children: lignes,
      ));
      contenu.add(pw.SizedBox(height: 20));

      if (caParProduit.isNotEmpty) {
        contenu.add(pw.Text("REPARTITION DU CHIFFRE D'AFFAIRES PAR PRODUIT :",
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)));
        contenu.add(pw.SizedBox(height: 8));
        var k = 0;
        contenu.add(pw.SizedBox(
          height: 260,
          child: pw.Chart(
            grid: pw.PieGrid(),
            datasets: [
              for (final e in caParProduit.entries)
                pw.PieDataSet(
                  legend: '${e.key} (${milliersAnglais(e.value)} F)',
                  value: e.value,
                  color: PdfColor.fromHex(_palette[k++ % _palette.length]),
                  legendStyle: const pw.TextStyle(fontSize: 8),
                  innerRadius: 40,
                ),
            ],
          ),
        ));
        contenu.add(pw.SizedBox(height: 10));
      }

      final jours = encaisseParJour.keys.toList()..sort();
      if (jours.length >= 2) {
        contenu.add(pw.Text('TENDANCE DE LA TRESORERIE ENCAISSEE :',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)));
        contenu.add(pw.SizedBox(height: 8));
        final vmax = jours.map((j) => encaisseParJour[j]!).reduce((a, b) => a > b ? a : b);
        final (pas, nb) = echelleAgreable(vmax, 5);
        final pasLabel = (jours.length / 8).ceil();
        contenu.add(pw.SizedBox(
          height: 200,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis.fromStrings(
                [for (var i = 0; i < jours.length; i++) (i % pasLabel == 0) ? '${jours[i].day}/${jours[i].month}' : ''],
                marginStart: 20, marginEnd: 20, ticks: true,
              ),
              yAxis: pw.FixedAxis(
                [for (var i = 0; i <= nb; i++) i * pas],
                format: (v) => formaterAxe(v.toDouble()), divisions: true,
              ),
            ),
            datasets: [
              pw.LineDataSet(
                legend: 'FCFA / jour', color: _vertSucces, drawPoints: true, isCurved: false,
                data: [for (var i = 0; i < jours.length; i++) pw.PointChartValue(i.toDouble(), encaisseParJour[jours[i]]!)],
              ),
            ],
          ),
        ));
        contenu.add(pw.SizedBox(height: 10));
      }

      contenu.add(pw.Text('SOLDE DE CLOTURE DE PERIODE :',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)));
      contenu.add(pw.SizedBox(height: 8));
      contenu.add(pw.RichText(
        text: pw.TextSpan(style: pw.TextStyle(fontSize: 10, color: _vert), children: [
          const pw.TextSpan(text: '- Total Fonds Encaisses (Tresorerie active) : '),
          pw.TextSpan(text: '${milliersAnglais(encaisse)} FCFA\n',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _vertSucces)),
          const pw.TextSpan(text: '- Creances clients restant a recouvrer : '),
          pw.TextSpan(text: '${milliersAnglais(creances)} FCFA\n',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _orange)),
          pw.TextSpan(
              text: "CHIFFRE D'AFFAIRES CUMULE : ${milliersAnglais(ca)} FCFA",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ]),
      ));
    }
    contenu.add(pw.SizedBox(height: 25));
    contenu.add(pw.Text('Genere par Hakili de Antoine Software.',
        style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: _gris)));

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => contenu,
    ));

    final nomFichier = 'Journal_Caisse_${texteDebut.replaceAll('/', '-')}_au_${texteFin.replaceAll('/', '-')}.pdf';
    return await _enregistrer(nomFichier, "Choisir l'emplacement et le nom de votre Journal de Caisse", await doc.save()) != null;
  }

  // ------------------------------------------------------------------ TICKET CLIENT
  static Future<bool> ticketClient(Vente v, int numero) async {
    final doc = pw.Document();
    final statut = v.estCredit ? 'Credit (${v.client})' : v.reglement.replaceAll('À', 'A');
    final items = [
      ["Date de l'operation :", v.date],
      ['Type de produit :', v.type],
      ['Quantite livree :', milliersAnglais(v.qte, 1)],
      ['Prix Unitaire :', '${milliersAnglais(v.pu)} F'],
      ['Mode de reglement :', statut],
    ];

    final logoTicket = await LogoPdf.widget(hauteur: 38, centre: true);
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(226, 450, marginLeft: 12, marginRight: 12, marginTop: 15, marginBottom: 12),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        if (logoTicket != null) ...[logoTicket, pw.SizedBox(height: 6)],
        pw.Text(Session.nomFerme.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _vert)),
        pw.SizedBox(height: 15),
        pw.Table(
          columnWidths: const {0: pw.FixedColumnWidth(100), 1: pw.FixedColumnWidth(102)},
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColor.fromHex('#f3efe6'), width: 0.5)),
          children: [
            for (final it in items)
              pw.TableRow(children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    child: pw.Text(it[0], style: pw.TextStyle(fontSize: 9, color: _doux))),
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    child: pw.Text(it[1],
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _vert))),
              ]),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _creme, border: pw.Border.all(color: _vert, width: 1)),
          child: pw.Text('TOTAL NET : ${milliersAnglais(v.total)} FCFA',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)),
        ),
        pw.SizedBox(height: 25),
        pw.Text('Merci de votre confiance !',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: _vertSucces)),
        pw.SizedBox(height: 10),
        pw.Text('Genere par Hakili de Antoine Software',
            textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7, color: _gris)),
      ]),
    ));

    final premier = v.type.split(' ').first;
    final nomFichier = 'Ticket_${v.date.replaceAll('/', '-')}_${premier}_$numero.pdf';
    return await _enregistrer(nomFichier, 'Nommer et enregistrer le Ticket Client', await doc.save()) != null;
  }
}
