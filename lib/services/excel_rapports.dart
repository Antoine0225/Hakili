import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../data/bilans_repo.dart';
import '../data/ventes_repo.dart';
import '../metier/analyse_rapports.dart';
import '../utilitaires/formats.dart';

/// Export Excel du bilan : un vrai classeur (5 feuilles, formules vivantes, formats monétaires, filtres).
/// Il est fabriqué ici en OOXML « à la main » (comme avant) : aucune dépendance ajoutée.
///
/// Feuilles : Synthèse · Comparaison · Tendance 6 mois · Produits · Archives.
class ExcelRapports {
  ExcelRapports._();

  /// Renvoie true si le fichier est enregistré, false si la personne annule.
  static Future<bool> exporter({
    required BilanMarge bilan,
    required ResultatFinancier res,
    required SynthesePeriodes synthese,
    required List<BilanArchive> archives,
    required String nomFerme,
  }) async {
    final nom = 'Hakili_Bilan_${bilan.periode.replaceAll('/', '-')}.xlsx';
    final lieu = await getSaveLocation(
      suggestedName: nom,
      acceptedTypeGroups: const [XTypeGroup(label: 'Classeur Excel', extensions: ['xlsx'])],
      confirmButtonText: 'Enregistrer',
    );
    if (lieu == null) return false;
    var chemin = lieu.path;
    if (!chemin.toLowerCase().endsWith('.xlsx')) chemin = '$chemin.xlsx';

    final feuilles = <_Feuille>[
      _feuilleSynthese(bilan, res, synthese, nomFerme),
      _feuilleComparaison(synthese),
      _feuilleTendance(synthese),
      _feuilleProduits(synthese),
      _feuilleArchives(archives),
    ];
    await File(chemin).writeAsBytes(_classeur(feuilles), flush: true);
    return true;
  }

  // ------------------------------------------------------------------ styles (indices de cellXfs)
  static const _sTitre = 1, _sNote = 2, _sEntete = 3, _sLibelle = 4, _sMontant = 5, _sTotalLib = 6, _sTotalMont = 7,
      _sPourcent = 8, _sSection = 9, _sCentre = 10, _sVariation = 11, _sPoints = 12, _sTotalPct = 13, _sBandeau = 14,
      _sEntier = 15, _sMargePts = 16;

  static String _maintenant() {
    final n = DateTime.now();
    return '${jourEnTexte(n)} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  static void _entete(_Feuille f, String titre, String sousTitre, int derniereCol) {
    f.fusionner(0, 0, derniereCol, titre, _sTitre);
    f.hauteurs[0] = 30;
    f.fusionner(1, 0, derniereCol, sousTitre, _sBandeau);
    f.hauteurs[1] = 20;
  }

