import 'dart:io';

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/bilans_repo.dart';
import '../data/ventes_repo.dart';
import '../session.dart';
import '../utilitaires/formats.dart';

/// Bilan de marge & bénéfice du Boss en PDF (mêmes rubriques que le logiciel actuel).
class PdfMarge {
  PdfMarge._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _doux = PdfColor.fromHex('#4d5f56');
  static final _gris = PdfColor.fromHex('#6f7d75');
  static final _ligne = PdfColor.fromHex('#e8e2d7');
  static final _grille = PdfColor.fromHex('#d8d1c2');
  static final _creme = PdfColor.fromHex('#faf8f5');
  static final _succes = PdfColor.fromHex('#2f7d4f');
  static final _danger = PdfColor.fromHex('#b3372a');
  static const _palette = ['#123229', '#2f7d4f', '#b8651f', '#b98a1e', '#516758', '#c2691f', '#8a9c91', '#4fb37a'];
  static const _mois = [
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Aout', 'Septembre', 'Octobre', 'Novembre', 'Decembre'
  ];

  static pw.Widget _section(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)),
      );

  static pw.Widget _note(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: _gris)),
      );

  static pw.Widget _lignes(List<List<String>> donnees, {int? gras}) => pw.Table(
        columnWidths: const {0: pw.FixedColumnWidth(330), 1: pw.FixedColumnWidth(150)},
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _ligne, width: 0.4), bottom: pw.BorderSide(color: _ligne, width: 0.4)),
        children: [
          for (var i = 0; i < donnees.length; i++)
            pw.TableRow(children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Text(donnees[i][0],
                      style: pw.TextStyle(fontSize: 10, fontWeight: gras == i ? pw.FontWeight.bold : pw.FontWeight.normal, color: _vert))),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Text(donnees[i][1],
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 10, fontWeight: gras == i ? pw.FontWeight.bold : pw.FontWeight.normal, color: _vert))),
            ]),
        ],
      );

  static pw.Widget _cell(String t, {bool gras = false, bool gauche = false, PdfColor? couleur}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        child: pw.Text(t,
            textAlign: gauche ? pw.TextAlign.left : pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur ?? _vert)),
      );

  static Future<bool> exporter(BilanMarge b, List<Vente> ventes, DateTime debut, DateTime fin,
      String texteDebut, String texteFin) async {
    final moisEntier = debut.day == 1 && debut.year == fin.year && debut.month == fin.month &&
        fin.day == DateTime(fin.year, fin.month + 1, 0).day;
    final libelle = moisEntier ? '${_mois[debut.month - 1]} ${debut.year}' : 'du $texteDebut au $texteFin';
    final suffixe = moisEntier
        ? '${debut.month.toString().padLeft(2, '0')}-${debut.year}'
        : '${texteDebut.replaceAll('/', '-')}_au_${texteFin.replaceAll('/', '-')}';

    final detail = VentesRepo.revenuPeriode(ventes, debut, fin);
    var revenu = detail.beneficePur;
    var revenuManuel = false;
    final periodeCle = '${debut.month.toString().padLeft(2, '0')}/${debut.year}';
    if (moisEntier && b.revenuModifie && periodeCle == b.periode) {
      revenu = b.ca;
      revenuManuel = true;
    }
    final totalCharges = b.totalCharges;
    final net = revenu - totalCharges;
    final base = detail.caBrut > 0 ? detail.caBrut : revenu;
    final margePct = base > 0 ? net / base * 100 : 0.0;
    final couleurNet = net >= 0 ? _succes : _danger;
    final n = DateTime.now();
    final genere = '${jourEnTexte(n)} a ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';

    final logo = await LogoPdf.widget();
    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('BILAN DE MARGE & BENEFICE - ${Session.nomFerme.toUpperCase()}',
          style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 6),
      pw.Text('Periode : $libelle  -  Genere le $genere', style: pw.TextStyle(fontSize: 10, color: _doux)),
      pw.SizedBox(height: 18),
      _section('Revenus de la Caisse :'),
      _lignes([
        ["Chiffre d'affaires des ventes (avec prix d'achat connu)", '${milliersAnglais(detail.caBrut - detail.caSansCout)} FCFA'],
        ["Prix d'achat des marchandises vendues (arrivages)", '- ${milliersAnglais(detail.coutAchat)} FCFA'],
        ['Benefice pur de la Caisse', '${milliersAnglais(detail.beneficePur)} FCFA'],
      ], gras: 2),
    ];
    if (detail.nbSansCout > 0) {
      contenu.add(_note("Attention : ${detail.nbSansCout} vente(s) sans prix d'achat connu (${milliersAnglais(detail.caSansCout)} FCFA) "
          'ne sont pas comptees dans le benefice.'));
    }
    if (detail.beneficeEnAttente > 0.5) {
      contenu.add(_note('Dont ${milliersAnglais(detail.beneficeEnAttente)} FCFA de marge sur des credits pas encore recouvres.'));
    }
    if (revenuManuel) {
      contenu.add(_note('Revenu ajuste manuellement dans le logiciel : ${milliersAnglais(revenu)} FCFA (valeur retenue pour le calcul ci-dessous).'));
    }
    contenu.add(_section('Charges mensuelles :'));
    contenu.add(_lignes([
      ['Electricite & Energie', '${milliersAnglais(b.elec)} FCFA'],
      ['Transport & Logistique', '${milliersAnglais(b.transport)} FCFA'],
      ["Salaires & Main d'oeuvre", '${milliersAnglais(b.salaires)} FCFA'],
      ['Divers & Imprevus', '${milliersAnglais(b.divers)} FCFA'],
    ]));
    if (!(moisEntier && periodeCle == b.periode)) {
      contenu.add(_note('Les charges reprises sont celles saisies dans le logiciel (periode de saisie : ${b.periode}).'));
    }
    contenu.add(pw.SizedBox(height: 12));
    pw.Widget total(String t, String v, PdfColor c) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.RichText(
              text: pw.TextSpan(style: pw.TextStyle(fontSize: 12, color: _vert), children: [
            pw.TextSpan(text: '$t : '),
            pw.TextSpan(text: v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: c)),
          ])),
        );
    contenu.add(total('Total des Charges', '${milliersAnglais(totalCharges)} FCFA', _danger));
    contenu.add(total('Net dans la Poche du Boss', '${milliersAnglais(net)} FCFA', couleurNet));
    contenu.add(total("Marge Nette (sur le chiffre d'affaires de ${milliersAnglais(detail.caBrut)} FCFA)",
        '${margePct.toStringAsFixed(1)} %', couleurNet));

    // barres Revenu / Charges / Net
    contenu.add(pw.SizedBox(height: 12));
    final valeurs = [revenu, totalCharges, net < 0 ? 0.0 : net];
    final (pas, nb) = echelleAgreable(valeurs.reduce((a, c) => a > c ? a : c), 5);
    contenu.add(pw.SizedBox(
      height: 190,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(['Revenu', 'Charges', 'Net Poche Boss'], marginStart: 40, marginEnd: 40),
          yAxis: pw.FixedAxis([for (var i = 0; i <= nb; i++) i * pas], format: (v) => formaterAxe(v.toDouble()), divisions: true),
        ),
        datasets: [
          pw.BarDataSet(
            color: _vert, width: 40,
            data: [for (var i = 0; i < 3; i++) pw.PointChartValue(i.toDouble(), valeurs[i])],
          ),
        ],
      ),
    ));

    if (detail.parProduit.isNotEmpty) {
      contenu.add(_section('Detail par produit sur la periode :'));
      final tries = detail.parProduit.entries.toList()..sort((a, c) => c.value.benefice.compareTo(a.value.benefice));
      var unSansCout = false;
      final lignes = <pw.TableRow>[
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _vert),
          repeat: true,
          children: [
            for (final t in ['Produit', 'Qte vendue', 'CA (FCFA)', "Prix d'achat (FCFA)", 'Benefice pur (FCFA)'])
              _cell(t, gras: true, couleur: PdfColors.grey100),
          ],
        ),
      ];
      for (var i = 0; i < tries.length; i++) {
        final e = tries[i];
        final pr = e.value;
        final etoile = pr.caSansCout > 0 ? ' *' : '';
        if (pr.caSansCout > 0) unSansCout = true;
        lignes.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _creme),
          children: [
            _cell('${e.key}$etoile', gras: true, gauche: true),
            _cell(milliersAnglais(pr.qte, 1)),
            _cell(milliersAnglais(pr.ca)),
            _cell(milliersAnglais(pr.cout)),
            _cell(milliersAnglais(pr.benefice), gras: true),
          ],
        ));
      }
      contenu.add(pw.Table(
        border: pw.TableBorder.all(color: _grille, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(170), 1: pw.FixedColumnWidth(60), 2: pw.FixedColumnWidth(95),
          3: pw.FixedColumnWidth(100), 4: pw.FixedColumnWidth(105),
        },
        children: lignes,
      ));
      if (unSansCout) {
        contenu.add(_note("* Contient des ventes sans prix d'achat connu, non comptees dans le benefice de ce produit "
            '(elles figurent dans la colonne CA).'));
      }
      final positifs = tries.where((e) => e.value.benefice > 0).toList();
      if (positifs.isNotEmpty) {
        var k = 0;
        contenu.add(pw.SizedBox(height: 8));
        contenu.add(pw.SizedBox(
          height: 240,
          child: pw.Chart(
            grid: pw.PieGrid(),
            datasets: [
              for (final e in positifs)
                pw.PieDataSet(
                  legend: '${e.key} (${milliersAnglais(e.value.benefice)} F)',
                  value: e.value.benefice,
                  color: PdfColor.fromHex(_palette[k++ % _palette.length]),
                  legendStyle: const pw.TextStyle(fontSize: 8),
                  innerRadius: 40,
                ),
            ],
          ),
        ));
      }
    }
    contenu.add(pw.SizedBox(height: 25));
    contenu.add(pw.Text('Genere par Hakili de Antoine Software.',
        style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColor.fromHex('#8a9c91'))));

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.letter, margin: const pw.EdgeInsets.all(40), build: (_) => contenu));

    final lieu = await getSaveLocation(
      suggestedName: 'Bilan_Marge_Boss_$suffixe.pdf',
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
