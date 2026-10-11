//+------------------------------------------------------------------+
//|                                                                  |
//| Scanner_rsi7.mqh — SCANNER RSI7 SOLO (div. cachée LONG + SHORT)  |
//|                                                                  |
//| Adaptation du script Pine "SCANNER RSI7 | OR H1 | Divergence     |
//| cachee | SOLO" (03_RSI7_OR_SOLO.pine) dans l'architecture        |
//| parallèle multi-scanners de Koenigin.                            |
//|                                                                  |
//| - Classe CONCRETE CScannerRsi7 (pas d'héritage, pas de virtual) |
//| - LONG : divergence cachée haussière — toujours actif (le Pine  |
//|   d'origine est long uniquement, fidélité Pine stricte)         |
//| - SHORT : divergence cachée baissière (miroir exact du long)    |
//|   — OPTIONNEL, input K_RSI7_Short = false par défaut (off =     |
//|   fidélité Pine : aucune référence baissière dans le .pine)     |
//|   Machine à pivots HAUTS indépendante de la machine basse       |
//| - Divergence cachée haussière = prix creux PLUS HAUT + RSI      |
//|   creux PLUS BAS, entre pivots ADJACENTS uniquement             |
//| - Divergence cachée baissière = prix sommet PLUS BAS + RSI      |
//|   sommet PLUS HAUT (miroir, entre pivots hauts adjacents)       |
//| - Pivots 7 barres STRICTS : low[3] strictement plus bas que     |
//|   ses 6 voisines (égalité low[j] <= low[3] → PAS un pivot)      |
//| - Gap entre pivots : 5 à 60 BARRES inclus (comptage en barres,  |
//|   pas en temps horloge — un week-end ne gonfle pas le gap)      |
//| - SL = plus bas des N bougies, bougie signal INCLUSE (short :   |
//|   plus HAUT)                                                     |
//| - TP = 3R (Pine : entry + 3*(entry-sl) ; short : bid - 3R)       |
//| - 1 trade simultané max (HasPositionForSymbol) — le verrou SOLO |
//|   ... et UNIQUEMENT si sélectionné dans le panier (K_RSI7_Trade)|
//| - Entrée au marché (IsMarketOrder = true) au 1er tick qui suit  |
//|   la clôture de la bougie de signal                              |
//|                                                                  |
//| === TRADUCTION PINE → MQL5 ===                                   |
//| - ta.rsi(close,7)                    → handle iRSI (PRICE_CLOSE) |
//| - pivot 7 barres (l.40-43, STRICT)   → DetectPivot : comparaison|
//|   identique low[j] <= low[candidat] → pivot rejeté              |
//| - var prevPrice/prevRsi/prevBar/     → membres m_Prev* : mis à  |
//|   prevTime (l.29-32)                    jour à CHAQUE pivot     |
//|   confirmé, divergent OU NON (l.56-59) — comparaison pivots     |
//|   ADJACENTS uniquement                                         |
//| - gap = bar_index-3-prevBar (l.45)   → iBarShift(prev_time) −   |
//|   shift_candidat : comptage en barres réelles, robuste à la     |
//|   croissance de l'historique (les index MT5 glissent, pas les   |
//|   temps) ; bornes [5,60] INCLUSES                              |
//| - divergence (l.50)                  → m_Divergence (propriété  |
//|   de la bougie confirmée : recalculée à chaque clôture)         |
//| - "TF Valide" (H1 forcé, l.27)      → K_RSI7_TF (défaut H1 ;    |
//|   le scanner travaille sur SON TF, quel que soit le chart)      |
//| - bar_index>=16 (pivots, l.39)      → garde Bars() >= 18        |
//|   (bougie confirmée = Bars-2 bar_index)                         |
//| - bar_index>=200 (entrée, l.94)     → garde Bars() >= 200       |
//| - ta.lowest(low,10) (l.28)          → iLowest(shift 1, count    |
//|   K_RSI7_SL_Bars) — bougie signal incluse                      |
//| - close-stopCandidate>mintick       → risk = ask - SL > tick    |
//|   size (convention ask, cf. EMA50)                              |
//| - entrée = close bougie signal      → ask au 1er tick suivant   |
//|   (convention projet, validée par les backtests EMA50)          |
//| - tp = entry+3*(entry-sl) (l.97)    → K_RSI7_TP_R (défaut 3.0)  |
//| - "not active" (l.94)               → verrou SOLO = position    |
//|   réelle commentée "Rsi7Scanner" (HasPositionForSymbol)         |
//| - Simulation sorties gap/touch     → bracket broker : SL/TP     |
//|   portés par l'ordre, le serveur tranche au tick (règle         |
//|   proximité-open du Pine sans objet — constaté EMA50 : sorties  |
//|   au niveau exact du bracket)                                   |
//| - Replay historique TradingView    → TryBackfill : rejoue les   |
//|   confirmations des 500 dernières bougies au 1er appel réussi   |
//|   (l'état pivots est chaud dès le démarrage, comme un indicateur|
//|   Pine chargé sur tout l'historique du chart)                   |
//| - Sortie PUIS entrée même clôture   → naturel en MQL5 : le      |
//|   broker sort intrabougie au toucher, le verrou est déjà        |
//|   relâché à la clôture où la divergence se confirme             |
//|                                                                  |
//| === EXCLUS (décision utilisateur : logique pure) ===             |
//| Visuel Pine : lignes de divergence, boxes TP/SL, labels,        |
//| diamant, lignes actives, table plan/checklist, alertes          |
//| graphiques. La checklist Pine (creux confirmé / espacé 5-60 /   |
//| prix plus haut / RSI plus bas) est reproduite en LOG à chaque   |
//| pivot (chaîne de raison sur l'échec éventuel).                  |
//|                                                                  |
//| ⚠ SCANNER À ÉTAT (différence clé vs EMA50) :                    |
//| la machine à pivots (UpdateState) DOIT tourner à CHAQUE nouvelle|
//| bougie K_RSI7_TF — AVANT tout filtre, verrou ou toggle. Strategy |
//| l'appelle avant les filtres d'exécution (FIX ChatGPT #1).       |
//| Le signal, lui, reste une propriété de la bougie : pas de rejeu |
//| (une divergence manquée parce que filtrée/bloquée est perdue,   |
//| comme une alerte Pine non prise).                               |
//|                                                                  |
//| Le scanner ne fait AUCUN appel direct à BROKER, MONEY ou DATAS. |
//| Il remplit STRUCT_STRATEGY et CStrategy fait le reste.          |
//| Pas de RollbackSignal : l'état pivots n'est PAS lié à un ordre  |
//| (il évoluerait pareil dans le Pine, ordre envoyé ou non).       |
//| Pas de verrou pending : ordres au marché uniquement.            |
//+------------------------------------------------------------------+


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////
// Gardes et constantes Pine (codées en dur = fidélité au .pine,
// qui n'en fait pas des inputs).
#define RSI7_WARMUP_BARS     200   // Entrée : bar_index >= 200 (Pine l.94)
#define RSI7_MIN_BARS_PIVOT   18   // Pivots : bar_index >= 16 (Pine l.39) — bougie confirmée = Bars-2
#define RSI7_PIVOT_SHIFT       3   // Centre du pivot : low[3] (creux confirmé 3 bougies après)
#define RSI7_GAP_MIN           5   // Écart min entre pivots, INCLUS (Pine l.50)
#define RSI7_GAP_MAX          60   // Écart max entre pivots, INCLUS (Pine l.50)
#define RSI7_BACKFILL_BARS   500   // Profondeur du replay historique au démarrage