  // ------------------------------------------------------------------ feuille 1 : synthèse
  static _Feuille _feuilleSynthese(BilanMarge b, ResultatFinancier res, SynthesePeriodes s, String nomFerme) {
    final f = _Feuille('Synthèse', [50, 22, 62]);
    _entete(f, 'HAKILI — RAPPORT FINANCIER', '$nomFerme  ·  Bilan de marge et bénéfice', 2);
    f.texte(2, 0, 'Période du bilan', _sLibelle);
    f.fusionner(2, 1, 2, b.periode, _sLibelle);
    f.texte(3, 0, 'Généré le', _sLibelle);
    f.fusionner(3, 1, 2, _maintenant(), _sLibelle);
    f.fusionner(5, 0, 2, "Du chiffre d'affaires au bénéfice net", _sSection);
    f.texte(6, 0, 'Indicateur', _sEntete);
    f.texte(6, 1, 'Montant (FCFA)', _sEntete);
    f.texte(6, 2, 'Commentaire', _sEntete);

    final d = s.detail;
    const rCa = 7, rSans = 8, rCout = 9, rPur = 10, rAjust = 11, rRev = 12, rLoyer = 13, rElec = 14, rTrans = 15, rSal = 16,
        rDiv = 17, rTot = 18, rNet = 19, rMarge = 20;
    String c(int r) => 'B${r + 1}';

    f.texte(rCa, 0, "Chiffre d'affaires facturé (ventes du mois)", _sLibelle);
    f.nombre(rCa, 1, d.caBrut, _sMontant);
    f.texte(rCa, 2, 'Toutes les ventes enregistrées, y compris les crédits pas encore encaissés', _sLibelle);

    f.texte(rSans, 0, "Ventes sans prix d'achat connu", _sLibelle);
    f.nombre(rSans, 1, d.caSansCout, _sMontant);
    f.texte(rSans, 2, d.nbSansCout > 0 ? '${d.nbSansCout} vente(s) : exclues du bénéfice pur' : 'Aucune', _sLibelle);

    f.texte(rCout, 0, "Coût d'achat des marchandises vendues", _sLibelle);
    f.nombre(rCout, 1, d.coutAchat, _sMontant);
    f.texte(rCout, 2, "Prix d'achat (arrivages) × quantités vendues", _sLibelle);

    final pur = d.caBrut - d.caSansCout - d.coutAchat;
    f.texte(rPur, 0, 'Bénéfice pur de la Caisse', _sTotalLib);
    f.formule(rPur, 1, '${c(rCa)}-${c(rSans)}-${c(rCout)}', pur, _sTotalMont);
    f.texte(rPur, 2, d.beneficeEnAttente > 0.5
        ? 'dont ${fmtF(d.beneficeEnAttente, unite: '')} FCFA de marge sur des crédits non recouvrés'
        : 'CA − ventes sans coût − coût d\'achat', _sTotalLib);

    f.texte(rAjust, 0, 'Ajustement manuel du revenu', _sLibelle);
    f.formule(rAjust, 1, '${c(rRev)}-${c(rPur)}', b.ca - pur, _sMontant);
    f.texte(rAjust, 2, b.revenuModifie ? 'Revenu modifié à la main dans Hakili' : 'Aucun (écart d\'arrondi éventuel)', _sLibelle);

    f.texte(rRev, 0, 'Revenu retenu pour le calcul', _sTotalLib);
    f.nombre(rRev, 1, b.ca, _sTotalMont);
    f.texte(rRev, 2, b.revenuModifie ? 'Valeur saisie manuellement' : 'Identique au bénéfice pur de la Caisse', _sTotalLib);

    final charges = <(String, double)>[
      ('Loyer', b.loyer), ('Électricité et énergie', b.elec), ('Transport et logistique', b.transport),
      ("Salaires et main d'œuvre", b.salaires), ('Divers et imprévus', b.divers),
    ];
    final rCharges = [rLoyer, rElec, rTrans, rSal, rDiv];
    for (var i = 0; i < 5; i++) {
      f.texte(rCharges[i], 0, charges[i].$1, _sLibelle);
      f.nombre(rCharges[i], 1, charges[i].$2, _sMontant);
      f.texte(rCharges[i], 2, 'Charge mensuelle saisie', _sLibelle);
    }
    f.texte(rTot, 0, 'TOTAL DES CHARGES', _sTotalLib);
    f.formule(rTot, 1, 'SUM(${c(rLoyer)}:${c(rDiv)})', res.charges, _sTotalMont);
    f.texte(rTot, 2, '', _sTotalLib);

    f.texte(rNet, 0, 'BÉNÉFICE NET (APRÈS CHARGES)', _sTotalLib);
    f.formule(rNet, 1, '${c(rRev)}-${c(rTot)}', res.net, _sTotalMont);
    f.texte(rNet, 2, 'Revenu retenu − total des charges', _sTotalLib);

    f.texte(rMarge, 0, 'MARGE NETTE (%)', _sTotalLib);
    f.formule(rMarge, 1, 'IF(${c(rCa)}>0,${c(rNet)}/${c(rCa)},IF(${c(rRev)}>0,${c(rNet)}/${c(rRev)},0))',
        res.margePct / 100, _sTotalPct);
    f.texte(rMarge, 2, "Bénéfice net ÷ chiffre d'affaires facturé", _sTotalLib);

    f.fusionner(22, 0, 2,
        'Les montants correspondent au bilan calculé dans Hakili à partir des ventes enregistrées. Vérifiez la période '
        'avant toute décision de gestion. Document de gestion interne, non certifié.',
        _sNote);
    f.hauteurs[22] = 32;
    return f;
  }

