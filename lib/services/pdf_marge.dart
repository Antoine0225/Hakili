import 'dart:io';
import 'dart:math' as math;

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/bilans_repo.dart';
import '../data/ventes_repo.dart';
import '../metier/analyse_rapports.dart';
import '../session.dart';
import '../utilitaires/formats.dart';
import '../utilitaires/texte_pdf.dart';

/// Bilan de marge & bénéfice du Boss en PDF.
/// Même police simple que les autres PDF de Hakili (sans accents ni emojis) : tous les textes passent par `sansAccents`.
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
  static final _clair = PdfColor.fromHex('#d9e4dc');
  static const _palette = ['#123229', '#2f7d4f', '#b8651f', '#b98a1e', '#516758', '#c2691f', '#8a9c91', '#4fb37a'];

  static String _a(String t) => sansAccents(t);
  static String _f(num v) => fmtF(v, unite: 'FCFA');
  static String _pct(double v) => '${v.toStringAsFixed(1)} %';

  static pw.Widget _section(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(_a(t), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)),
      );

  static pw.Widget _note(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(_a(t), style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: _gris)),
      );

  static pw.Widget _cell(String t, {bool gras = false, bool gauche = false, PdfColor? couleur, bool droite = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 5),
        child: pw.Text(_a(t),
            textAlign: droite ? pw.TextAlign.right : (gauche ? pw.TextAlign.left : pw.TextAlign.center),
            style: pw.TextStyle(fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur ?? _vert)),
      );

  static pw.TableRow _enteteTable(List<String> titres, {int alignerDroiteDes = 1}) => pw.TableRow(
        decoration: pw.BoxDecoration(color: _vert),
        repeat: true,
        children: [
          for (var i = 0; i < titres.length; i++)
            _cell(titres[i], gras: true, couleur: PdfColors.grey100, gauche: i == 0, droite: i >= alignerDroiteDes),
        ],
      );

  static pw.Widget _lignes(List<List<String>> d, {Set<int> gras = const {}, Map<int, PdfColor> couleurs = const {}}) =>
      pw.Table(
        columnWidths: const {0: pw.FixedColumnWidth(360), 1: pw.FixedColumnWidth(172)},
        border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _ligne, width: 0.4), bottom: pw.BorderSide(color: _ligne, width: 0.4)),
        children: [
          for (var i = 0; i < d.length; i++)
            pw.TableRow(
              decoration: gras.contains(i) ? pw.BoxDecoration(color: _creme) : null,
              children: [
                _cell(d[i][0], gauche: true, gras: gras.contains(i)),
                _cell(d[i][1], droite: true, gras: gras.contains(i), couleur: couleurs[i]),
              ],
            ),
        ],
      );

  static pw.Widget _kpi(String titre, String valeur, String sous, PdfColor couleur, {bool fort = false}) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: fort ? _vert : _creme,
            border: pw.Border.all(color: fort ? _vert : _grille, width: 0.6),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(_a(titre), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: fort ? _clair : _gris)),
            pw.SizedBox(height: 5),
            pw.Text(_a(valeur), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: fort ? PdfColors.white : couleur)),
            pw.SizedBox(height: 4),
            pw.Text(_a(sous), style: pw.TextStyle(fontSize: 7.5, color: fort ? _clair : _gris)),
          ]),
        ),
      );

  static String _evolution(LigneComparaison l) {
    final e = l.evolution;
    if (l.precedent == null) return '-';
    if (e == null) return 'n/d';
    final signe = e > 0 ? '+' : '';
    return l.enPourcent ? '$signe${e.toStringAsFixed(1)} pts' : '$signe${e.toStringAsFixed(1)} %';
  }

  static String _montantLigne(LigneComparaison l, double v) => l.enPourcent ? _pct(v) : _f(v);

  /// Barres verticales « CA / bénéfice pur » sur 6 mois, construites avec de simples boîtes (aucun risque de compatibilité).
  static pw.Widget _barresMensuelles(List<PointMensuel> pts) {
    const hMax = 105.0;
    var vmax = 0.0;
    for (final p in pts) {
      vmax = math.max(vmax, math.max(p.ca, p.benefice));
    }
    if (vmax <= 0) return _note('Aucune vente enregistree sur ces 6 mois : pas de graphique.');
    pw.Widget barre(double v, PdfColor c) {
      final h = v > 0 ? math.max(1.5, v / vmax * hMax) : 0.0;
      return pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text(v > 0 ? formaterAxe(v) : '', style: pw.TextStyle(fontSize: 6.5, color: _doux)),
        pw.SizedBox(height: 1.5),
        pw.Container(width: 17, height: h, color: c),
      ]);
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(children: [
        pw.Container(width: 8, height: 8, color: _vert),
        pw.SizedBox(width: 4),
        pw.Text("Chiffre d'affaires facture", style: pw.TextStyle(fontSize: 8, color: _doux)),
        pw.SizedBox(width: 14),
        pw.Container(width: 8, height: 8, color: _cuivre),
        pw.SizedBox(width: 4),
        pw.Text('Benefice pur', style: pw.TextStyle(fontSize: 8, color: _doux)),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        for (final p in pts)
          pw.SizedBox(
            height: hMax + 34,
            child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                barre(p.ca, _vert),
                pw.SizedBox(width: 3),
                barre(math.max(0.0, p.benefice), _cuivre),
              ]),
              pw.Container(width: 80, height: 0.6, color: _grille),
              pw.SizedBox(height: 3),
              pw.Text(_a(p.etiquette), style: pw.TextStyle(fontSize: 8, color: _doux)),
            ]),
          ),
      ]),
    ]);
  }

  /// Trois barres horizontales : revenu retenu, charges, net.
  static pw.Widget _cascade(double revenu, double charges, double net) {
    final vmax = math.max(revenu.abs(), math.max(charges, net.abs()));
    if (vmax <= 0) return pw.SizedBox();
    pw.Widget ligne(String t, double v, PdfColor c) {
      final w = math.max(1.5, v.abs() / vmax * 270);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.SizedBox(width: 120, child: pw.Text(_a(t), style: pw.TextStyle(fontSize: 9, color: _vert))),
          pw.Container(width: w, height: 11, color: c),
          pw.SizedBox(width: 6),
          pw.Text(_a(_f(v)), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: c)),
        ]),
      );
    }

    return pw.Column(children: [
      ligne('Revenu retenu', revenu, revenu >= 0 ? _vert : _danger),
      ligne('Charges totales', charges, _danger),
      ligne('Benefice net', net, net >= 0 ? _succes : _danger),
    ]);
  }

  static Future<bool> exporter(BilanMarge b, List<Vente> ventes, DateTime debut, DateTime fin,
      String texteDebut, String texteFin, {List<BilanArchive>? archives}) async {
    final moisEntier = debut.day == 1 && debut.year == fin.year && debut.month == fin.month &&
        fin.day == DateTime(fin.year, fin.month + 1, 0).day;
    final libelle = _a(moisEntier ? AnalyseRapports.libellePeriode(debut, fin) : 'du $texteDebut au $texteFin');
    final suffixe = moisEntier
        ? '${debut.month.toString().padLeft(2, '0')}-${debut.year}'
        : '${texteDebut.replaceAll('/', '-')}_au_${texteFin.replaceAll('/', '-')}';

    // --- chiffres : mêmes règles qu'avant (revenu de la période, sauf ajustement manuel du mois en cours)
    final detail = VentesRepo.revenuPeriode(ventes, debut, fin);
    var revenu = detail.beneficePur;
    var revenuManuel = false;
    final periodeCle = '${debut.month.toString().padLeft(2, '0')}/${debut.year}';
    if (moisEntier && b.revenuModifie && periodeCle == b.periode) {
      revenu = b.ca;
      revenuManuel = true;
    }
    final res = ResultatFinancier.calculer(
        benefice: revenu, charges: b.totalCharges, caBrut: detail.caBrut, coutAchat: detail.coutAchat);
    final couleurNet = res.net >= 0 ? _succes : _danger;
    final arch = archives ?? await BilansRepo.archives();
    final synthese = AnalyseRapports.construire(ventes: ventes, archives: arch, debut: debut, fin: fin, res: res);
    final n = DateTime.now();
    final genere = '${jourEnTexte(n)} a ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    final periodeEnCours = fin.isAfter(n);

    // positions des lignes importantes du tableau « du CA au bénéfice net »
    final sansCout = detail.caSansCout > 0 ? 1 : 0;
    final iPur = 2 + sansCout;
    final iNet = 4 + sansCout + (revenuManuel ? 1 : 0);
    final iMarge = iNet + 1;

    final logo = await LogoPdf.widget();
    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      // --- bandeau de titre
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: pw.BoxDecoration(color: _vert, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('BILAN DE MARGE ET BENEFICE',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          pw.SizedBox(height: 4),
          pw.Text(_a(Session.nomFerme.toUpperCase()),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#e8b27a'))),
          pw.SizedBox(height: 8),
          pw.Text('Periode : $libelle   -   Genere le $genere', style: pw.TextStyle(fontSize: 9.5, color: _clair)),
        ]),
      ),
      pw.SizedBox(height: 14),
      // --- les 4 indicateurs clés
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _kpi("CHIFFRE D'AFFAIRES", _f(detail.caBrut), '${detail.nbVentes} vente(s) facturee(s)', _vert),
        _kpi('CHARGES TOTALES', _f(res.charges), res.benefice > 0 ? '${_pct(res.charges / res.benefice * 100)} du benefice pur' : 'Charges mensuelles saisies', _danger),
        _kpi('BENEFICE NET', _f(res.net), 'Benefice pur - charges', couleurNet, fort: true),
        _kpi('MARGE NETTE', _pct(res.margePct), "Net / chiffre d'affaires", couleurNet),
      ]),
      _section("Du chiffre d'affaires au benefice net"),
      _lignes([
        ["Chiffre d'affaires facture (ventes de la periode)", _f(detail.caBrut)],
        if (detail.caSansCout > 0) ["- Ventes sans prix d'achat connu (non comptees)", '- ${_f(detail.caSansCout)}'],
        ["- Cout d'achat des marchandises vendues", '- ${_f(detail.coutAchat)}'],
        ['= Benefice pur de la Caisse', _f(detail.beneficePur)],
        if (revenuManuel) ['+/- Ajustement manuel du revenu', _f(revenu - detail.beneficePur)],
        ['- Charges totales', '- ${_f(res.charges)}'],
        ['= Benefice net (poche du Boss)', _f(res.net)],
        ["Marge nette (net / CA facture de ${_f(detail.caBrut)})", _pct(res.margePct)],
      ], gras: {iPur, iNet, iMarge}, couleurs: {iNet: couleurNet, iMarge: couleurNet}),
    ];
    if (detail.nbSansCout > 0) {
      contenu.add(_note("Attention : ${detail.nbSansCout} vente(s) sans prix d'achat connu (${_f(detail.caSansCout)}) "
          'ne sont pas comptees dans le benefice, mais figurent dans le chiffre d\'affaires.'));
    }
    if (detail.beneficeEnAttente > 0.5) {
      contenu.add(_note('Dont ${_f(detail.beneficeEnAttente)} de marge sur des credits pas encore recouvres.'));
    }
    if (revenuManuel) {
      contenu.add(_note('Revenu ajuste manuellement dans le logiciel : ${_f(revenu)} (valeur retenue pour le calcul).'));
    }

    // --- charges
    contenu.add(_section('Charges mensuelles'));
    final postes = <(String, double)>[
      ('Loyer', b.loyer), ('Electricite & Energie', b.elec), ('Transport & Logistique', b.transport),
      ("Salaires & Main d'oeuvre", b.salaires), ('Divers & Imprevus', b.divers),
    ];
    contenu.add(pw.Table(
      columnWidths: const {0: pw.FixedColumnWidth(280), 1: pw.FixedColumnWidth(150), 2: pw.FixedColumnWidth(102)},
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _ligne, width: 0.4), bottom: pw.BorderSide(color: _ligne, width: 0.4)),
      children: [
        _enteteTable(['Poste', 'Montant', 'Part des charges']),
        for (final p in postes)
          pw.TableRow(children: [
            _cell(p.$1, gauche: true),
            _cell(_f(p.$2), droite: true),
            _cell(res.charges > 0 ? _pct(p.$2 / res.charges * 100) : '-', droite: true),
          ]),
        pw.TableRow(decoration: pw.BoxDecoration(color: _creme), children: [
          _cell('Total des charges', gauche: true, gras: true),
          _cell(_f(res.charges), droite: true, gras: true, couleur: _danger),
          _cell(res.charges > 0 ? '100.0 %' : '-', droite: true, gras: true),
        ]),
      ],
    ));
    if (!(moisEntier && periodeCle == b.periode)) {
      contenu.add(_note('Les charges reprises sont celles saisies dans le logiciel (periode de saisie : ${b.periode}).'));
    }
    contenu.add(pw.SizedBox(height: 14));
    contenu.add(_cascade(revenu, res.charges, res.net));

    // --- comparaison
    contenu.add(_section('Comparaison avec la periode precedente'));
    contenu.add(pw.Text(_a('Actuelle : ${synthese.libelleActuel}   |   Precedente : ${synthese.libellePrecedent}'),
        style: pw.TextStyle(fontSize: 8.5, color: _doux)));
    contenu.add(pw.SizedBox(height: 5));
    contenu.add(pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(185), 1: pw.FixedColumnWidth(115), 2: pw.FixedColumnWidth(115), 3: pw.FixedColumnWidth(117),
      },
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _ligne, width: 0.4), bottom: pw.BorderSide(color: _ligne, width: 0.4)),
      children: [
        _enteteTable(['Indicateur', 'Actuelle', 'Precedente', 'Evolution']),
        for (final l in synthese.comparaison)
          pw.TableRow(children: [
            _cell(l.libelle, gauche: true),
            _cell(_montantLigne(l, l.actuel), droite: true),
            _cell(l.precedent == null ? '-' : _montantLigne(l, l.precedent!), droite: true),
            _cell(_evolution(l),
                droite: true,
                gras: true,
                couleur: l.favorable == null ? _doux : (l.favorable! ? _succes : _danger)),
          ]),
      ],
    ));
    if (synthese.precedentVide) {
      contenu.add(_note('Aucune vente enregistree sur la periode precedente : les evolutions ne sont pas calculables.'));
    }
    if (synthese.archivePrecedente == null) {
      contenu.add(_note('Charges, benefice net et marge : aucun bilan archive pour la periode precedente (archivez chaque mois pour comparer).'));
    } else {
      contenu.add(_note('Charges, benefice net et marge : compares au bilan archive de la periode precedente (mois complet).'));
    }
    if (periodeEnCours) {
      contenu.add(_note('Periode en cours : les jours a venir ne sont pas encore comptes.'));
    }

    // --- tendance
    contenu.add(_section('Evolution sur 6 mois'));
    contenu.add(_barresMensuelles(synthese.tendance));
    contenu.add(pw.SizedBox(height: 8));
    contenu.add(pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(92), 1: pw.FixedColumnWidth(110), 2: pw.FixedColumnWidth(110), 3: pw.FixedColumnWidth(110),
        4: pw.FixedColumnWidth(110),
      },
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _ligne, width: 0.4), bottom: pw.BorderSide(color: _ligne, width: 0.4)),
      children: [
        _enteteTable(['Mois', "CA facture", 'Benefice pur', 'Charges archivees', 'Net archive']),
        for (final p in synthese.tendance)
          pw.TableRow(children: [
            _cell(p.etiquette, gauche: true),
            _cell(milliersAnglais(p.ca).replaceAll(',', ' '), droite: true),
            _cell(milliersAnglais(p.benefice).replaceAll(',', ' '), droite: true),
            _cell(p.chargesArchivees == null ? '-' : milliersAnglais(p.chargesArchivees!).replaceAll(',', ' '), droite: true),
            _cell(p.netArchive == null ? '-' : milliersAnglais(p.netArchive!).replaceAll(',', ' '), droite: true),
          ]),
      ],
    ));
    contenu.add(_note("Montants en FCFA. Charges et net : uniquement pour les mois dont le bilan a ete archive ('-' sinon)."));

    // --- détail par produit (inchangé sur le fond)
    if (detail.parProduit.isNotEmpty) {
      contenu.add(_section('Detail par produit sur la periode'));
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
          3: pw.FixedColumnWidth(100), 4: pw.FixedColumnWidth(107),
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
                  legend: _a('${e.key} (${milliersAnglais(e.value.benefice)} F)'),
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

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 5),
        decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _ligne, width: 0.5))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Genere par Hakili de Antoine Software - document de gestion interne, non certifie.',
              style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic, color: PdfColor.fromHex('#8a9c91'))),
          pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 7.5, color: _gris)),
        ]),
      ),
      build: (_) => contenu,
    ));

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
