//+------------------------------------------------------------------+
//|                                                                  |
//| Scanner.mqh — classe CScanner (TEMPLATE DE BASE)                |
//|                                                                  |
//| Principe :                                                       |
//|   Pas d'héritage. Pas de méthode virtuelle.                     |
//|   Cette classe est un TEMPLATE que l'on copie et modifie        |
//|   pour chaque stratégie :                                       |
//|                                                                  |
//|     - Scanner_fibo.mqh   (class CScanner, logique Fibo 38.2%)   |
//|     - Scanner_opr.mqh    (class CScanner, logique ORB breakout) |
//|     - ...                                                        |
//|                                                                  |
//|   Chaque copie garde le MÊME nom de classe CScanner.           |
//|   On include UN seul Scanner_xxx.mqh à la fois. CStrategy     |
//|   a un seul membre CScanner.                                    |
//|                                                                  |
//|   (Pattern identique à Strategy.mqh / Strategy_cloture_         |
//|    fonctionnel.mqh qui sont des drop-in replacements.)         |
//|                                                                  |
//| Rôle du scanner :                                                |
//|   - Détecter un signal de trading (entry, SL, TP, sens)          |
//|   - Gérer son état interne (pivots, indicateurs, usedLevel, …)  |
//|   - Gérer ses positions ouvertes (BE, invalidation, …)           |
//|                                                                  |
//| Rôle de CStrategy (la liaison) :                                 |
//|   - Appeler scanner.Detect() à chaque NewCandle                 |
//|   - Appeler scanner.OnTick() à chaque tick                      |
//|   - Allouer l'ID de détection (DATAS)                            |
//|   - Calculer le lot (MONEY)                                      |
//|   - Envoyer l'ordre (BROKER)                                     |
//|   - Filtres globaux (NEWS, heures, jours)                        |
//|                                                                  |
//|   Le scanner ne fait AUCUN appel direct à BROKER, MONEY ou      |
//|   DATAS. Il communique avec CStrategy via STRUCT_STRATEGY.      |
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
class CScanner
{
//==================================
//--- PRIVATE
//==================================
private:
    // Identité du scanner
    //---------------------
    string          m_Name;             // Nom logique (ex: "FiboScanner")
    ENUM_TIMEFRAMES m_TF;               // Timeframe de travail

    // Verrouillage solo journalier
    //------------------------------
    int             m_LockedDay;        // Jour verrouillé
    bool            m_PositionOpened;  // Flag position ouverte aujourd'hui

//==================================
//--- PROTECTED (helpers réutilisables)
//==================================
protected:

    //+--------------------------------------------------------+
    //| GetName / GetTF                                         |
    //+--------------------------------------------------------+
    string          GetName(void)   { return(m_Name); }
    ENUM_TIMEFRAMES GetTF(void)     { return(m_TF);    }

    //+--------------------------------------------------------+
    //| IsPositionOpenedToday                                  |
    //| Verrouillage "solo" : une seule position par scanner     |
    //| et par jour. Reset automatique à minuit.                |
    //|                                                          |
    //| Filtre par :                                             |
    //|   - Symbol() courant                                     |
    //|   - Magic = K_Magic + I_Robot_ID                         |
    //|   - DEAL_COMMENT commence par m_Name                     |
    //|     (permet à plusieurs scanners de trader en parallèle  |
    //|      si Broker pose le comment avec le nom du scanner)   |
    //+--------------------------------------------------------+
    bool IsPositionOpenedToday(const MqlTick &i_tick)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        datetime day_start;
        int      l_Deals;

        // Reset à minuit
        //---------------
        if (dt.day != m_LockedDay)
        {
            m_LockedDay      = dt.day;
            m_PositionOpened = false;
        }

        if (m_PositionOpened) return(true);

        // Détection via historique du jour (deal d'entrée)
        //-------------------------------------------------
        day_start = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");

        if (!HistorySelect(day_start, TimeCurrent())) return(false);
        l_Deals = HistoryDealsTotal();
        for (int i = l_Deals - 1; i >= 0; i--)
        {
            ulong l_Ticket = HistoryDealGetTicket(i);

            if (HistoryDealGetString (l_Ticket, DEAL_SYMBOL) != Symbol())               continue;
            if (HistoryDealGetInteger(l_Ticket, DEAL_MAGIC) != (K_Magic + I_Robot_ID))   continue;
            if (HistoryDealGetInteger(l_Ticket, DEAL_ENTRY)  != DEAL_ENTRY_IN)           continue;

            // Filtre par commentaire (préfixe = nom du scanner)
            string l_comment = HistoryDealGetString(l_Ticket, DEAL_COMMENT);
            if (StringFind(l_comment, m_Name) < 0) continue;

            m_PositionOpened = true;
            return(true);
        }