//////////////////////////////////////////////////////////
//                                                      //
//              I N P U T S                             //
//                                                      //
//////////////////////////////////////////////////////////
// Auto-contenus : chaque scanner apporte SES réglages dans SON
// fichier (convention "panier de stratégies"). Ils apparaissent
// dans la fenêtre de réglages de l'EA dès que le scanner est
// inclus par Strategy.mqh.
//============================================
//---   Paramètres SCANNER RSI7 SOLO
//============================================
// PANIER DE STRATÉGIES : greffé ≠ tradé.
// Ce toggle décide si CE scanner trade. Le scanner reste câblé dans
// Strategy (Config/End/UpdateState/Detection) mais DORMANT tant que
// la case n'est pas cochée : aucun ordre, aucun signal consommé.
// La machine à pivots, elle, tourne toujours (fidélité Pine :
// l'indicateur calcule, seule l'ENTRÉE est soumise au panier).
// Les positions déjà ouvertes avant dé-sélection courent jusqu'à
// leur SL/TP (portés par le broker — jamais touchées par le toggle).
// False par défaut : rien ne trade tant que l'utilisateur n'a
// rien choisi dans le panier.
input bool               K_RSI7_Trade   = false;       // Panier : trader RSI7 SOLO ?
input ENUM_TIMEFRAMES    K_RSI7_TF      = PERIOD_H1;   // TF de travail (Pine : TF Valide = H1, OR)
input uint               K_RSI7_Period  = 7;           // Période RSI (Pine : 7)
input uint               K_RSI7_SL_Bars = 10;          // Plus bas de combien de bougies pour le SL (Pine : 10)
input double             K_RSI7_TP_R    = 3.0;         // Objectif TP en R (Pine : 3R)
// SHORT OPTIONNEL : le Pine d'origine est long uniquement (divergence
// cachée haussière, Pine l.50). K_RSI7_Short=true ajoute le miroir :
// divergence cachée baissière = pivot HAUT 7 barres strict (égalité
// high[j] >= high[3] → pas de pivot), gap 5-60 barres, prix sommet
// PLUS BAS + RSI sommet PLUS HAUT ; SL = plus HAUT des N bougies ;
// TP = bid - 3R. Machine à pivots haute INDÉPENDANTE de la machine
// basse (deux états prev* distincts, aucune interaction). False par
// défaut = fidélité Pine et bit-identique au comportement validé.
input bool               K_RSI7_Short   = false;       // Activer short (Pine : long uniquement)