  // ------------------------------------------------------------------ feuille 2 : comparaison
  static _Feuille _feuilleComparaison(SynthesePeriodes s) {
    final f = _Feuille('Comparaison', [40, 22, 22, 18, 16]);
    _entete(f, 'COMPARAISON DES PÉRIODES', 'Actuelle : ${s.libelleActuel}   |   Précédente : ${s.libellePrecedent}', 4);
    f.texte(3, 0, 'Indicateur', _sEntete);
    f.texte(3, 1, 'Période actuelle', _sEntete);
    f.texte(3, 2, 'Période précédente', _sEntete);
    f.texte(3, 3, 'Écart', _sEntete);
    f.texte(3, 4, 'Évolution', _sEntete);
    var r = 4;
    for (final l in s.comparaison) {
      final pts = l.enPourcent;
      f.texte(r, 0, l.libelle, _sLibelle);
      f.nombre(r, 1, l.actuel, pts ? _sMargePts : _sMontant);
      if (l.precedent == null) {
        f.texte(r, 2, '—', _sCentre);
        f.texte(r, 3, '—', _sCentre);
        f.texte(r, 4, '—', _sCentre);
      } else {
        f.nombre(r, 2, l.precedent!, pts ? _sMargePts : _sMontant);
        f.formule(r, 3, 'B${r + 1}-C${r + 1}', l.actuel - l.precedent!, pts ? _sPoints : _sMontant);
        if (pts) {
          f.texte(r, 4, '—', _sCentre);
        } else {
          final ev = l.evolution;
          f.formule(r, 4, 'IF(C${r + 1}=0,"n/d",(B${r + 1}-C${r + 1})/ABS(C${r + 1}))', ev == null ? 'n/d' : ev / 100,
              _sVariation);
        }
      }
      r++;
    }
    final notes = <String>[
      if (s.precedentVide) 'Aucune vente enregistrée sur la période précédente : les évolutions ne peuvent pas être calculées.',
      'Chiffre d\'affaires, coût d\'achat et bénéfice pur : calculés depuis les ventes enregistrées (mêmes jours du mois précédent).',
      s.archivePrecedente == null
          ? 'Charges, bénéfice net et marge : aucun bilan archivé pour la période précédente. Archivez chaque mois pour alimenter cette comparaison.'
          : 'Charges, bénéfice net et marge : comparés au bilan archivé de la période précédente (mois complet).',
    ];
    r++;
    for (final n in notes) {
      f.fusionner(r, 0, 4, n, _sNote);
      f.hauteurs[r] = 28;
      r++;
    }
    return f;
  }

