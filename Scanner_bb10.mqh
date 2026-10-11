//+------------------------------------------------------------------+
//|                                                                  |
//| Scanner_bb10.mqh — SCANNER BB10 SOLO (réintégration Bollinger)   |
//|                                                                  |
//| Adaptation du script Pine "SCANNER BB10 | NASDAQ H1 | SOLO |     |
//| SL5 TP3R" (05_BOLLINGER_NASDAQ_SOLO.pine) dans l'architecture    |
//| parallèle multi-scanners de Koenigin.                            |
//|                                                                  |
//| - Classe CONCRETE CScannerBb10 (pas d'héritage, pas de virtual)  |
//| - LONG : réintégration haussière — toujours actif (le Pine       |
//|   d'origine est long uniquement, fidélité Pine stricte)          |
//| - SHORT : réintégration baissière (miroir exact, bande HAUTE) —  |
//|   OPTIONNEL, input K_BB10_Short = false par défaut. Touche       |
//|   personnelle Koenigin (décision utilisateur) et piste           |
//|   d'optimisation future — même pattern que K_EMA50_Short et      |
//|   K_RSI7_Short (off = fidélité Pine : le .pine n'a aucun short)  |
//| - Bande = Bollinger sur les CLÔTURES : mid = SMA(P), sd =        |
//|   écart-type POPULATION (comme ta.stdev Pine), calcul MANUEL     |
//|   (pas de handle : contrôle total du mode de calcul — ni         |
//|   iBands ni iStdDev, dont les conventions ne sont pas garanties  |
//|   identiques à ta.stdev)                                         |
//| - lower = mid - Sigma*sd ; upper = mid + Sigma*sd                |
//| - LONG  (Pine l.27) : sd>0 ET close[1]<=lower[1] ET close>lower  |
//|   = première clôture de RETOUR au-dessus de la bande basse       |
//| - SHORT (miroir maison) : sd>0 ET close[1]>=upper[1] ET          |
//|   close<upper = première clôture de retour EN-DESSOUS de la      |
//|   bande haute                                                     |
//| - SL long = plus BAS des N bougies ; SL short = plus HAUT        |
//|   (bougie signal incluse, N = K_BB10_SL_Bars, Pine : 5)          |
//| - TP long = entry + 3R (ask) ; TP short = entry - 3R (bid)       |
//| - 1 trade simultané max (HasPositionForSymbol) — le verrou SOLO  |
//|   ... et UNIQUEMENT si sélectionné dans le panier (K_BB10_Trade) |
//| - Entrée au marché (IsMarketOrder = true) au 1er tick qui suit   |
//|   la clôture de la bougie de signal                               |
//| - Pas de break-even, pas de trailing (fidélité Pine : le bracket |
//|   est figé à l'entrée et porté par le broker)                     |
//|                                                                  |
//| === TRADUCTION PINE → MQL5 ===                                    |
//| - "TF Valide" (graphe H1 imposé)     → K_BB10_TF (le scanner     |
//|   travaille sur SON TF, quel que soit le TF du chart)             |
//| - barstate.isconfirmed              → anti-rejeu de CStrategy :  |
//|   GetSignal n'est appelé qu'au 1er tick de chaque nouvelle bougie |
//|   K_BB10_TF (la bougie signal = shift 1, clôturée)                |
//| - ÉTAT PERSISTANT (active/entry/sl/tp)→ position RÉELLE : le      |
//|   verrou SOLO = HasPositionForSymbol, le bracket SL/TP est posé  |
//|   avec l'ordre et géré par le broker                              |
//| - Simulation gapSL/gapTP + priorité SL/TP → exécution réelle      |
//|   broker (le Pine simulait les sorties sur OHLC ; ici SL/TP      |
//|   natifs, gaps traités au prix réel du marché)                    |
//| - entrée = close de la bougie signal → ask/bid au 1er tick        |
//|   suivant (convention projet : lot et TP calculés sur le prix     |
//|   réel d'exécution)                                               |
//| - bar_index >= 200 (bande "chaude") → Bars()-2 >= 200 (l'index    |
//|   Pine de la bougie signal shift 1 = Bars()-2 — convention        |
//|   audit RSI7 P1-1)                                                 |
//| - close - stopCandidate > mintick   → DEUX contrôles distincts    |
//|   (convention audit RSI7 P1-2) :                                   |
//|   (1) FILTRE PINE sur la CLÔTURE de la bougie signal (fidélité :  |
//|       ce que le Pine aurait rejeté n'est JAMAIS tradé),           |
//|   (2) GARDE D'EXÉCUTION sur le prix réel ask/bid (risque          |
//|       strictement positif au prix disponible).                    |
//| - Capital virtuel 100k / cap cash / commissions 0,01% du Pine →   |
//|   NON REPRODUITS : sizing par le module MONEY standard            |
//|   (MONEY.CalculateLotSize dans ExecuteSignal — risque 1%,         |
//|   plafond 2,5%, fallback MinLot). DÉCISION UTILISATEUR : "le      |
//|   sizing utilise ce qui est dans Money, plus besoin de recréer    |
//|   un autre". Le capital virtuel ne servait dans le Pine qu'à      |
//|   dimensionner les quantités de la simulation.                    |
//| - Portes de dates TV (startDate/limitEnd/endDate) et strictChart  |
//|   → non reproduites : artefacts de la simulation TradingView.     |
//|   Garde symbole = I_Symbol_Name au niveau EA, TF = K_BB10_TF.     |
//|                                                                  |
//| Le scanner ne fait AUCUN appel direct à BROKER, MONEY ou DATAS.  |
//| Il remplit STRUCT_STRATEGY et CStrategy fait le reste.            |
//|                                                                  |
//| Pas d'UpdateState : le scanner est SANS ÉTAT (la bande et le      |
//| signal se recalculent à la demande sur les bougies ; rien ne      |
//| survit d'une bougie à l'autre). Un échec de lecture (CopyClose)   |
//| ne corrompt rien : la bougie est sans signal, comme une alerte    |
//| Pine non prise (schéma EMA50, validé par l'audit RSI7 pour les    |
//| scanners sans mémoire).                                          |
//| Pas de verrou pending : ordres au marché uniquement.              |
//+------------------------------------------------------------------+


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////
// Garde d'historique minimal (Pine : bar_index >= 200 sur la bougie
// SIGNAL — le contrôle applique Bars()-2 >= 200, cf. audit RSI7 P1-1).
// Étendue automatiquement si l'utilisateur met une période BB plus
// longue que la valeur Pine d'origine.
#define BB10_WARMUP_BARS  200

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
//---   Paramètres SCANNER BB10 SOLO
//============================================
// PANIER DE STRATÉGIES : greffé ≠ tradé.
// Ce toggle décide si CE scanner trade. Le scanner reste câblé dans
// Strategy (Config/Detection) mais DORMANT tant que la case
// n'est pas cochée : aucun signal, aucune entrée. Les positions
// déjà ouvertes avant dé-sélection courent jusqu'à leur SL/TP
// (portés par le broker — jamais touchées par le toggle).
// False par défaut : rien ne trade tant que l'utilisateur n'a
// rien choisi dans le panier.
input bool               K_BB10_Trade   = false;       // Panier : trader BB10 SOLO ?
input ENUM_TIMEFRAMES    K_BB10_TF      = PERIOD_H1;   // TF de travail (Pine : TF Valide = H1)
input uint               K_BB10_Period  = 10;          // Période Bollinger (Pine : 10)
input double             K_BB10_Sigma   = 2.0;         // Largeur de bande en sigma (Pine : 2.0)
input uint               K_BB10_SL_Bars = 5;           // Plus bas de combien de bougies pour le SL (Pine : 5)
input double             K_BB10_TP_R    = 3.0;         // Objectif TP en R (Pine : 3R)
// SHORT OPTIONNEL : le Pine d'origine est long uniquement (BB_01677
// "achats uniquement", Pine l.15). K_BB10_Short=true ajoute le miroir :
// première clôture de retour EN-DESSOUS de la bande HAUTE ;
// SL = plus HAUT des N bougies ; TP = bid - 3R. False par défaut =
// fidélité Pine. Touche personnelle Koenigin + piste d'optimisation
// future (pattern K_EMA50_Short / K_RSI7_Short).
input bool               K_BB10_Short   = false;       // Activer short (Pine : long uniquement)

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
class CScannerBb10
{
//==================================
//--- PRIVATE
//==================================
private:
    // Identité du scanner
    //---------------------
    string          m_Name;             // Nom logique ("Bb10Scanner") — préfixe du comment d'ordre
    ENUM_TIMEFRAMES m_TF;               // Timeframe de travail (K_BB10_TF)

