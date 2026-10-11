//+------------------------------------------------------------------+
//|                                                                  |
//| Scanner_ema50.mqh — SCANNER EMA50 SOLO (crossUp / SL N bas / TP 2R)|
//|                                                                  |
//| Adaptation du script Pine "SCANNER NASDAQ EMA50 | SOLO | SL10    |
//| | TP2R" (H1) dans l'architecture parallèle multi-scanners de     |
//| Koenigin.                                                        |
//|                                                                  |
//| - Classe CONCRETE CScannerEma50 (pas d'héritage, pas de virtual)|
//| - Bull uniquement (achats)                                        |
//| - Entrée : clôture franchit l'EMA vers le haut (crossUp)         |
//| - SL = plus bas des N dernières bougies, bougie signal incluse   |
//| - TP = entry + 2R (basé sur ask réel d'exécution)                |
//| - 1 trade simultané max (HasPositionForSymbol) — le verrou SOLO |
//|   ... et UNIQUEMENT si sélectionné dans le panier (K_EMA50_Trade) |
//| - Entrée au marché (IsMarketOrder = true) au 1er tick qui suit   |
//|   la clôture de la bougie de signal                               |
//| - Pas de break-even, pas de trailing (fidélité Pine : le bracket|
//|   est figé à l'entrée et porté par le broker)                     |
//|                                                                  |
//| === TRADUCTION PINE → MQL5 ===                                    |
//| - "TF Valide" (graphe H1 imposé)     → K_EMA50_TF (le scanner    |
//|   travaille sur SON TF, quel que soit le TF du chart)             |
//| - barstate.isconfirmed              → anti-rejeu de CStrategy :  |
//|   GetSignal n'est appelé qu'à la première tick de chaque nouvelle |
//|   bougie K_EMA50_TF (la bougie signal = shift 1, clôturée)        |
//| - ÉTAT PERSISTANT (active/entry/sl/tp)→ position RÉELLE : le      |
//|   verrou SOLO = HasPositionForSymbol, le bracket SL/TP est posé  |
//|   avec l'ordre et géré par le broker                              |
//| - Simulation gapSL/gapTP + priorité SL/TP → exécution réelle      |
//|   broker (le Pine simulait les sorties sur OHLC ; ici SL/TP      |
//|   natifs, gaps traités au prix réel du marché)                    |
//| - entrée = close de la bougie signal → ask au 1er tick suivant    |
//|   (convention projet, cf. Fibo "Option B" : lot et TP calculés   |
//|   sur le prix réel d'exécution)                                   |
//| - bar_index >= 200 (EMA "chaude")    → garde Bars() >= 200        |
//| - close - stopCandidate > mintick    → risque > tick size         |
//|                                                                  |
//| Le scanner ne fait AUCUN appel direct à BROKER, MONEY ou DATAS.  |
//| Il remplit STRUCT_STRATEGY et CStrategy fait le reste.            |
//|                                                                  |
//| Pas d'UpdateState : le scanner est SANS ÉTAT (le crossUp se      |
//| calcule sur les bougies à la demande ; pas de swing à suivre).   |
//| Pas de RollbackSignal : un signal manqué est une propriété de la |
//| bougie, il ne se rejouera pas — comme une alerte Pine non prise. |
//| Pas de verrou pending : ordres au marché uniquement.             |
//+------------------------------------------------------------------+


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////
// Garde d'historique minimal (Pine : bar_index >= 200).
// Étendue automatiquement si l'utilisateur met une EMA ou un
// lookback SL plus longs que la valeur Pine d'origine.
#define EMA50_WARMUP_BARS  200

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
//---   Paramètres SCANNER EMA50 SOLO
//============================================
// PANIER DE STRATÉGIES : greffé ≠ tradé.
// Ce toggle décide si CE scanner trade. Le scanner reste câblé dans
// Strategy (Config/End/Detection) mais DORMANT tant que la case
// n'est pas cochée : aucun signal, aucune entrée. Les positions
// déjà ouvertes avant dé-sélection courent jusqu'à leur SL/TP
// (portés par le broker — jamais touchées par le toggle).
// False par défaut : rien ne trade tant que l'utilisateur n'a
// rien choisi dans le panier.
input bool               K_EMA50_Trade   = false;       // Panier : trader EMA50 SOLO ?
input ENUM_TIMEFRAMES    K_EMA50_TF      = PERIOD_H1;   // TF de travail (Pine : TF Valide = H1)
input uint               K_EMA50_Period  = 50;          // Période EMA (Pine : 50)
input uint               K_EMA50_SL_Bars = 10;          // Plus bas de combien de bougies pour le SL (Pine : 10)
input double             K_EMA50_TP_R    = 2.0;         // Objectif TP en R (Pine : 2R)

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
class CScannerEma50
{
//==================================
//--- PRIVATE
//==================================
private:
    // Identité du scanner
    //---------------------
    string          m_Name;             // Nom logique ("Ema50Scanner") — préfixe du comment d'ordre
    ENUM_TIMEFRAMES m_TF;               // Timeframe de travail (K_EMA50_TF)

    // Handle d'indicateur
    //---------------------
    int             m_HandleEMA;        // Handle iMA (EMA, K_EMA50_Period, PRICE_CLOSE)

//==================================
//--- PUBLIC
//==================================
public:

    //+--------------------------------------------------------+
    //| Config                                                  |
    //+--------------------------------------------------------+
    bool Config(const string i_name, const ENUM_TIMEFRAMES i_tf)
    {
        m_Name      = i_name;
        m_TF        = i_tf;
        m_HandleEMA = INVALID_HANDLE;

        m_HandleEMA = iMA(Symbol(), m_TF, (int)K_EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
        if (m_HandleEMA == INVALID_HANDLE)
        {
            LOG.ERROR(m_Name + " : création du handle EMA(" +
                      IntegerToString((int)K_EMA50_Period) + ") impossible", __FUNCTION__);
            return(false);
        }

        LOG.INFO(m_Name + " : Scanner EMA50 SOLO initialisé (TF=" +
                 PeriodToString(m_TF) +
                 ", EMA="   + IntegerToString((int)K_EMA50_Period) +
                 ", SL_Bars=" + IntegerToString((int)K_EMA50_SL_Bars) +
                 ", TP_R=" + DoubleToString(K_EMA50_TP_R, 2) + ")", __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| End                                                     |
    //+--------------------------------------------------------+
    void End(void)
    {
        if (m_HandleEMA != INVALID_HANDLE)
        {
            IndicatorRelease(m_HandleEMA);
            m_HandleEMA = INVALID_HANDLE;
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
    //| Vérifie les conditions d'entrée sur la bougie qui vient |
    //| de clôturer (shift=1, appel au 1er tick de la nouvelle  |
    //| bougie — équivalent barstate.isconfirmed du Pine) :     |
    //|   - historique suffisant (Pine : bar_index >= 200)      |
    //|   - crossUp : Close[1] > EMA[1] ET Close[2] <= EMA[2]   |
    //|   - SL = plus bas des K_EMA50_SL_Bars bougies (1..N)    |
    //|   - risque > tick size (Pine : close - stop > mintick)  |
    //|                                                          |
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
        // Historique minimal (Pine : bar_index >= 200, EMA "chaude")
        //------------------------------------------------------------
        int min_bars = MathMax(EMA50_WARMUP_BARS, (int)K_EMA50_Period + (int)K_EMA50_SL_Bars);
        if (Bars(Symbol(), m_TF) < min_bars) return(false);

        // Bougie signal = shift 1 (elle vient de clôturer)
        // Bougie précédente = shift 2
        //---------------------------------------------------
        double close1 = iClose(Symbol(), m_TF, 1);
        double close2 = iClose(Symbol(), m_TF, 2);
        if (close1 <= 0.0 || close2 <= 0.0) return(false);

        // EMA sur les 2 dernières bougies clôturées
        //--------------------------------------------
        double ema_buf[];
        ArraySetAsSeries(ema_buf, true);
        if (CopyBuffer(m_HandleEMA, 0, 1, 2, ema_buf) < 2)
        {
            LOG.WARNING(m_Name + " : CopyBuffer EMA indisponible", __FUNCTION__);
            return(false);
        }
        double ema1 = ema_buf[0];   // EMA bougie signal (shift 1)
        double ema2 = ema_buf[1];   // EMA bougie précédente (shift 2)

        // === CROSSUP (Pine : close > ema and close[1] <= ema[1]) ===
        //--------------------------------------------------------------
        bool crossUp = (close1 > ema1) && (close2 <= ema2);
        if (!crossUp) return(false);

        // === SL = PLUS BAS DES N BOUGIES, BOUGIE SIGNAL INCLUSE ===
        // (Pine : ta.lowest(low, 10) évalué sur la bougie de signal)
        //--------------------------------------------------------------
        int lowest_idx = iLowest(Symbol(), m_TF, MODE_LOW, (int)K_EMA50_SL_Bars, 1);
        if (lowest_idx < 0) return(false);
        double sl = iLow(Symbol(), m_TF, lowest_idx);

        // === ENTRÉE = ASK RÉEL D'EXÉCUTION ===
        // (équivalent live du "close" du Pine : l'ordre part au 1er
        //  tick de la bougie suivante — convention projet, cf. Fibo)
        //--------------------------------------------------------------
        double entry = i_tick.ask;

        // === FILTRE ANTI-RISQUE-NUL ===
        // (Pine : close - stopCandidate > syminfo.mintick)
        //------------------------------------------------
        double min_tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if (min_tick <= 0.0) min_tick = _Point;
        double risk = entry - sl;
        if (risk <= min_tick) return(false);

        // === SIGNAL D'ACHAT CONFIRMÉ → REMPLIR STRUCT_STRATEGY ===
        //----------------------------------------------------------
        ZeroMemory(o_datas);
        o_datas.Trend         = eT_Bull;
        o_datas.Entry         = entry;                            // entrée marché au prix courant
        o_datas.StopLoss      = sl;                               // plus bas des N bougies
        o_datas.TakeProfit    = entry + K_EMA50_TP_R * risk;      // TP = K_EMA50_TP_R R
        o_datas.IsMarketOrder = true;                             // ordre au marché

        LOG.INFO(m_Name + " : EMA50 ACHAT crossUp | Close=" +
                 DoubleToString(close1, _Digits) +
                 " | EMA="       + DoubleToString(ema1, _Digits) +
                 " | SL "        + IntegerToString((int)K_EMA50_SL_Bars) + " bars=" +
                                  DoubleToString(sl, _Digits) +
                 " | Ask="       + DoubleToString(entry, _Digits) +
                 " | TP="        + DoubleToString(o_datas.TakeProfit, _Digits) +
                 " | R="         + DoubleToString(K_EMA50_TP_R, 2),
                 __FUNCTION__);

        return(true);
    }

    //+--------------------------------------------------------+
    //| GetNamePublic                                          |
    //+--------------------------------------------------------+
    string GetNamePublic(void) { return(m_Name); }

};  // fin de la classe CScannerEma50