  // ------------------------------------------------------------------ feuille 3 : tendance
  static _Feuille _feuilleTendance(SynthesePeriodes s) {
    final f = _Feuille('Tendance 6 mois', [18, 20, 20, 20, 12, 20, 20]);
    _entete(f, 'ÉVOLUTION SUR 6 MOIS', "Chiffre d'affaires et bénéfice pur issus des ventes ; charges et net issus des bilans archivés", 6);
    const titres = ['Mois', "CA facturé (FCFA)", "Coût d'achat (FCFA)", 'Bénéfice pur (FCFA)', 'Nb ventes', 'Charges archivées', 'Net archivé'];
    for (var i = 0; i < titres.length; i++) {
      f.texte(3, i, titres[i], _sEntete);
    }
    var r = 4;
    for (final p in s.tendance) {
      f.texte(r, 0, '${moisNomsRapport[p.mois.month - 1]} ${p.mois.year}', _sLibelle);
      f.nombre(r, 1, p.ca, _sMontant);
      f.nombre(r, 2, p.coutAchat, _sMontant);
      f.nombre(r, 3, p.benefice, _sMontant);
      f.nombre(r, 4, p.nbVentes, _sEntier);
      if (p.chargesArchivees == null) {
        f.texte(r, 5, '—', _sCentre);
      } else {
        f.nombre(r, 5, p.chargesArchivees!, _sMontant);
      }
      if (p.netArchive == null) {
        f.texte(r, 6, '—', _sCentre);
      } else {
        f.nombre(r, 6, p.netArchive!, _sMontant);
      }
      r++;
    }
    final premiere = 5, derniere = r; // lignes Excel (1-based) de la première et de la dernière donnée
    f.texte(r, 0, 'TOTAL', _sTotalLib);
    double somme(double Function(PointMensuel) g) => s.tendance.fold<double>(0, (a, p) => a + g(p));
    f.formule(r, 1, 'SUM(B$premiere:B$derniere)', somme((p) => p.ca), _sTotalMont);
    f.formule(r, 2, 'SUM(C$premiere:C$derniere)', somme((p) => p.coutAchat), _sTotalMont);
    f.formule(r, 3, 'SUM(D$premiere:D$derniere)', somme((p) => p.benefice), _sTotalMont);
    f.formule(r, 4, 'SUM(E$premiere:E$derniere)', s.tendance.fold<int>(0, (a, p) => a + p.nbVentes), _sEntier);
    f.texte(r, 5, '', _sTotalLib);
    f.texte(r, 6, '', _sTotalLib);
    f.barresDonnees('B$premiere:B$derniere', 'FF9CC5AB');
    f.barresDonnees('D$premiere:D$derniere', 'FFE3B27A');
    f.fusionner(r + 2, 0, 6,
        'Le mois en cours est partiel (jusqu\'à aujourd\'hui). « — » = aucun bilan archivé pour ce mois.', _sNote);
    f.gel = 4;
    return f;
  }

  // ------------------------------------------------------------------ feuille 4 : produits
  static _Feuille _feuilleProduits(SynthesePeriodes s) {
    final f = _Feuille('Produits', [38, 14, 20, 20, 22, 16]);
    _entete(f, 'DÉTAIL PAR PRODUIT', 'Période : ${s.libelleActuel}', 5);
    const titres = ['Produit', 'Qté vendue', 'CA (FCFA)', "Coût d'achat (FCFA)", 'Bénéfice pur (FCFA)', 'Part du bénéfice'];
    for (var i = 0; i < titres.length; i++) {
      f.texte(3, i, titres[i], _sEntete);
    }
    final lignes = s.detail.parProduit.entries.toList()..sort((a, c) => c.value.benefice.compareTo(a.value.benefice));
    if (lignes.isEmpty) {
      f.fusionner(4, 0, 5, 'Aucune vente enregistrée sur la période.', _sNote);
      f.gel = 4;
      return f;
    }
    final premiere = 5, derniere = 4 + lignes.length;
    final rTot = 4 + lignes.length; // index 0-based de la ligne TOTAL
    final totalBenef = lignes.fold<double>(0, (a, e) => a + e.value.benefice);
    var r = 4;
    var etoile = false;
    for (final e in lignes) {
      final pr = e.value;
      if (pr.caSansCout > 0) etoile = true;
      f.texte(r, 0, pr.caSansCout > 0 ? '${e.key} *' : e.key, _sLibelle);
      f.nombre(r, 1, pr.qte, _sMontant);
      f.nombre(r, 2, pr.ca, _sMontant);
      f.nombre(r, 3, pr.cout, _sMontant);
      f.nombre(r, 4, pr.benefice, _sMontant);
      f.formule(r, 5, 'IF(E${rTot + 1}>0,E${r + 1}/E${rTot + 1},0)', totalBenef > 0 ? pr.benefice / totalBenef : 0.0, _sPourcent);
      r++;
    }
    f.texte(rTot, 0, 'TOTAL', _sTotalLib);
    double somme(double Function(ProduitRevenu) g) => lignes.fold<double>(0, (a, e) => a + g(e.value));
    f.formule(rTot, 1, 'SUM(B$premiere:B$derniere)', somme((p) => p.qte), _sTotalMont);
    f.formule(rTot, 2, 'SUM(C$premiere:C$derniere)', somme((p) => p.ca), _sTotalMont);
    f.formule(rTot, 3, 'SUM(D$premiere:D$derniere)', somme((p) => p.cout), _sTotalMont);
    f.formule(rTot, 4, 'SUM(E$premiere:E$derniere)', totalBenef, _sTotalMont);
    f.texte(rTot, 5, '', _sTotalLib);
    if (etoile) {
      f.fusionner(rTot + 2, 0, 5,
          "* Contient des ventes sans prix d'achat connu : elles figurent dans le CA mais pas dans le bénéfice du produit.", _sNote);
    }
    f.barresDonnees('E$premiere:E$derniere', 'FF9CC5AB');
    f.gel = 4;
    return f;
  }