    //+--------------------------------------------------------+
    //| BandsAt                                                 |
    //| Bollinger d'une fenêtre de P clôtures, dans le tableau  |
    //| SÉRIE i_close (index 0 = shift 1, bougie signal ;        |
    //| index 1 = shift 2 ; etc. — sortie directe de CopyClose   |
    //| avec ArraySetAsSeries).                                  |
    //|                                                          |
    //| mid = SMA(P) ; sd = écart-type POPULATION (division par  |
    //| P, comme ta.stdev Pine) — PAS l'écart-type d'échantillon |
    //| (P-1). Calcul manuel volontaire : ni iBands ni iStdDev.  |
    //|                                                          |
    //| INPUT:                                                   |
    //|   i_close : clôtures en série (index 0 = plus récente)   |
    //|   i_start : décalage de départ dans i_close              |
    //|            (0 = fenêtre de la bougie signal shift 1,     |
    //|             1 = fenêtre de la bougie précédente shift 2) |
    //| OUTPUT:                                                  |
    //|   o_mid, o_sd : moyenne et écart-type population         |
    //|   Retour : TRUE si la fenêtre est complète               |
    //+--------------------------------------------------------+
    bool BandsAt(const double &i_close[], const int i_start,
                 double &o_mid, double &o_sd)
    {
        int p = (int)K_BB10_Period;
        if (p < 2)                        return(false);
        if (ArraySize(i_close) < i_start + p) return(false);

        double sum = 0.0;
        for (int i = i_start; i < i_start + p; i++) sum += i_close[i];
        double mid = sum / p;

        double var = 0.0;
        for (int i = i_start; i < i_start + p; i++)
        {
            double d = i_close[i] - mid;
            var += d * d;
        }

        o_mid = mid;
        o_sd  = MathSqrt(var / p);   // POPULATION (ta.stdev Pine)
        return(true);
    }

//==================================
//--- PUBLIC
//==================================
public:

    //+--------------------------------------------------------+
    //| Config                                                  |
    //+--------------------------------------------------------+
    bool Config(const string i_name, const ENUM_TIMEFRAMES i_tf)
    {
        m_Name = i_name;
        m_TF   = i_tf;

        LOG.INFO(m_Name + " : Scanner BB10 SOLO initialisé (TF=" +
                 PeriodToString(m_TF) +
                 ", BB="    + IntegerToString((int)K_BB10_Period) +
                 ", Sigma=" + DoubleToString(K_BB10_Sigma, 1) +
                 ", SL_Bars=" + IntegerToString((int)K_BB10_SL_Bars) +
                 ", TP_R=" + DoubleToString(K_BB10_TP_R, 2) + ")", __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| End                                                     |
    //+--------------------------------------------------------+
    //| Pas de handle d'indicateur à libérer : la bande est      |
    //| calculée à la demande sur CopyClose (calcul manuel).     |
    //+--------------------------------------------------------+
    void End(void)
    {
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
    //| Vérifie les conditions d'entrée sur la bougie qui vient |
    //| de clôturer (shift=1, appel au 1er tick de la nouvelle  |
    //| bougie — équivalent barstate.isconfirmed du Pine) :     |
    //|   - historique suffisant (Pine : bar_index >= 200)      |
    //|   - LONG réintégration (Pine l.27, toujours actif) :    |
    //|     close[1] <= lower[1] ET close > lower               |
    //|   - SHORT réintégration (si K_BB10_Short, miroir        |
    //|     bande haute) : close[1] >= upper[1] ET close<upper  |
    //|   - SL : plus bas (long) / plus HAUT (short) des        |
    //|     K_BB10_SL_Bars bougies, bougie signal incluse       |
    //|   - filtre Pine sur la CLÔTURE puis garde d'exécution   |
    //|     sur le prix réel (convention audit RSI7 P1-2)       |
    //|                                                          |
    //| INPUT:                                                   |
    //|   i_tick : tick courant (ask/bid réels d'exécution)     |
    //| OUTPUT:                                                  |
    //|   o_datas : STRUCT_STRATEGY rempli si retourne TRUE     |
    //|   Retour : TRUE si signal émis, FALSE sinon             |
    //|                                                          |
    //| IMPORTANT : ne JAMAIS appeler BROKER/MONEY/DATAS ici.   |
    //| CStrategy fait le relais après réception du signal.     |
    //+--------------------------------------------------------+
    bool GetSignal(const MqlTick &i_tick, STRUCT_STRATEGY &o_datas)
    {
        // (1) Historique minimal (Pine : bar_index >= 200 sur la bougie
        //     SIGNAL). Son index Pine = Bars()-2 (shift 0 = bougie
        //     formante = index Bars()-1) → Bars()-2 >= 200, soit
        //     Bars() >= 202. La fenêtre BB du shift 2 exige aussi
        //     P+2 bougies (shifts 0..P+1).
        //----------------------------------------------------------------
        int min_bars = MathMax(BB10_WARMUP_BARS + 2, (int)K_BB10_Period + 2);
        if (Bars(Symbol(), m_TF) < min_bars) return(false);

        // (2) Clôtures des shifts 1..P+1 (une seule lecture)
        //-----------------------------------------------------
        int need = (int)K_BB10_Period + 1;
        double c[];
        ArraySetAsSeries(c, true);
        if (CopyClose(Symbol(), m_TF, 1, need, c) < need)
        {
            LOG.WARNING(m_Name + " : CopyClose indisponible", __FUNCTION__);
            return(false);
        }
        double close1 = c[0];   // bougie signal (shift 1)
        double close2 = c[1];   // bougie précédente (shift 2)
        if (close1 <= 0.0 || close2 <= 0.0) return(false);

        // (3) Bandes des bougies signal (shift 1) et précédente (shift 2)
        //------------------------------------------------------------------
        double mid1 = 0.0, sd1 = 0.0, mid2 = 0.0, sd2 = 0.0;
        if (!BandsAt(c, 0, mid1, sd1)) return(false);   // fenêtre shifts 1..P
        if (!BandsAt(c, 1, mid2, sd2)) return(false);   // fenêtre shifts 2..P+1
        double lower1 = mid1 - K_BB10_Sigma * sd1;
        double lower2 = mid2 - K_BB10_Sigma * sd2;
        double upper1 = mid1 + K_BB10_Sigma * sd1;
        double upper2 = mid2 + K_BB10_Sigma * sd2;

        // === DÉTECTION DE SENS ===
        // LONG  (Pine l.27, toujours actif) :
        //   signal = sd>0 and close[1]<=lower[1] and close>lower
        //   → la bougie PRÉCÉDENTE clôturait sous/sur SA bande basse,
        //     la bougie SIGNAL clôture AU-DESSUS de SA bande basse.
        //     Bornes Pine : close[1] <= lower[1] INCLUSIF,
        //                   close > lower STRICT.
        // SHORT (miroir maison, gated par K_BB10_Short) :
        //   close[1] >= upper[1] INCLUSIF ET close < upper STRICT.
        //   Exclusion mutuelle STRUCTURELLE : la bougie précédente ne
        //   peut pas clôturer à LA FOIS sous lower[1] ET sur upper[1]
        //   quand sd[1] > 0 (lower < upper). Cas dégénéré sd2 = 0
        //   (P clôtures identiques → lower2 == upper2 == mid2, close2
        //   == mid2 armé des deux côtés) : close1 devient alors un
        //   EXTRÊME de sa propre fenêtre (1 valeur ≠ 9 identiques →
        //   |close1 - mid1| = 0.9|d| > 2*sd1 = 0.6|d| → hors bande)
        //   → un seul des deux sens peut compléter. Le if/else avec
        //   priorité LONG reste une ceinture défensive (convention
        //   RSI7 : le long est traité avant le short).
        //---------------------------------------------------------------
        bool go_long  = (sd1 > 0.0) && (close2 <= lower2) && (close1 > lower1);
        bool go_short = K_BB10_Short && (sd1 > 0.0) && (close2 >= upper2) && (close1 < upper1);
        if (!go_long && !go_short) return(false);

        // Tick size (filtre anti-risque-nul, commun aux deux sens)
        //-----------------------------------------------------------
        double min_tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if (min_tick <= 0.0) min_tick = _Point;

        if (go_long)
        {
            // === LONG : SL = PLUS BAS DES N BOUGIES ===
            // (Pine : stopCandidate = ta.lowest(low,5) sur la bougie de
            //  signal — iLowest(shift 1, count N) couvre les shifts 1..N,
            //  bougie signal INCLUSE)
            //------------------------------------------------------
            int lowest_idx = iLowest(Symbol(), m_TF, MODE_LOW, (int)K_BB10_SL_Bars, 1);
            if (lowest_idx < 0) return(false);
            double sl = iLow(Symbol(), m_TF, lowest_idx);

            // === FILTRE PINE SUR LA CLÔTURE (audit RSI7 P1-2) ===
            // Pine l.59/l.64 : distance = close - stopCandidate >
            // syminfo.mintick, évalué sur la CLÔTURE de la bougie
            // signal — PAS sur le prix d'exécution. Le spread et le
            // mouvement entre la clôture et le 1er tick ne peuvent
            // pas faire accepter une entrée que le Pine rejette.
            //--------------------------------------------------------------
            if (close1 - sl <= min_tick) return(false);   // le Pine aurait rejeté

            // === ENTRÉE + GARDE D'EXÉCUTION (distincte du filtre) ===
            // Adaptation MQL5 : l'ordre part à l'ask réel au 1er tick de
            // la bougie suivante — il faut un risque strictement positif
            // (> tick) au prix DISPONIBLE. Le sizing et le TP sont fondés
            // sur CE prix réel (le TP peut différer du TP simulé Pine de
            // (ask - close)).
            //-------------------------------------------------------------------
            double entry = i_tick.ask;
            double risk  = entry - sl;
            if (risk <= min_tick) return(false);

            // === SIGNAL D'ACHAT → REMPLIR STRUCT_STRATEGY ===
            //------------------------------------------------
            ZeroMemory(o_datas);
            o_datas.Trend         = eT_Bull;
            o_datas.Entry         = entry;                       // entrée marché au prix courant
            o_datas.StopLoss      = sl;                          // plus bas des N bougies
            o_datas.TakeProfit    = entry + K_BB10_TP_R * risk;  // TP = K_BB10_TP_R R
            o_datas.IsMarketOrder = true;                        // ordre au marché

            LOG.INFO(m_Name + " : BB10 ACHAT réintégration bande basse | Close=" +
                     DoubleToString(close1, _Digits) +
                     " | Basse=" + DoubleToString(lower1, _Digits) +
                     " | SL "    + IntegerToString((int)K_BB10_SL_Bars) + " bars=" +
                                  DoubleToString(sl, _Digits) +
                     " | Ask="   + DoubleToString(entry, _Digits) +
                     " | TP="    + DoubleToString(o_datas.TakeProfit, _Digits) +
                     " | R="     + DoubleToString(K_BB10_TP_R, 2),
                     __FUNCTION__);
            return(true);
        }

        // === SHORT : MIROIR EXACT DU LONG (bande HAUTE) ===
        //----------------------------------------------------
        // SL = plus HAUT des N bougies ; entrée = bid réel ;
        // TP = entry - K_BB10_TP_R R (sous l'entrée).
        // Le verrou SOLO reste partagé : une position à la fois,
        // long OU short (HasPositionForSymbol ne distingue pas le
        // sens — fidèle au "active" du Pine).
        //----------------------------------------------------
        int highest_idx = iHighest(Symbol(), m_TF, MODE_HIGH, (int)K_BB10_SL_Bars, 1);
        if (highest_idx < 0) return(false);
        double sl = iHigh(Symbol(), m_TF, highest_idx);

        // === FILTRE PINE MIROIR : SL - CLÔTURE(bougie signal) > mintick ===
        // (le Pine d'origine n'a pas de short : miroir exact du filtre
        //  close - SL du long, évalué sur la CLÔTURE — audit RSI7 P1-2)
        //--------------------------------------------------------------------
        if (sl - close1 <= min_tick) return(false);   // le miroir du Pine aurait rejeté

        // === ENTRÉE + GARDE D'EXÉCUTION (distincte du filtre) ===
        //------------------------------------------------------------
        double entry = i_tick.bid;
        double risk  = sl - entry;
        if (risk <= min_tick) return(false);

        // === SIGNAL DE VENTE → REMPLIR STRUCT_STRATEGY ===
        //---------------------------------------------------
        ZeroMemory(o_datas);
        o_datas.Trend         = eT_Bear;
        o_datas.Entry         = entry;                        // entrée marché au prix courant
        o_datas.StopLoss      = sl;                           // plus haut des N bougies
        o_datas.TakeProfit    = entry - K_BB10_TP_R * risk;   // TP = K_BB10_TP_R R (sous l'entrée)
        o_datas.IsMarketOrder = true;                         // ordre au marché

        LOG.INFO(m_Name + " : BB10 VENTE réintégration bande haute | Close=" +
                 DoubleToString(close1, _Digits) +
                 " | Haute=" + DoubleToString(upper1, _Digits) +
                 " | SL "    + IntegerToString((int)K_BB10_SL_Bars) + " bars=" +
                              DoubleToString(sl, _Digits) +
                 " | Bid="   + DoubleToString(entry, _Digits) +
                 " | TP="    + DoubleToString(o_datas.TakeProfit, _Digits) +
                 " | R="     + DoubleToString(K_BB10_TP_R, 2),
                 __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| GetNamePublic                                          |
    //+--------------------------------------------------------+
    string GetNamePublic(void) { return(m_Name); }

};  // fin de la classe CScannerBb10