//////////////////////////////////////////////////////////
//                                                      //
//                 I N C L U D E S                      //
//                                                      //
//////////////////////////////////////////////////////////
#include <Koenigin/Type.mqh>
#include <Koenigin/Log.mqh>
#include <Koenigin/Tools.mqh>


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CScannerRsi7
{
//==================================
//--- PRIVATE
//==================================
private:
    // Identité du scanner
    //---------------------
    string          m_Name;             // Nom logique ("Rsi7Scanner") — préfixe du comment d'ordre
    ENUM_TIMEFRAMES m_TF;               // Timeframe de travail (K_RSI7_TF)

    // Handle d'indicateur
    //---------------------
    int             m_HandleRSI;        // Handle iRSI (RSI, K_RSI7_Period, PRICE_CLOSE)

    // === ÉTAT PERSISTANT (Pine l.29-32 : var prevPrice/prevRsi/prevBar/prevTime) ===
    // Dernier pivot confirmé — mis à jour à CHAQUE pivot (divergent ou
    // non, Pine l.56-59). Comparaisons de divergence entre pivots
    // ADJACENTS uniquement. prevBar (index Pine) est remplacé par le
    // TEMPS du pivot : stable quand l'historique grandit (les index
    // MT5 glissent), et iBarShift le reconvertit en écart en barres.
    //--------------------------------------------------------------------------------
    bool            m_BackfillDone;     // Replay historique exécuté (une fois)
    bool            m_HavePrev;         // Équivalent Pine "not na(prevBar)"
    double          m_PrevPrice;        // low du pivot précédent
    double          m_PrevRsi;          // RSI du pivot précédent
    datetime        m_PrevBarTime;      // open-time de la bougie pivot précédente

    // Divergence confirmée à la DERNIÈRE bougie clôturée (propriété de
    // la bougie : recalculée à chaque clôture, consommée une fois)
    //----------------------------------------------------------------
    bool            m_Divergence;

    // === ÉTAT PERSISTANT SHORT (miroir, pivots HAUTS) ===
    // Machine à pivots INDÉPENDANTE de la machine basse : sommets et
    // creux forment deux suites de pivots DISTINCTES, chacune avec
    // son prev* (comparaisons entre pivots ADJACENTS au sein de SA
    // suite uniquement — le miroir du long est structurellement
    // isolé : aucune variable partagée avec la machine basse).
    // Ne vit que si K_RSI7_Short=true (sinon jamais mise à jour,
    // zéro signal court — bit-identique au long-only validé).
    //------------------------------------------------------------------
    bool            m_HavePrevS;        // Équivalent Pine "not na(prevBar)" — suite haute
    double          m_PrevPriceS;       // high du pivot haut précédent
    double          m_PrevRsiS;         // RSI du pivot haut précédent
    datetime        m_PrevBarTimeS;     // open-time de la bougie pivot haut précédente
    bool            m_DivergenceShort;  // divergence cachée BAISSIÈRE confirmée à la dernière clôture

    //+--------------------------------------------------------+
    //| DetectPivot (privé)                                     |
    //|--------------------------------------------------------|
    //| Traite UNE confirmation de bougie : détection pivot     |
    //| strict 7 barres centré sur [3], calcul de divergence vs |
    //| le pivot précédent, mise à jour de l'état prev*.        |
    //|                                                        |
    //| Utilisé par le chemin LIVE (shift confirmé = 1) ET par  |
    //| le backfill (confirmations historiques) → UN SEUL code, |
    //| l'état est construit par la même logique partout.       |
    //|                                                        |
    //| Pine l.39-59 (bloc barstate.isconfirmed) :              |
    //|   pivot ← VRAI                                          |
    //|   pour j de 0 à 6, j != 3 :                             |
    //|       si low[j] <= low[3] → pivot ← FAUX   (STRICT)     |
    //|   si pivot :                                            |
    //|       gap ← bar_index-3-prevBar                         |
    //|       divergence ← prevBar existe ET gap∈[5,60]         |
    //|                     ET low[3]>prevPrice ET r[3]<prevRsi |
    //|       prevPrice/prevRsi/prevBar/prevTime ← ce pivot     |
    //|       (à CHAQUE pivot, divergent ou non)                |
    //|                                                        |
    //| INPUT:                                                  |
    //|   i_lows[] : lows série-indexées (i_lows[k] = low shift k)|
    //|   i_times[] : open-times série-indexées                 |
    //|   i_rsis[] : RSI série-indexés                          |
    //|   i_conf_shift : shift de la bougie qui vient d'être     |
    //|     confirmée (live : 1 ; candidat pivot = i_conf_shift+3)|
    //|   i_log : TRUE = journaliser (live) / FALSE = silencieux |
    //|     (backfill : 500 bougies, on ne trace que le bilan)  |
    //+--------------------------------------------------------+
    void DetectPivot(const double   &i_lows[],
                     const datetime &i_times[],
                     const double   &i_rsis[],
                     const int       i_conf_shift,
                     const bool      i_log)
    {
        // Bougie pivot candidate = 3 barres avant la confirmée (Pine low[3])
        //--------------------------------------------------------------------
        int c = i_conf_shift + RSI7_PIVOT_SHIFT;

        // === PIVOT STRICT 7 BOUGIES (Pine l.40-43) ===
        // Le candidat doit être STRICTEMENT plus bas que ses 6 voisines.
        // RQ : égalité low[j] == low[candidat] → PAS un pivot (le Pine
        // rejette avec <=). Fréquent sur l'or aux ronds — fidélité stricte.
        //--------------------------------------------------------------------
        bool pivot = true;
        for (int j = i_conf_shift; j <= i_conf_shift + 2 * RSI7_PIVOT_SHIFT; j++)
        {
            if (j == c) continue;
            if (i_lows[j] <= i_lows[c])
            {
                pivot = false;
                break;
            }
        }
        if (!pivot) return;

        // === ÉCART AVEC LE PIVOT PRÉCÉDENT (Pine l.45 : gap = bar_index-3-prevBar) ===
        // Comptage en BARRES (pas en temps horloge) : iBarShift reconvertit
        // le temps du pivot précédent en shift actuel, l'écart de shifts =
        // l'écart en barres du Pine. exact=true : bar introuvable → -1.
        //----------------------------------------------------------------------------------
        int gap = -1;
        if (m_HavePrev)
        {
            int prev_shift = iBarShift(Symbol(), m_TF, m_PrevBarTime, true);
            if (prev_shift >= 0) gap = prev_shift - c;
        }

        // === DIVERGENCE CACHÉE HAUSSIÈRE (Pine l.50) ===
        // Pivots ADJACENTS uniquement, bornes [5,60] INCLUSES,
        // prix creux PLUS HAUT + RSI creux PLUS BAS.
        //----------------------------------------------------
        m_Divergence = (m_HavePrev
                        && gap >= RSI7_GAP_MIN && gap <= RSI7_GAP_MAX
                        && i_lows[c] > m_PrevPrice
                        && i_rsis[c] < m_PrevRsi);

        // Journal live (le backfill trace son propre bilan) — reproduit
        // la checklist Pine : creux confirmé / espacé 5-60 / prix plus
        // haut / RSI plus bas, avec la raison exacte de l'échec.
        //---------------------------------------------------------------
        if (i_log)
        {
            if (m_Divergence)
            {
                LOG.INFO(m_Name + " : DIVERGENCE cachée haussière | pivot " +
                         TimeToString(i_times[c], TIME_DATE | TIME_MINUTES) +
                         " low=" + DoubleToString(i_lows[c], _Digits) +
                         " (précédent " + DoubleToString(m_PrevPrice, _Digits) + ")" +
                         " | RSI=" + DoubleToString(i_rsis[c], 2) +
                         " (précédent " + DoubleToString(m_PrevRsi, 2) + ")" +
                         " | gap=" + IntegerToString(gap) + " bougies", __FUNCTION__);
            }
            else
            {
                // Raison de l'absence de divergence (cascade exhaustive)
                //--------------------------------------------------------
                string why;
                if (!m_HavePrev)                     why = "premier pivot (pas de précédent)";
                else if (gap < 0)                    why = "pivot précédent introuvable dans l'historique";
                else if (gap < RSI7_GAP_MIN)         why = "gap "    + IntegerToString(gap) + " < "  + IntegerToString(RSI7_GAP_MIN);
                else if (gap > RSI7_GAP_MAX)         why = "gap "    + IntegerToString(gap) + " > "  + IntegerToString(RSI7_GAP_MAX);
                else if (i_lows[c] <= m_PrevPrice)   why = "prix creux pas plus haut (" +
                                                            DoubleToString(i_lows[c], _Digits) + " <= " +
                                                            DoubleToString(m_PrevPrice, _Digits) + ")";
                else                                 why = "RSI creux pas plus bas ("   +
                                                            DoubleToString(i_rsis[c], 2) + " >= " +
                                                            DoubleToString(m_PrevRsi, 2) + ")";

                LOG.INFO(m_Name + " : pivot confirmé " +
                         TimeToString(i_times[c], TIME_DATE | TIME_MINUTES) +
                         " low=" + DoubleToString(i_lows[c], _Digits) +
                         " RSI=" + DoubleToString(i_rsis[c], 2) +
                         " — pas de divergence (" + why + ")", __FUNCTION__);
            }
        }

        // === MISE À JOUR DE L'ÉTAT À CHAQUE PIVOT (Pine l.56-59) ===
        // Divergent OU NON : le prochain pivot se comparera à CELUI-CI.
        //---------------------------------------------------------------
        m_PrevPrice   = i_lows[c];
        m_PrevRsi     = i_rsis[c];
        m_PrevBarTime = i_times[c];
        m_HavePrev    = true;
    }

    //+--------------------------------------------------------+
    //| DetectPivotShort (privé)                                |
    //| Miroir EXACT de DetectPivot sur les SOMMETS : pivot     |
    //| haut 7 barres STRICT centré [3], divergence cachée      |
    //| BAISSIÈRE vs pivot haut précédent, maj prev*S à CHAQUE  |
    //| pivot haut.                                              |
    //|                                                        |
    //| Aucune référence Pine (le .pine est long uniquement) :  |
    //| chaque règle est le miroir symétrique du long —          |
    //|   pivot  : high[j] >= high[c] → FAUX (égalité rejetée,   |
    //|            miroir du <= long)                            |
    //|   diverg : high[c] < prevPrixS (sommet PLUS BAS)         |
    //|            ET rsi[c] > prevRsiS (RSI sommet PLUS HAUT)   |
    //|   gap    : identique au long, [5,60] barres incluses     |
    //|                                                        |
    //| Utilisé par le chemin LIVE et le backfill, comme le     |
    //| long → un seul code, zéro dérive entre les deux chemins. |
    //+--------------------------------------------------------+
    void DetectPivotShort(const double   &i_highs[],
                          const datetime &i_times[],
                          const double   &i_rsis[],
                          const int       i_conf_shift,
                          const bool      i_log)
    {
        // Bougie pivot candidate = 3 barres avant la confirmée (miroir high[3])
        //----------------------------------------------------------------------
        int c = i_conf_shift + RSI7_PIVOT_SHIFT;

        // === PIVOT HAUT STRICT 7 BOUGIES (miroir du long) ===
        // Le candidat doit être STRICTEMENT plus haut que ses 6 voisines.
        // RQ : égalité high[j] == high[candidat] → PAS un pivot (miroir
        // du rejet <= du long). Fréquent sur l'or aux ronds.
        //--------------------------------------------------------------
        bool pivot = true;
        for (int j = i_conf_shift; j <= i_conf_shift + 2 * RSI7_PIVOT_SHIFT; j++)
        {
            if (j == c) continue;
            if (i_highs[j] >= i_highs[c])
            {
                pivot = false;
                break;
            }
        }
        if (!pivot) return;

        // === ÉCART AVEC LE PIVOT HAUT PRÉCÉDENT (barres, miroir du long) ===
        //----------------------------------------------------------------------
        int gap = -1;
        if (m_HavePrevS)
        {
            int prev_shift = iBarShift(Symbol(), m_TF, m_PrevBarTimeS, true);
            if (prev_shift >= 0) gap = prev_shift - c;
        }

        // === DIVERGENCE CACHÉE BAISSIÈRE (miroir du long) ===
        // Pivots hauts ADJACENTS uniquement, bornes [5,60] INCLUSES,
        // prix sommet PLUS BAS + RSI sommet PLUS HAUT.
        //--------------------------------------------------------
        m_DivergenceShort = (m_HavePrevS
                             && gap >= RSI7_GAP_MIN && gap <= RSI7_GAP_MAX
                             && i_highs[c] < m_PrevPriceS
                             && i_rsis[c] > m_PrevRsiS);

        // Journal live (miroir de la checklist long)
        //----------------------------------------------
        if (i_log)
        {
            if (m_DivergenceShort)
            {
                LOG.INFO(m_Name + " : DIVERGENCE cachée baissière | pivot " +
                         TimeToString(i_times[c], TIME_DATE | TIME_MINUTES) +
                         " high=" + DoubleToString(i_highs[c], _Digits) +
                         " (précédent " + DoubleToString(m_PrevPriceS, _Digits) + ")" +
                         " | RSI=" + DoubleToString(i_rsis[c], 2) +
                         " (précédent " + DoubleToString(m_PrevRsiS, 2) + ")" +
                         " | gap=" + IntegerToString(gap) + " bougies", __FUNCTION__);
            }
            else
            {
                string why;
                if (!m_HavePrevS)                    why = "premier pivot haut (pas de précédent)";
                else if (gap < 0)                    why = "pivot haut précédent introuvable dans l'historique";
                else if (gap < RSI7_GAP_MIN)         why = "gap " + IntegerToString(gap) + " < " + IntegerToString(RSI7_GAP_MIN);
                else if (gap > RSI7_GAP_MAX)         why = "gap " + IntegerToString(gap) + " > " + IntegerToString(RSI7_GAP_MAX);
                else if (i_highs[c] >= m_PrevPriceS) why = "prix sommet pas plus bas (" +
                                                            DoubleToString(i_highs[c], _Digits) + " >= " +
                                                            DoubleToString(m_PrevPriceS, _Digits) + ")";
                else                                 why = "RSI sommet pas plus haut (" +
                                                            DoubleToString(i_rsis[c], 2) + " <= " +
                                                            DoubleToString(m_PrevRsiS, 2) + ")";

                LOG.INFO(m_Name + " : pivot haut confirmé " +
                         TimeToString(i_times[c], TIME_DATE | TIME_MINUTES) +
                         " high=" + DoubleToString(i_highs[c], _Digits) +
                         " RSI=" + DoubleToString(i_rsis[c], 2) +
                         " — pas de divergence (" + why + ")", __FUNCTION__);
            }
        }

        // === MISE À JOUR DE L'ÉTAT À CHAQUE PIVOT HAUT ===
        // Divergent OU NON : le prochain pivot haut se comparera à CELUI-CI.
        //-----------------------------------------------------------------------
        m_PrevPriceS   = i_highs[c];
        m_PrevRsiS     = i_rsis[c];
        m_PrevBarTimeS = i_times[c];
        m_HavePrevS    = true;
    }

    //+--------------------------------------------------------+
    //| TryBackfill (privé)                                     |
    //| Replay des confirmations HISTORIQUES pour initialiser   |
    //| l'état pivots — l'équivalent du chargement d'historique  |
    //| d'un indicateur TradingView (le Pine rejoue tout le      |
    //| chart ; l'EA démarre avec un état vide sinon).           |
    //|                                                        |
    //| Rejoue les confirmations des shifts n-7 … 2 (du plus     |
    //| ancien au plus récent, ordre chronologique) :            |
    //|   - shift 1 = confirmation de MAINTENANT → chemin live   |
    //|     (UpdateState), juste après ce backfill               |
    //|   - 500 bougies suffisent : tout pivot plus ancien aurait |
    //|     un gap > 60 avec tout nouveau pivot → aucun effet    |
    //|     sur les divergences futures (comportement identique  |
    //|     à un état vide : divergence impossible, état mis à   |
    //|     jour au prochain pivot)                              |
    //|                                                        |
    //| Données indicateur ASYNC : au démarrage (surtout tester),|
    //| CopyBuffer peut échouer tant que le RSI n'est pas        |
    //| calculé → retourne FALSE, sera retenté à la bougie       |
    //| suivante jusqu'à succès (une fois).                      |
    //|                                                        |
    //| Retour : TRUE = état initialisé (une fois pour toutes)   |
    //+--------------------------------------------------------+
    bool TryBackfill(void)
    {
        int bars_avail = Bars(Symbol(), m_TF);
        if (bars_avail < RSI7_MIN_BARS_PIVOT) return(false);   // historique trop court → on attend

        int n = RSI7_BACKFILL_BARS;              // fenêtre de replay…
        if (bars_avail < n) n = bars_avail;      // …bornée par l'historique disponible

        double   lows[];
        datetime times[];
        double   rsis[];
        ArraySetAsSeries(lows,  true);
        ArraySetAsSeries(times, true);
        ArraySetAsSeries(rsis,  true);

        if (CopyLow(Symbol(), m_TF, 0, n, lows) < n)   return(false);
        if (CopyTime(Symbol(), m_TF, 0, n, times) < n) return(false);
        if (CopyBuffer(m_HandleRSI, 0, 0, n, rsis) < n) return(false);   // RSI pas prêt → retry

        // Machine haute (short) : mêmes données en miroir — copie et
        // replay UNIQUEMENT si K_RSI7_Short (sinon état haute vierge,
        // zéro travail, bit-identique au long-only).
        //---------------------------------------------------------------
        double highs[];
        ArraySetAsSeries(highs, true);
        bool short_on = K_RSI7_Short;
        if (short_on && CopyHigh(Symbol(), m_TF, 0, n, highs) < n) return(false);

        // Replay chronologique des confirmations passées (shifts ≥ 2) :
        // DetectPivot met l'état à jour à CHAQUE pivot rencontré. Un pivot
        // est compté quand l'état a bougé (temps du pivot précédent changé).
        //----------------------------------------------------------------------
        int pivots_found = 0;
        int pivots_high_found = 0;
        for (int s = n - (2 * RSI7_PIVOT_SHIFT + 1); s >= 2; s--)
        {
            datetime prev_time_before = m_PrevBarTime;
            DetectPivot(lows, times, rsis, s, false);
            if (m_PrevBarTime != prev_time_before) pivots_found++;

            if (short_on)
            {
                datetime prev_time_before_s = m_PrevBarTimeS;
                DetectPivotShort(highs, times, rsis, s, false);
                if (m_PrevBarTimeS != prev_time_before_s) pivots_high_found++;
            }
        }

        // Le replay peut avoir posé m_Divergence (ou Short) sur la DERNIÈRE
        // confirmation historique (s=2) : on les annule — seule la
        // confirmation LIVE de la bougie shift 1 (traitée juste après, par
        // UpdateState) a le droit de poser les drapeaux. Sans ça, un signal
        // périmé pourrait être consommé si la bougie courante ne confirme
        // aucun pivot.
        //----------------------------------------------------------------------
        m_Divergence      = false;
        m_DivergenceShort = false;

        m_BackfillDone = true;
        LOG.INFO(m_Name + " : backfill pivots OK — " + IntegerToString(n) +
                 " bougies rejouées, " + IntegerToString(pivots_found) + " pivots" +
                 (short_on ? (" + " + IntegerToString(pivots_high_found) + " pivots hauts (short)") : "") +
                 (m_HavePrev ? (", dernier pivot " + TimeToString(m_PrevBarTime, TIME_DATE | TIME_MINUTES) +
                                " low=" + DoubleToString(m_PrevPrice, _Digits) +
                                " RSI=" + DoubleToString(m_PrevRsi, 2))
                            : ", aucun pivot (état vide)") +
                 (short_on ? (m_HavePrevS ? (", dernier pivot haut " + TimeToString(m_PrevBarTimeS, TIME_DATE | TIME_MINUTES) +
                                " high=" + DoubleToString(m_PrevPriceS, _Digits) +
                                " RSI=" + DoubleToString(m_PrevRsiS, 2))
                            : ", aucun pivot haut (état haute vide)") : ""), __FUNCTION__);
        return(true);
    }

//==================================
//--- PUBLIC
//==================================
public:

    //+--------------------------------------------------------+
    //| Config                                                  |
    //| Crée le handle RSI et réinitialise l'état pivots.       |
    //| Le backfill N'est PAS tenté ici : les données           |
    //| d'indicateur sont async (surtout dans le tester) — il   |
    //| sera exécuté au premier UpdateState réussi.             |
    //+--------------------------------------------------------+
    bool Config(const string i_name, const ENUM_TIMEFRAMES i_tf)
    {
        m_Name      = i_name;
        m_TF        = i_tf;
        m_HandleRSI = INVALID_HANDLE;

        // État pivots vierge (Pine : var prev* = na) — machine basse LONG
        //--------------------------------------------------------------
        m_BackfillDone = false;
        m_HavePrev     = false;
        m_PrevPrice    = 0.0;
        m_PrevRsi      = 0.0;
        m_PrevBarTime  = 0;
        m_Divergence   = false;

        // État pivots vierge — machine haute SHORT (miroir)
        //-----------------------------------------------------
        m_HavePrevS      = false;
        m_PrevPriceS     = 0.0;
        m_PrevRsiS       = 0.0;
        m_PrevBarTimeS   = 0;
        m_DivergenceShort = false;

        m_HandleRSI = iRSI(Symbol(), m_TF, (int)K_RSI7_Period, PRICE_CLOSE);
        if (m_HandleRSI == INVALID_HANDLE)
        {
            LOG.ERROR(m_Name + " : création du handle RSI(" +
                      IntegerToString((int)K_RSI7_Period) + ") impossible", __FUNCTION__);
            return(false);
        }

        LOG.INFO(m_Name + " : Scanner RSI7 SOLO initialisé (TF=" +
                 PeriodToString(m_TF) +
                 ", RSI="   + IntegerToString((int)K_RSI7_Period) +
                 ", SL_Bars=" + IntegerToString((int)K_RSI7_SL_Bars) +
                 ", TP_R=" + DoubleToString(K_RSI7_TP_R, 2) +
                 ", gap pivots [" + IntegerToString(RSI7_GAP_MIN) + ".." + IntegerToString(RSI7_GAP_MAX) + "]" +
                 (K_RSI7_Short ? ", LONG + SHORT (miroir baissier)"
                               : ", LONG uniquement"), __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| End                                                     |
    //+--------------------------------------------------------+
    void End(void)
    {
        if (m_HandleRSI != INVALID_HANDLE)
        {
            IndicatorRelease(m_HandleRSI);
            m_HandleRSI = INVALID_HANDLE;
        }
    }

    //+--------------------------------------------------------+
    //| UpdateState                                             |
    //|--------------------------------------------------------|
    //| La machine à pivots — appelée par Strategy à CHAQUE     |
    //| nouvelle bougie K_RSI7_TF, AVANT tout filtre d'exécution|
    //| (FIX ChatGPT #1 : l'état évolue avant les filtres).     |
    //|                                                        |
    //| Doit tourner même si : scanner non sélectionné, position|
    //| ouverte, filtres NEWS/heures actifs — fidélité Pine :   |
    //| l'indicateur calcule toujours, seule l'ENTRÉE est       |
    //| filtrée. Sinon l'état prev* serait troué et les gaps    |
    //| calculés sur des pivots non adjacents.                  |
    //|                                                        |
    //| 1er appel : replay historique (TryBackfill) pour un     |
    //| état chaud, comme un indicateur Pine chargé sur tout    |
    //| l'historique du chart.                                  |
    //|                                                        |
    //| Ensuite : confirmation de la bougie shift 1 (elle vient |
    //| de clôturer — équivalent barstate.isconfirmed du Pine). |
    //| Candidat pivot = shift 4, voisines = shifts 1..7 sauf 4.|
    //+--------------------------------------------------------+
    void UpdateState(void)
    {
        // La divergence est une propriété de LA bougie qui vient de
        // clôturer : recalculée à chaque appel, consommée par GetSignal.
        // Les deux machines (basse/long, haute/short) posent leur propre
        // drapeau — indépendants l'un de l'autre.
        //----------------------------------------------------------------
        m_Divergence      = false;
        m_DivergenceShort = false;

        // Backfill paresseux (une fois) : données async → retry à la bougie suivante
        //-----------------------------------------------------------------------------
        if (!m_BackfillDone)
        {
            if (!TryBackfill()) return;   // historique/RSI indisponible → état vide, on réessaiera
        }

        // Historique minimal pour la fenêtre pivot (Pine : bar_index >= 16)
        //--------------------------------------------------------------------
        if (Bars(Symbol(), m_TF) < RSI7_MIN_BARS_PIVOT) return;

        // Lecture de la fenêtre : shifts 0..7 (bougie formante 0 ignorée,
        // confirmée = 1, candidat pivot = 4, voisines jusqu'à 7)
        //------------------------------------------------------------------
        int window = 2 * RSI7_PIVOT_SHIFT + 2;   // = 8

        double   lows[];
        double   highs[];   // machine haute (short) — copiée si K_RSI7_Short
        datetime times[];
        double   rsis[];
        ArraySetAsSeries(lows,  true);
        ArraySetAsSeries(highs, true);
        ArraySetAsSeries(times, true);
        ArraySetAsSeries(rsis,  true);

        if (CopyLow(Symbol(), m_TF, 0, window, lows) < window)    return;
        if (CopyTime(Symbol(), m_TF, 0, window, times) < window)  return;
        if (CopyBuffer(m_HandleRSI, 0, 0, window, rsis) < window) return;

        // Confirmation de la bougie shift 1 → candidat pivot shift 4
        //--------------------------------------------------------------
        DetectPivot(lows, times, rsis, 1, true);

        // Machine haute (short) : même confirmation, miroir sur les highs.
        // TOUJOURS APRÈS le long (invariant de non-régression : la machine
        // basse ne peut jamais être perturbée par la machine haute — si
        // les highs manquent, le short saute CETTE confirmation, le long
        // a déjà été traité). Symétrie de traitement : indisponibilité
        // = bougie non traitée pour la machine concernée (même mode de
        // défaillance que le long quand CopyLow échoue ; en pratique
        // CopyLow/CopyHigh lisent la même historique et échouent ensemble).
        //---------------------------------------------------------------------
        if (K_RSI7_Short)
        {
            if (CopyHigh(Symbol(), m_TF, 0, window, highs) < window)
            {
                LOG.WARNING(m_Name + " : CopyHigh indisponible — machine courte sautée cette bougie", __FUNCTION__);
            }
            else
            {
                DetectPivotShort(highs, times, rsis, 1, true);
            }
        }
    }

    //+--------------------------------------------------------+
    //| HasPositionForSymbol                                   |
    //| Une position OUVERTE existe-t-elle pour CE scanner ?     |
    //| C'est le verrou SOLO du Pine ("active") : tant qu'une   |
    //| position existe, aucune nouvelle entrée n'est possible. |
    //+--------------------------------------------------------+
    bool HasPositionForSymbol(void)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = PositionGetTicket(i);
            if (PositionGetString (POSITION_SYMBOL) != Symbol())              continue;
            if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

            string l_comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(l_comment, m_Name) < 0) continue;

            return(true);
        }
        return(false);
    }

    //+--------------------------------------------------------+
    //| GetSignal                                               |
    //|--------------------------------------------------------|
    //| Conditions d'entrée sur la bougie qui vient de clôturer |
    //| (consommée au 1er tick de la nouvelle bougie) —         |
    //| Pine l.94 : validTF AND not active AND bar_index>=200   |
    //|             AND divergence AND close-stopCandidate>mint |
    //|                                                        |
    //|   - validTF            → K_RSI7_TF (le scanner travaille|
    //|                          sur SON TF, ici même)          |
    //|   - not active         → verrou SOLO (TryRsi7, AVANT    |
    //|                          GetSignal)                     |
    //|   - bar_index >= 200   → garde Bars() >= 200 ci-dessous |
    //|   - divergence         → drapeau posé par UpdateState à |
    //|                          la clôture de CETTE bougie     |
    //|   - close-stop>mintick → risk = ask - SL > tick size    |
    //|                          (short : sl - bid > tick size) |
    //|                                                        |
    //| SL : plus bas des K_RSI7_SL_Bars bougies, bougie signal |
    //| incluse (Pine : ta.lowest(low,10) — shift 1..10).       |
    //| TP : entry + K_RSI7_TP_R * risk (Pine : 3R).            |
    //| SHORT (miroir, K_RSI7_Short) : divergence cachée        |
    //| baissière → SL = plus HAUT des N bougies, entrée = bid, |
    //| TP = bid - K_RSI7_TP_R * risk. Exclusion mutuelle des   |
    //| deux drapeaux : le pivot candidat (même bougie pour les  |
    //| deux machines) ne peut pas être ET le plus bas ET le    |
    //| plus haut STRICT de ses 6 voisines.                      |
    //|                                                        |
    //| INPUT:                                                   |
    //|   i_tick : tick courant (ask réel d'exécution)          |
    //| OUTPUT:                                                  |
    //|   o_datas : STRUCT_STRATEGY rempli si retourne TRUE     |
    //|   Retour : TRUE si signal émis, FALSE sinon             |
    //|                                                          |
    //| IMPORTANT : ne JAMAIS appeler BROKER/MONEY/DATAS ici.   |
    //| CStrategy fait le relais après réception du signal.     |
    //+--------------------------------------------------------+
    bool GetSignal(const MqlTick &i_tick, STRUCT_STRATEGY &o_datas)
    {
        // Historique minimal (Pine : bar_index >= 200 — garde d'ENTRÉE,
        // distincte de la garde pivots bar_index >= 16)
        //----------------------------------------------------------------
        if (Bars(Symbol(), m_TF) < RSI7_WARMUP_BARS) return(false);

        // Divergence cachée confirmée à la clôture de la bougie signal ?
        // LONG = haussière (machine basse, Pine) ; SHORT = baissière
        // (machine haute, miroir — gated par K_RSI7_Short).
        // Exclusion mutuelle : les deux drapeaux sont posés par le pivot
        // de la MÊME bougie candidate (shift conf+3), qui ne peut pas
        // être à la fois le plus bas ET le plus haut strict de ses 6
        // voisines → jamais deux sens le même tick.
        //-----------------------------------------------------------------
        bool go_long  = m_Divergence;
        bool go_short = K_RSI7_Short && m_DivergenceShort;
        if (!go_long && !go_short) return(false);

        // Tick size (filtre anti-risque-nul, commun aux deux sens)
        //-----------------------------------------------------------
        double min_tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if (min_tick <= 0.0) min_tick = _Point;

        if (go_long)
        {
        // === SL = PLUS BAS DES N BOUGIES, BOUGIE SIGNAL INCLUSE ===
        // (Pine : stopCandidate = ta.lowest(low,10) sur la bougie de
        //  signal — iLowest(shift 1, count N) couvre les shifts 1..N)
        //--------------------------------------------------------------
        int lowest_idx = iLowest(Symbol(), m_TF, MODE_LOW, (int)K_RSI7_SL_Bars, 1);
        if (lowest_idx < 0) return(false);
        double sl = iLow(Symbol(), m_TF, lowest_idx);

        // === ENTRÉE = ASK RÉEL D'EXÉCUTION ===
        // (équivalent live du "close" du Pine : l'ordre part au 1er
        //  tick de la bougie suivante — convention projet, cf. EMA50)
        //----------------------------------------------------------
        double entry = i_tick.ask;

        // === FILTRE ANTI-RISQUE-NUL ===
        // (Pine : close - stopCandidate > syminfo.mintick)
        //----------------------------------------------------
        double risk = entry - sl;
        if (risk <= min_tick) return(false);

        // === SIGNAL D'ACHAT → REMPLIR STRUCT_STRATEGY ===
        // (LONG : divergence cachée haussière, Pine l.94-97)
        //----------------------------------------------------------
        ZeroMemory(o_datas);
        o_datas.Trend         = eT_Bull;
        o_datas.Entry         = entry;                        // entrée marché au prix courant
        o_datas.StopLoss      = sl;                           // plus bas des N bougies
        o_datas.TakeProfit    = entry + K_RSI7_TP_R * risk;   // TP = K_RSI7_TP_R R (Pine : 3R)
        o_datas.IsMarketOrder = true;                         // ordre au marché

        LOG.INFO(m_Name + " : RSI7 ACHAT divergence cachée | SL " +
                 IntegerToString((int)K_RSI7_SL_Bars) + " bars=" +
                 DoubleToString(sl, _Digits) +
                 " | Ask=" + DoubleToString(entry, _Digits) +
                 " | TP=" + DoubleToString(o_datas.TakeProfit, _Digits) +
                 " | R=" + DoubleToString(K_RSI7_TP_R, 2),
                 __FUNCTION__);
        return(true);
        }

        // === SHORT : MIROIR EXACT DU LONG (divergence baissière) ===
        //--------------------------------------------------------------
        // SL = plus HAUT des N bougies (bougie signal incluse) ;
        // entrée = bid réel ; TP = entry - K_RSI7_TP_R R (sous
        // l'entrée). Verrou SOLO partagé : une position à la fois,
        // long OU short (HasPositionForSymbol ne distingue pas le
        // sens — sémantique identique à l'option short EMA50).
        //--------------------------------------------------------------
        int highest_idx = iHighest(Symbol(), m_TF, MODE_HIGH, (int)K_RSI7_SL_Bars, 1);
        if (highest_idx < 0) return(false);
        double sl = iHigh(Symbol(), m_TF, highest_idx);

        // Entrée = bid réel (miroir de l'ask long)
        //--------------------------------------------
        double entry = i_tick.bid;

        // Filtre anti-risque-nul, sens short : sl - entry > mintick
        //-------------------------------------------------------------
        double risk = sl - entry;
        if (risk <= min_tick) return(false);

        // === SIGNAL DE VENTE → REMPLIR STRUCT_STRATEGY ===
        //----------------------------------------------------------
        ZeroMemory(o_datas);
        o_datas.Trend         = eT_Bear;
        o_datas.Entry         = entry;                        // entrée marché au prix courant
        o_datas.StopLoss      = sl;                           // plus haut des N bougies
        o_datas.TakeProfit    = entry - K_RSI7_TP_R * risk;   // TP = K_RSI7_TP_R R sous l'entrée
        o_datas.IsMarketOrder = true;                         // ordre au marché

        LOG.INFO(m_Name + " : RSI7 VENTE divergence cachée baissière | SL " +
                 IntegerToString((int)K_RSI7_SL_Bars) + " bars=" +
                 DoubleToString(sl, _Digits) +
                 " | Bid=" + DoubleToString(entry, _Digits) +
                 " | TP=" + DoubleToString(o_datas.TakeProfit, _Digits) +
                 " | R=" + DoubleToString(K_RSI7_TP_R, 2),
                 __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| GetNamePublic                                          |
    //+--------------------------------------------------------+
    string GetNamePublic(void) { return(m_Name); }

};  // fin de la classe CScannerRsi7