  // ------------------------------------------------------------------ feuille 5 : archives
  static _Feuille _feuilleArchives(List<BilanArchive> archives) {
    final f = _Feuille('Archives', [14, 20, 20, 16, 16, 16, 16, 16, 18, 18, 12, 22]);
    _entete(f, 'ARCHIVES DES BILANS MENSUELS', '${archives.length} bilan(s) enregistré(s) sur ce poste', 11);
    const titres = ['Période', 'Archivé le', 'Revenu retenu', 'Loyer', 'Électricité', 'Transport', 'Salaires', 'Divers',
      'Total charges', 'Bénéfice net', 'Marge', 'Statut'];
    for (var i = 0; i < titres.length; i++) {
      f.texte(3, i, titres[i], _sEntete);
    }
    if (archives.isEmpty) {
      f.fusionner(4, 0, 11, "Aucun bilan archivé pour l'instant.", _sNote);
      f.gel = 4;
      return f;
    }
    var r = 4;
    for (final a in archives) {
      f.texte(r, 0, a.periode, _sCentre);
      f.texte(r, 1, a.dateArchivage, _sCentre);
      f.nombre(r, 2, a.ca, _sMontant);
      f.nombre(r, 3, a.loyer, _sMontant);
      f.nombre(r, 4, a.elec, _sMontant);
      f.nombre(r, 5, a.transport, _sMontant);
      f.nombre(r, 6, a.salaires, _sMontant);
      f.nombre(r, 7, a.divers, _sMontant);
      f.nombre(r, 8, a.totalCharges, _sMontant);
      f.nombre(r, 9, a.net, _sMontant);
      f.nombre(r, 10, a.margePct, _sMargePts);
      f.texte(r, 11, a.envoye ? 'Synchronisé (Cloud)' : 'Local uniquement', _sCentre);
      r++;
    }
    f.filtre = 'A4:L$r';
    f.gel = 4;
    return f;
  }