        // Détection via ordres pending (pas encore déclenchés)
        //-----------------------------------------------------
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

        // Détection via positions ouvertes
        //---------------------------------
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
    //| Un ordre PENDING existe-t-il pour CE scanner ?           |
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
    //| Initialise l'identité et l'état du scanner.              |
    //|                                                          |
    //| ⚠️ Dans chaque Scanner_xxx.mqh, surcharger Config()     |
    //|    pour ajouter l'init des indicateurs/variables         |
    //|    spécifiques. ET APPELER CE CScanner::Config() en      |
    //|    premier (via le pattern "CScanner::Config(...)").     |
    //+--------------------------------------------------------+
    bool Config(const string i_name, const ENUM_TIMEFRAMES i_tf)
    {
        m_Name           = i_name;
        m_TF             = i_tf;
        m_LockedDay      = -1;
        m_PositionOpened = false;
        LOG.INFO("Scanner '" + m_Name + "' initialisé (TF=" + PeriodToString(m_TF) + ")", __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| End                                                     |
    //| Libération des ressources.                              |
    //| Implémentation par défaut : ne fait rien.               |
    //| Surcharger dans chaque scanner pour libérer les handles. |
    //+--------------------------------------------------------+
    void End(void) { }

    //+--------------------------------------------------------+
    //| Detect                                                  |
    //| ⚠️ POINT D'EXTENSION CENTRAL — à modifier dans chaque    |
    //|    copie Scanner_xxx.mqh selon la stratégie.             |
    //|                                                          |
    //| Appelée par CStrategy::Detection() à chaque NewCandle.    |
    //|                                                          |
    //| INPUT:                                                   |
    //|   i_tick : tick courant (pour ask/bid si entrée marché)  |
    //| OUTPUT:                                                  |
    //|   o_datas : STRUCT_STRATEGY à remplir (Trend, Entry,     |
    //|             StopLoss, TakeProfit, IsMarketOrder)         |
    //|   Retour : TRUE si un nouveau signal est émis,          |
    //|            FALSE sinon                                   |
    //|                                                          |
    //| Contrat :                                                |
    //|   - Ne PAS appeler BROKER.SendOrder (rôle de CStrategy)  |
    //|   - Ne PAS appeler MONEY.CalculateLotSize                |
    //|   - Ne PAS appeler DATAS.SetData / GetNewDetection       |
    //|   - Gérer son propre usedLevel pour ne pas réémettre     |
    //|     le même signal 2 fois sur le même setup             |
    //|   - Remplir o_datas.IsMarketOrder selon le besoin        |
    //|     (TRUE = ordre au marché, FALSE = ordre stop/limit)   |
    //+--------------------------------------------------------+
    bool Detect(const MqlTick &i_tick, STRUCT_STRATEGY &o_datas)
    {
        // === IMPLÉMENTATION PAR DÉFAUT (à remplacer dans chaque copie) ===
        // Cette méthode ne fait rien dans le template de base.
        // Surcharge-la dans Scanner_fibo.mqh, Scanner_opr.mqh, etc.
        return(false);
    }

    //+--------------------------------------------------------+
    //| OnTick                                                  |
    //| Appelée par CStrategy::ManagePositions() à chaque tick.  |
    //| Implémentation par défaut : ne fait rien.                |
    //| Surcharger pour :                                       |
    //|   - break-even spécifique au scanner                     |
    //|   - trailing stop                                        |
    //|   - invalidation de signal (ex: low casse swing low)     |
    //+--------------------------------------------------------+
    void OnTick(const MqlTick &i_tick) { }

    //+--------------------------------------------------------+
    //| OnOrderCancelled                                        |
    //| Notifiée par CStrategy quand un ordre pending de ce       |
    //| scanner a été annulé (zone NEWS, divergence, etc.).      |
    //| Le scanner peut réinitialiser son état interne           |
    //| (usedLevel = false par ex.) pour redevenir éligible.      |
    //+--------------------------------------------------------+
    void OnOrderCancelled(void) { }

    //+--------------------------------------------------------+
    //| GetNamePublic                                          |
    //| Accès public au nom logique du scanner (pour CStrategy   |
    //| qui le passe à BROKER.SendOrder(strategy_name, ...) →    |
    //| le comment de l'ordre).                                 |
    //+--------------------------------------------------------+
    string GetNamePublic(void) { return(m_Name); }

    //+--------------------------------------------------------+
    //| HasActiveSignal                                          |
    //| Indique si le scanner a un signal "en vol" (ordre         |
    //| pending non exécuté, ou swing utilisé en attente de      |
    //| résolution). Utilisé par CStrategy pour le mode solo      |
    //| strict (ne pas empiler les signaux).                     |
    //| Implémentation par défaut : false.                       |
    //+--------------------------------------------------------+
    bool HasActiveSignal(void) { return(false); }
};
