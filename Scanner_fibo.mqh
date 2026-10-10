//+------------------------------------------------------------------+
//|                                                                  |
//| Scanner_fibo.mqh — StrategFiboScanner SOLO (38.2% / 3R)          |
//|                                                                  |
//| Adaptation du script Pine "FIBO SCANNER SOLO | XAUUSD H1"      |
//| dans l'architecture parallèle multi-scanners de Koenigin.        |
//|                                                                  |
//| - Classe CONCRETE CScannerFibo (pas d'héritage, pas de virtual) |
//| - Copie du template Scanner.mqh + logique Fibo spécifique       |
//| - Bull uniquement (achats)                                       |
//| - Détection des pivots : 2 bougies de chaque côté               |
//| - Tendance : HH + HL sur les 2 derniers pivots                  |
//| - Entrée : prix touche 38.2% Fibo ET clôture au-dessus          |
//| - SL = swing low (origine du mouvement)                          |
//| - TP = entry + 3R  (basé sur ask réel d'exécution)              |
//| - 1 trade max par swing (m_UsedLevel)                            |
//| - 1 trade max simultané (HasPositionForSymbol)                  |
//| - Entrée au marché (IsMarketOrder = true) à la clôture          |
//| - Pas de break-even, pas de trailing (fidélité Pine)            |
//|                                                                  |
//| === FIXES POST-REVIEW CHATGPT ===                                |
//| - #1 : off-by-one sur bougie de confirmation (m_DirectionSetBar- |
//|        Time empêche l'entrée sur la même bougie que la détection)|
//| - #3 : Detect() split en UpdateState() (toujours appelé) +      |
//|        GetSignal() (seulement si entrée autorisée)              |
//| - #5 : OnOrderCancelled no-op (Fibo = market orders, pas de     |
//|        pending à annuler)                                        |
//| - #6 : Verrou journalier basé sur datetime (pas dt.day)         |
//|                                                                  |
//| Le scanner ne fait AUCUN appel direct à BROKER, MONEY ou         |
//| DATAS. Il remplit STRUCT_STRATEGY et CStrategy fait le reste.    |
//|                                                                  |
//+------------------------------------------------------------------+


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////
//                                                      //
//                 I N C L U D E S                      //
//                                                      //
//////////////////////////////////////////////////////////
#include <OPR_Bot/Type.mqh>
#include <OPR_Bot/Log.mqh>
#include <OPR_Bot/Tools.mqh>


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CScannerFibo
{
//==================================
//--- PRIVATE
//==================================
private:
    // Identité du scanner
    //---------------------
    string          m_Name;             // Nom logique ("FiboScanner")
    ENUM_TIMEFRAMES m_TF;               // Timeframe de travail (K_Fibo_TF)

    // Verrouillage solo journalier (optionnel, contrôlé par Strategy via K_One_Trade_Per_Day)
    //-----------------------------------------------------------------------------------------
    datetime        m_DayStart;         // Début du jour courant (date complète, fix #6)
    bool            m_PositionOpened;   // Flag position ouverte aujourd'hui

    // ✅ ÉTAT DE LA DÉTECTION FIBO
    //------------------------------
    // Pivots successifs (les 2 derniers de chaque côté)
    double          m_LastHigh;
    double          m_PreviousHigh;
    datetime        m_HighTime;
    double          m_LastLow;
    double          m_PreviousLow;
    datetime        m_LowTime;

    // Swing ancré (mouvement haussier actif)
    double          m_Hi;                       // Sommet du swing
    double          m_Lo;                       // Plancher du swing (origine = SL)
    datetime        m_AnchorTime;
    int             m_Direction;                // 1 = bull, 0 = invalide/attente
    bool            m_UsedLevel;                // Empêche 2 entrées sur le même swing
    datetime        m_LastProcessedBarTime;     // Anti-rejeu de la même bougie
    datetime        m_DirectionSetBarTime;      // FIX #1 : bar où m_Direction a été mis à 1

    // Helpers internes
    //-----------------
    double   CheckPivotHigh(const int i_idx);
    double   CheckPivotLow (const int i_idx);

//==================================
//--- PROTECTED (helpers partagés avec le template)
//==================================
protected:

    //+--------------------------------------------------------+
    //| GetName / GetTF                                         |
    //+--------------------------------------------------------+
    string          GetName(void)   { return(m_Name); }
    ENUM_TIMEFRAMES GetTF(void)     { return(m_TF);    }

    //+--------------------------------------------------------+
    //| IsPositionOpenedToday                                  |
    //| Verrouillage "solo journalier" : 1 trade par scanner     |
    //| et par jour. Reset automatique à minuit.                |
    //|                                                          |
    //| FIX #6 : utilise m_DayStart (datetime complet) et non   |
    //| dt.day (1-31) qui confond octobre/novembre si même jour |
    //| du mois.                                                 |
    //|                                                          |
    //| Filtre par :                                             |
    //|   - Symbol() courant                                     |
    //|   - Magic = K_Magic + I_Robot_ID                         |
    //|   - DEAL_COMMENT / ORDER_COMMENT / POSITION_COMMENT       |
    //|     contient m_Name (préfixe posé par Broker.SendOrder)  |
    //|                                                          |
    //| Note : cette méthode n'est appelée par Strategy QUE si   |
    //| K_One_Trade_Per_Day = true. Sinon, le verrou quotidien    |
    //| est contourné (fidélité Pine — le Pine n'a pas de verrou  |
    //| quotidien).                                              |
    //+--------------------------------------------------------+
    bool IsPositionOpenedToday(const MqlTick &i_tick)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        datetime day_start;
        int      l_Deals;

        // Calcul du début de journée (date complète)
        //-------------------------------------------
        day_start = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");

        // Reset à minuit (fix #6 : comparaison datetime, pas dt.day)
        //-----------------------------------------------------------
        if (day_start != m_DayStart)
        {
            m_DayStart        = day_start;
            m_PositionOpened = false;
            LOG.INFO(m_Name + " : Nouveau jour (" + TimeToString(day_start, TIME_DATE) +
                     ") - Verrouillage réinitialisé", __FUNCTION__);
        }

        if (m_PositionOpened) return(true);

        // Détection via historique du jour (deal d'entrée)
        //-------------------------------------------------
        if (!HistorySelect(day_start, TimeCurrent())) return(false);
        l_Deals = HistoryDealsTotal();
        for (int i = l_Deals - 1; i >= 0; i--)
        {
            ulong l_Ticket = HistoryDealGetTicket(i);

            if (HistoryDealGetString (l_Ticket, DEAL_SYMBOL) != Symbol())               continue;
            if (HistoryDealGetInteger(l_Ticket, DEAL_MAGIC) != (K_Magic + I_Robot_ID))   continue;
            if (HistoryDealGetInteger(l_Ticket, DEAL_ENTRY)  != DEAL_ENTRY_IN)           continue;

            string l_comment = HistoryDealGetString(l_Ticket, DEAL_COMMENT);
            if (StringFind(l_comment, m_Name) < 0) continue;

            m_PositionOpened = true;
            return(true);
        }

        // Détection via ordres pending (BUY_STOP/SELL_STOP pas encore déclenchés)
        //-----------------------------------------------------------------------
        for (int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = OrderGetTicket(i);

            if (OrderGetString (l_Ticket, ORDER_SYMBOL) != Symbol())              continue;
            if (OrderGetInteger(l_Ticket, ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

            string l_comment = OrderGetString(l_Ticket, ORDER_COMMENT);
            if (StringFind(l_comment, m_Name) < 0) continue;

            double entry = OrderGetDouble(l_Ticket, ORDER_PRICE_OPEN);
            long   type  = OrderGetInteger(l_Ticket, ORDER_TYPE);

            if (type == ORDER_TYPE_BUY_STOP  && i_tick.ask >= entry)
            {
                m_PositionOpened = true;
                return(true);
            }
            if (type == ORDER_TYPE_SELL_STOP && i_tick.bid <= entry)
            {
                m_PositionOpened = true;
                return(true);
            }
        }

        // Détection via positions ouvertes actuellement
        //-----------------------------------------------
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = PositionGetTicket(i);

            if (PositionGetString (POSITION_SYMBOL) != Symbol())              continue;
            if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

            string l_comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(l_comment, m_Name) < 0) continue;

            m_PositionOpened = true;
            return(true);
        }

        return(false);
    }

    //+--------------------------------------------------------+
    //| HasPositionForSymbol                                   |
    //| Une position OUVERTE existe-t-elle pour CE scanner ?     |
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
    //| HasPendingOrderForSymbol                                |
    //| Un ordre PENDING existe-t-il pour CE scanner ?          |
    //+--------------------------------------------------------+
    bool HasPendingOrderForSymbol(void)
    {
        for (int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = OrderGetTicket(i);
            if (OrderGetString (l_Ticket, ORDER_SYMBOL) != Symbol())              continue;
            if (OrderGetInteger(l_Ticket, ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

            string l_comment = OrderGetString(l_Ticket, ORDER_COMMENT);
            if (StringFind(l_comment, m_Name) < 0) continue;

            return(true);
        }
        return(false);
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
        m_Name           = i_name;
        m_TF             = i_tf;
        m_DayStart       = 0;
        m_PositionOpened = false;

        // État Fibo
        //----------
        m_LastHigh             = 0.0;
        m_PreviousHigh         = 0.0;
        m_HighTime             = 0;
        m_LastLow              = 0.0;
        m_PreviousLow          = 0.0;
        m_LowTime              = 0;
        m_Hi                   = 0.0;
        m_Lo                   = 0.0;
        m_AnchorTime           = 0;
        m_Direction            = 0;
        m_UsedLevel            = false;
        m_LastProcessedBarTime = 0;
        m_DirectionSetBarTime  = 0;        // FIX #1

        LOG.INFO(m_Name + " : Scanner FIBO SCANNER SOLO initialisé (TF=" +
                 PeriodToString(m_TF) + ", PivotBars=" + IntegerToString((int)K_PivotBars) +
                 ", Retracement=" + DoubleToString(K_Fibo_Retracement, 3) +
                 ", TP_R=" + DoubleToString(K_Fibo_TP_R, 2) + ")", __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| End                                                     |
    //+--------------------------------------------------------+
    void End(void) { }

    //+--------------------------------------------------------+
    //| UpdateState   (FIX #3 : split de Detect)                |
    //|--------------------------------------------------------|
    //| Met à jour l'état interne du scanner :                  |
    //|   - Détection des pivots (haut et bas)                  |
    //|   - Calcul de la tendance (bullTrend / bearTrend)        |
    //|   - Ancrage d'un nouveau swing haussier si conditions   |
    //|   - Invalidation du swing si low casse origine ou bear  |
    //|                                                          |
    //| IMPORTANT : cette méthode NE DOIT PAS émettre de        |
    //| signal. Elle met juste à jour l'état du scanner pour     |
    //| que GetSignal() puisse décider ensuite.                 |
    //|                                                          |
    //| Doit être appelée à chaque NewCandle, même si une        |
    //| position est déjà ouverte (sinon l'état se fige —       |
    //| c'était le bug #3 avant le split).                      |
    //+--------------------------------------------------------+
    void UpdateState(const MqlTick &i_tick)
    {
        // === DÉTECTION DES PIVOTS ===
        //-----------------------------
        // La bougie qui vient de clôturer est à shift=1.
        // Un pivot confirmé avec K_PivotBars barres de chaque côté
        // est un pivot situé à shift = K_PivotBars + 1.
        int pivot_idx = (int)K_PivotBars + 1;

        // Heure de la dernière bougie clôturée (anti-rejeu)
        datetime last_closed_time = iTime(Symbol(), m_TF, 1);
        if (last_closed_time == 0)
        {
            LOG.WARNING(m_Name + " : iTime indisponible", __FUNCTION__);
            return;
        }

        // Anti-rejeu : ne pas retraiter la même bougie
        if (m_LastProcessedBarTime == last_closed_time)
        {
            return;
        }
        m_LastProcessedBarTime = last_closed_time;

        // Vérifier pivot haut potentiel
        //------------------------------
        double new_pivot_high = CheckPivotHigh(pivot_idx);
        if (new_pivot_high > 0.0)
        {
            m_PreviousHigh = m_LastHigh;
            m_LastHigh     = new_pivot_high;
            m_HighTime     = iTime(Symbol(), m_TF, pivot_idx);
            LOG.INFO(m_Name + " : Nouveau pivot haut : " +
                     DoubleToString(new_pivot_high, _Digits) + " @ " +
                     TimeToString(m_HighTime, TIME_DATE|TIME_MINUTES), __FUNCTION__);
        }

        // Vérifier pivot bas potentiel
        //-----------------------------
        double new_pivot_low = CheckPivotLow(pivot_idx);
        if (new_pivot_low > 0.0)
        {
            m_PreviousLow = m_LastLow;
            m_LastLow     = new_pivot_low;
            m_LowTime     = iTime(Symbol(), m_TF, pivot_idx);
            LOG.INFO(m_Name + " : Nouveau pivot bas : " +
                     DoubleToString(new_pivot_low, _Digits) + " @ " +
                     TimeToString(m_LowTime, TIME_DATE|TIME_MINUTES), __FUNCTION__);
        }

        // === CALCUL DE LA TENDANCE ===
        //------------------------------
        bool have_pivots = (m_LastHigh > 0.0 && m_PreviousHigh > 0.0 &&
                            m_LastLow  > 0.0 && m_PreviousLow  > 0.0);
        bool bull_trend = have_pivots && (m_LastHigh > m_PreviousHigh) && (m_LastLow > m_PreviousLow);
        bool bear_trend = have_pivots && (m_LastHigh < m_PreviousHigh) && (m_LastLow < m_PreviousLow);

        // === ANCRAGE D'UN NOUVEAU MOUVEMENT HAUSSIER ===
        //------------------------------------------------
        if (new_pivot_high > 0.0 && bull_trend && m_LowTime < m_HighTime)
        {
            m_Hi                  = m_LastHigh;
            m_Lo                  = m_LastLow;
            m_AnchorTime         = m_LowTime;
            m_Direction          = 1;
            m_UsedLevel          = false;
            m_DirectionSetBarTime = m_LastProcessedBarTime;  // FIX #1
            LOG.INFO(m_Name + " : Swing haussier ancré | Hi=" +
                     DoubleToString(m_Hi, _Digits) + " | Lo=" +
                     DoubleToString(m_Lo, _Digits) + " | knownBar=" +
                     TimeToString(m_DirectionSetBarTime, TIME_DATE|TIME_MINUTES), __FUNCTION__);
        }

        // === INVALIDATION DU MOUVEMENT ===
        //-----------------------------------
        if (m_Direction == 1)
        {
            double recent_low = iLow(Symbol(), m_TF, 1);
            if (recent_low <= m_Lo || bear_trend)
            {
                LOG.INFO(m_Name + " : Swing haussier invalidé (low=" +
                         DoubleToString(recent_low, _Digits) + " vs Lo=" +
                         DoubleToString(m_Lo, _Digits) + " | bear=" +
                         (bear_trend ? "oui" : "non") + ")", __FUNCTION__);
                m_Direction = 0;
            }
        }
    }

    //+--------------------------------------------------------+
    //| GetSignal   (FIX #3 : split de Detect)                  |
    //|--------------------------------------------------------|
    //| Vérifie si les conditions d'entrée sont remplies :      |
    //|   - m_Direction == 1 (swing haussier actif)             |
    //|   - !m_UsedLevel (pas encore entré sur ce swing)        |
    //|   - FIX #1 : bar courante > m_DirectionSetBarTime       |
    //|     (n'entre pas sur la bougie qui a confirmé le pivot)|
    //|   - span > mintick                                      |
    //|   - touch + close sur la dernière bougie clôturée      |
    //|                                                          |
    //| INPUT:                                                   |
    //|   i_tick : tick courant (pour ask si entrée marché)     |
    //| OUTPUT:                                                  |
    //|   o_datas : STRUCT_STRATEGY rempli si retourne TRUE     |
    //|   Retour : TRUE si signal émis, FALSE sinon             |
    //|                                                          |
    //| IMPORTANT : ne JAMAIS appeler BROKER/MONEY/DATAS ici.   |
    //| CStrategy fait le relais après réception du signal.     |
    //+--------------------------------------------------------+
    bool GetSignal(const MqlTick &i_tick, STRUCT_STRATEGY &o_datas)
    {
        // Pas de mouvement actif ou niveau déjà utilisé
        //------------------------------------------------
        if (m_Direction != 1 || m_UsedLevel) return(false);

        // FIX #1 : interdiction d'entrer sur la bougie qui a confirmé le pivot
        // (équivalent du ready = bar_index > knownBar du Pine)
        //---------------------------------------------------------------------
        if (m_LastProcessedBarTime <= m_DirectionSetBarTime)
        {
            return(false);
        }

        // Vérification que les données d'ancre sont valides
        //--------------------------------------------------
        double span = m_Hi - m_Lo;
        double min_tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if (min_tick <= 0.0) min_tick = _Point;
        if (span <= min_tick) return(false);

        // === NIVEAU D'ENTRÉE FIBO 38.2% ===
        //------------------------------------
        double entry_level = m_Hi - K_Fibo_Retracement * span;

        // === VÉRIFICATION TOUCH + CLOSE ===
        //-----------------------------------
        // Sur la bougie qui vient de clôturer (shift=1) :
        //   - touch : Low[1] <= entry_level <= High[1]
        //   - close : Close[1] > entry_level
        double last_low   = iLow  (Symbol(), m_TF, 1);
        double last_high  = iHigh (Symbol(), m_TF, 1);
        double last_close = iClose(Symbol(), m_TF, 1);

        bool touch        = (last_low <= entry_level) && (last_high >= entry_level);
        bool close_above  = (last_close > entry_level);

        if (!touch || !close_above) return(false);

        // === SIGNAL D'ACHAT CONFIRMÉ → REMPLIR STRUCT_STRATEGY ===
        //----------------------------------------------------------
        // Option B (choix utilisateur) : entrée = ask réel d'exécution
        // Lot/TP calculés sur cette base (cohérent avec le réel broker).
        ZeroMemory(o_datas);
        o_datas.Trend        = eT_Bull;
        o_datas.Entry        = i_tick.ask;                              // entrée marché au prix courant
        o_datas.StopLoss     = m_Lo;                                    // SL = origine (swing low)
        o_datas.TakeProfit   = o_datas.Entry + K_Fibo_TP_R * (o_datas.Entry - o_datas.StopLoss);
        o_datas.IsMarketOrder = true;                                  // ordre au marché

        // Verrouillage du niveau (1 trade max par swing)
        m_UsedLevel = true;

        LOG.INFO(m_Name + " : FIBO ACHAT 38.2% | Swing H=" +
                 DoubleToString(m_Hi, _Digits) +
                 " | Swing L="   + DoubleToString(m_Lo, _Digits) +
                 " | Entry Lvl=" + DoubleToString(entry_level, _Digits) +
                 " | Ask="       + DoubleToString(i_tick.ask, _Digits) +
                 " | SL="        + DoubleToString(o_datas.StopLoss, _Digits) +
                 " | TP="        + DoubleToString(o_datas.TakeProfit, _Digits) +
                 " | R="         + DoubleToString(K_Fibo_TP_R, 2),
                 __FUNCTION__);

        return(true);
    }

    //+--------------------------------------------------------+
    //| OnTick                                                  |
    //| Appelée par CStrategy::ManagePositions() à chaque tick.  |
    //| Fidélité Pine : pas de BE, pas de trailing. La sortie    |
    //| se fait uniquement au SL/TP natif posé à l'entrée.        |
    //+--------------------------------------------------------+
    void OnTick(const MqlTick &i_tick) { }

    //+--------------------------------------------------------+
    //| OnOrderCancelled   (FIX #5 : no-op)                     |
    //|--------------------------------------------------------|
    //| Fibo entre exclusivement au marché (IsMarketOrder=true) |
    //| → il n'y a JAMAIS d'ordre pending à annuler pour ce    |
    //| scanner. Resetter usedLevel ici serait conceptuellement|
    //| faux (le swing reste utilisé, la position est ouverte).|
    //|                                                          |
    //| Donc : no-op pur. Le corps est vide intentionnellement. |
    //+--------------------------------------------------------+
    void OnOrderCancelled(void) { }

    //+--------------------------------------------------------+
    //| RollbackSignal   (FIX ChatGPT : rollback usedLevel)      |
    //|--------------------------------------------------------|
    //| Appelée par CStrategy quand ExecuteSignal() a échoué :  |
    //|   - lot invalide (CalculateLotSize a retourné 0)         |
    //|   - OrderCheck rejeté                                     |
    //|   - OrderSend rejeté                                      |
    //|                                                          |
    //| Reset m_UsedLevel = false pour que le scanner reste       |
    //| éligible à émettre un nouveau signal sur la prochaine     |
    //| bougie (si les conditions touch+close sont encore remplies).|
    //|                                                          |
    //| Sans ce rollback, un swing serait définitivement "consommé"|
    //| même si l'ordre a échoué → plus aucune tentative possible |
    //| sur ce swing, ce qui est mauvais pour un EA réel.        |
    //+--------------------------------------------------------+
    void RollbackSignal(void)
    {
        if (m_UsedLevel)
        {
            m_UsedLevel = false;
            LOG.WARNING(m_Name + " : usedLevel rollback — ordre échoué, scanner redevient éligible", __FUNCTION__);
        }
    }

    //+--------------------------------------------------------+
    //| GetNamePublic                                          |
    //+--------------------------------------------------------+
    string GetNamePublic(void) { return(m_Name); }

    //+--------------------------------------------------------+
    //| HasActiveSignal                                          |
    //+--------------------------------------------------------+
    bool HasActiveSignal(void)
    {
        return(m_Direction == 1 && m_UsedLevel);
    }

};  // fin de la classe CScannerFibo


//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E   (helpers)            //
//                                                      //
//////////////////////////////////////////////////////////

//+------------------------------------------------------------------+
//| CheckPivotHigh                                                   |
//+------------------------------------------------------------------+
double CScannerFibo::CheckPivotHigh(const int i_idx)
{
    int    pivot_bars = (int)K_PivotBars;
    double val        = iHigh(Symbol(), m_TF, i_idx);
    if (val <= 0.0) return(0.0);

    for (int i = i_idx - pivot_bars; i <= i_idx + pivot_bars; i++)
    {
        if (i < 0) return(0.0);
        double v = iHigh(Symbol(), m_TF, i);
        if (v <= 0.0) return(0.0);
        if (i == i_idx) continue;
        if (v >= val) return(0.0);
    }
    return(val);
}

//+------------------------------------------------------------------+
//| CheckPivotLow                                                    |
//+------------------------------------------------------------------+
double CScannerFibo::CheckPivotLow(const int i_idx)
{
    int    pivot_bars = (int)K_PivotBars;
    double val        = iLow(Symbol(), m_TF, i_idx);
    if (val <= 0.0) return(0.0);

    for (int i = i_idx - pivot_bars; i <= i_idx + pivot_bars; i++)
    {
        if (i < 0) return(0.0);
        double v = iLow(Symbol(), m_TF, i);
        if (v <= 0.0) return(0.0);
        if (i == i_idx) continue;
        if (v <= val) return(0.0);
    }
    return(val);
}