  // ------------------------------------------------------------------ fabrication du classeur
  static Uint8List _classeur(List<_Feuille> feuilles) {
    final types = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    final rels = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    final noms = StringBuffer();
    final fichiers = <String, String>{};
    for (var i = 0; i < feuilles.length; i++) {
      final n = i + 1;
      types.write('<Override PartName="/xl/worksheets/sheet$n.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
      rels.write('<Relationship Id="rId$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet$n.xml"/>');
      noms.write('<sheet name="${_xml(feuilles[i].nom)}" sheetId="$n" r:id="rId$n"/>');
      fichiers['xl/worksheets/sheet$n.xml'] = feuilles[i].xml(i == 0);
    }
    types.write('</Types>');
    rels.write('<Relationship Id="rId${feuilles.length + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
    const racine = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
    final classeur = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$noms</sheets><calcPr fullCalcOnLoad="1"/></workbook>';
    return _zipSansCompression({
      '[Content_Types].xml': types.toString(),
      '_rels/.rels': racine,
      'xl/workbook.xml': classeur,
      'xl/_rels/workbook.xml.rels': rels.toString(),
      'xl/styles.xml': _styles,
      ...fichiers,
    });
  }

  static const _bord = '<border><left style="thin"><color rgb="FFD8D1C2"/></left><right style="thin"><color rgb="FFD8D1C2"/></right>'
      '<top style="thin"><color rgb="FFD8D1C2"/></top><bottom style="thin"><color rgb="FFD8D1C2"/></bottom><diagonal/></border>';

  static const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="5">'
      '<numFmt numFmtId="165" formatCode="0.0%"/>'
      '<numFmt numFmtId="166" formatCode="#,##0;[Red]\\-#,##0"/>'
      '<numFmt numFmtId="167" formatCode="+0.0%;\\-0.0%;0.0%"/>'
      '<numFmt numFmtId="168" formatCode="+0.0&quot; pts&quot;;\\-0.0&quot; pts&quot;;0.0&quot; pts&quot;"/>'
      '<numFmt numFmtId="169" formatCode="0.0&quot; %&quot;"/>'
      '</numFmts>'
      '<fonts count="7">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
      '<font><b/><sz val="16"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
      '<font><i/><sz val="10"/><color rgb="FF6F7D75"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FF123229"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="12"/><color rgb="FFB8651F"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="4">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF123229"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFE8F0EA"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="3">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '$_bord'
      '<border><left/><right/><top/><bottom style="thin"><color rgb="FFB8651F"/></bottom><diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="17">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="left" vertical="center" indent="1"/></xf>'
      '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="5" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="166" fontId="5" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
      '<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="6" fillId="0" borderId="2" xfId="0" applyFont="1" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="167" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="168" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="165" fontId="5" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="4" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" indent="1"/></xf>'
      '<xf numFmtId="1" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center"/></xf>'
      '<xf numFmtId="169" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  // ------------------------------------------------------------------ utilitaires XML / ZIP
  static String _xml(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Uint8List _zipSansCompression(Map<String, String> fichiers) {
    final sortie = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    var offset = 0;
    final date = DateTime.now();
    final heureZip = ((date.hour & 31) << 11) | ((date.minute & 63) << 5) | ((date.second ~/ 2) & 31);
    final dateZip = (((date.year - 1980) & 127) << 9) | ((date.month & 15) << 5) | (date.day & 31);
    for (final entry in fichiers.entries) {
      final nom = utf8.encode(entry.key);
      final data = utf8.encode(entry.value);
      final crc = _crc32(data);
      final local = BytesBuilder(copy: false);
      local.add(_u32(0x04034b50)); local.add(_u16(20)); local.add(_u16(0x0800)); local.add(_u16(0));
      local.add(_u16(heureZip)); local.add(_u16(dateZip)); local.add(_u32(crc));
      local.add(_u32(data.length)); local.add(_u32(data.length));
      local.add(_u16(nom.length)); local.add(_u16(0)); local.add(nom); local.add(data);
      final bytesLocal = local.takeBytes();
      sortie.add(bytesLocal);
      central.add(_u32(0x02014b50)); central.add(_u16(20)); central.add(_u16(20)); central.add(_u16(0x0800)); central.add(_u16(0));
      central.add(_u16(heureZip)); central.add(_u16(dateZip)); central.add(_u32(crc));
      central.add(_u32(data.length)); central.add(_u32(data.length));
      central.add(_u16(nom.length)); central.add(_u16(0)); central.add(_u16(0)); central.add(_u16(0)); central.add(_u16(0));
      central.add(_u32(0)); central.add(_u32(offset)); central.add(nom);
      offset += bytesLocal.length;
    }
    final repertoire = central.takeBytes();
    sortie.add(repertoire);
    sortie.add(_u32(0x06054b50)); sortie.add(_u16(0)); sortie.add(_u16(0));
    sortie.add(_u16(fichiers.length)); sortie.add(_u16(fichiers.length));
    sortie.add(_u32(repertoire.length)); sortie.add(_u32(offset)); sortie.add(_u16(0));
    return sortie.takeBytes();
  }

  static Uint8List _u16(int n) => Uint8List.fromList([n & 255, (n >> 8) & 255]);
  static Uint8List _u32(int n) => Uint8List.fromList([n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255]);

  static int _crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class _Cellule {
  final Object? valeur;
  final int style;
  final String? formule;
  const _Cellule(this.valeur, this.style, [this.formule]);
}

/// Une feuille du classeur : cellules, largeurs, fusions, filtre, volets figés, barres de données.
class _Feuille {
  final String nom;
  final List<double> largeurs;
  final Map<int, Map<int, _Cellule>> _lignes = {};
  final Map<int, double> hauteurs = {};
  final List<String> _fusions = [];
  final List<String> _barres = [];
  final List<String> _couleursBarres = [];
  String? filtre;
  int gel = 0; // nombre de lignes figées en haut
  _Feuille(this.nom, this.largeurs);

  void _poser(int r, int c, _Cellule cel) => (_lignes[r] ??= {})[c] = cel;
  void texte(int r, int c, String t, int style) => _poser(r, c, _Cellule(t, style));
  void nombre(int r, int c, num v, int style) => _poser(r, c, _Cellule(v, style));
  void formule(int r, int c, String f, Object cache, int style) => _poser(r, c, _Cellule(cache, style, f));

  /// Fusionne des cellules d'une même ligne (de c1 à c2) et pose le texte dans la première.
  void fusionner(int r, int c1, int c2, String t, int style) {
    texte(r, c1, t, style);
    for (var c = c1 + 1; c <= c2; c++) {
      _poser(r, c, _Cellule(null, style));
    }
    if (c2 > c1) _fusions.add('${_col(c1)}${r + 1}:${_col(c2)}${r + 1}');
  }

  void barresDonnees(String plage, String couleur) {
    _barres.add(plage);
    _couleursBarres.add(couleur);
  }

  static String _col(int index) {
    var n = index + 1;
    var out = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      out = String.fromCharCode(65 + r) + out;
      n = (n - 1) ~/ 26;
    }
    return out;
  }

  static String _nombre(num v) {
    if (v is int) return '$v';
    final d = v.toDouble();
    if (!d.isFinite) return '0';
    return double.parse(d.toStringAsFixed(6)).toString();
  }

  String _cellule(String ref, _Cellule c) {
    final s = c.style == 0 ? '' : ' s="${c.style}"';
    final v = c.valeur;
    if (c.formule != null) {
      final f = '<f>${ExcelRapports._xml(c.formule!)}</f>';
      if (v is num) return '<c r="$ref"$s>$f<v>${_nombre(v)}</v></c>';
      return '<c r="$ref"$s t="str">$f<v>${ExcelRapports._xml('$v')}</v></c>';
    }
    if (v == null) return '<c r="$ref"$s/>';
    if (v is num) return '<c r="$ref"$s><v>${_nombre(v)}</v></c>';
    return '<c r="$ref"$s t="inlineStr"><is><t xml:space="preserve">${ExcelRapports._xml('$v')}</t></is></c>';
  }

  String xml(bool selectionnee) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    b.write('<sheetViews><sheetView workbookViewId="0" showGridLines="0"${selectionnee ? ' tabSelected="1"' : ''}>');
    if (gel > 0) {
      b.write('<pane ySplit="$gel" topLeftCell="A${gel + 1}" activePane="bottomLeft" state="frozen"/>'
          '<selection pane="bottomLeft"/>');
    }
    b.write('</sheetView></sheetViews><sheetFormatPr defaultRowHeight="18" customHeight="1"/><cols>');
    for (var i = 0; i < largeurs.length; i++) {
      b.write('<col min="${i + 1}" max="${i + 1}" width="${largeurs[i]}" customWidth="1"/>');
    }
    b.write('</cols><sheetData>');
    final lignes = _lignes.keys.toList()..sort();
    for (final r in lignes) {
      final ht = hauteurs[r];
      b.write('<row r="${r + 1}"${ht != null ? ' ht="$ht" customHeight="1"' : ''}>');
      final cols = _lignes[r]!.keys.toList()..sort();
      for (final c in cols) {
        b.write(_cellule('${_col(c)}${r + 1}', _lignes[r]![c]!));
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (filtre != null) b.write('<autoFilter ref="$filtre"/>');
    if (_fusions.isNotEmpty) {
      b.write('<mergeCells count="${_fusions.length}">');
      for (final m in _fusions) {
        b.write('<mergeCell ref="$m"/>');
      }
      b.write('</mergeCells>');
    }
    for (var i = 0; i < _barres.length; i++) {
      b.write('<conditionalFormatting sqref="${_barres[i]}"><cfRule type="dataBar" priority="${i + 1}"><dataBar>'
          '<cfvo type="num" val="0"/><cfvo type="max"/><color rgb="${_couleursBarres[i]}"/></dataBar></cfRule></conditionalFormatting>');
    }
    b.write('<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
        '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>');
    return b.toString();
  }
}
