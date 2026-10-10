//+------------------------------------------------------------------+
//|                                                                  |
//| Strategy.mqh — LIAISON (Koenigin architecture)                   |
//|                                                                  |
//| Strategy n'est plus une stratégie à part entière mais une       |
//| LIAISON :                                                        |
//|                                                                  |
//|   - Détient les ressources partagées (CDatas DATAS)              |
//|   - Détient un ou plusieurs membres scanner EXPLICITES          |
//|     (ici : CScannerFibo m_FiboScanner)                           |
//|   - Detection() appelle chaque scanner via TryXxx()              |
//|   - ManagePositions() délègue à scanner.OnTick()                 |
//|   - SetTicket/GetPositionNb/DeleteDetection/CloseOfPositions    |
//|     → délèguent à DATAS partagé                                  |
//|                                                                  |
//| La logique de marché (pivots, EMA, OPR, Fibo, …) est dans les   |
//| scanners. Strategy ne sait PAS ce que fait un scanner, il       |
//| appelle juste Detect() et relaie au broker.                      |
//|                                                                  |
//| Ajouter un scanner = créer Scanner_xxx.mqh + ajouter un membre  |
//| + ajouter une méthode TryXxx() + l'appeler dans Detection().    |
//| On ne touche PAS aux autres scanners.                            |
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
#include <OPR_Bot/Tools.mqh>
#include <OPR_Bot/Log.mqh>
#include <OPR_Bot/Alert.mqh>
#include <OPR_Bot/Parameters.mqh>
#include <OPR_Bot/Context.mqh>
#include <OPR_Bot/Money.mqh>
#include <OPR_Bot/Visu.mqh>
#include <OPR_Bot/Monitoring.mqh>
#include <OPR_Bot/Broker.mqh>
#include <OPR_Bot/Datas.mqh>

// === Scanner(s) enregistrés ===
// Chaque scanner est une classe concrete (pas d'héritage).
// On include son fichier pour pouvoir le déclarer en membre.
#include <OPR_Bot/Scanner_fibo.mqh>
// Plus tard :
// #include <OPR_Bot/Scanner_opr.mqh>


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CStrategy
{
//==================================
//--- PRIVATE
//==================================
private:
    // Données de la stratégie (partagées par tous les scanners)
    //-----------------------------------------------------------
    CDatas        DATAS;

    // ✅ SCANNERS EXPLICITES (pas d'héritage, pas de tableau polymorphique)
    // Chaque scanner a son propre membre typé. On ajoute un membre
    // quand on branche un nouveau scanner.
    //-----------------------------------------------------------------
    CScannerFibo  m_FiboScanner;
    // Plus tard : CScannerOPR m_OPRScanner;

    // État interne
    //------------
    bool            m_InitOk;

    // ✅ FIX ChatGPT #2 : scheduler indépendant du chart timeframe
    // Strategy garde en mémoire le timestamp de la dernière bougie
    // traitée sur K_Fibo_TF (pas PERIOD_CURRENT). Comme ça, le
    // scanner H1 est appelé à chaque nouvelle bougie H1 même si
    // le chart est M15 ou H4.
    //----------------------------------------------------------------
    datetime        m_LastFiboBarTime;

    // Helpers d'exécution (communs à tous les scanners)
    //---------------------------------------------------
    bool ExecuteSignal(const string i_scanner_name, STRUCT_STRATEGY &io_datas);  // retourne TRUE si ordre envoyé avec succès
    void TryFibo(const MqlTick &i_tick);
    // Plus tard : void TryOPR(const MqlTick &i_tick);

//==================================
//--- PUBLIC
//==================================
public:

    //+--------------------------------------------------------+
    //| Config                                                  |
    //| Initialise DATAS (shared) + chaque scanner enregistré.   |
    //+--------------------------------------------------------+
    bool Config(const string            i_strategy_name,
                const ENUM_TIMEFRAMES   i_period,
                const string            i_folder)
    {
        m_InitOk = false;

        // ✅ FIX ChatGPT #2 : init du scheduler indépendant du chart TF
        //---------------------------------------------------------------
        m_LastFiboBarTime = 0;

        // 1. Configure les données partagées
        //-------------------------------------
        if (!DATAS.Config(i_strategy_name, i_period, i_folder)) return(false);

        // 2. Configure chaque scanner enregistré
        //-----------------------------------------
        // Le nom passé au scanner sera le prefix du comment de l'ordre
        // posé par Broker → permet le filtrage par scanner dans
        // IsPositionOpenedToday.
        if (!m_FiboScanner.Config("FiboScanner", K_Fibo_TF))
        {
            LOG.ERROR(DATAS.GetStrategyName() + "Initialisation scanner Fibo échouée", __FUNCTION__);
            return(false);
        }

        m_InitOk = true;
        LOG.INFO(DATAS.GetStrategyName() + "Stratégie (liaison) initialisée avec succès", __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| ConfigOk / End                                          |
    //+--------------------------------------------------------+
    bool ConfigOk(void) { return(m_InitOk);  }

    void End(void)
    {
        // Libère chaque scanner
        //----------------------
        m_FiboScanner.End();
        // Plus tard : m_OPRScanner.End();

        // Flush les données
        //-------------------
        DATAS.End();
    }

    //+--------------------------------------------------------+
    //| SetTicket                                               |
    //| Appelée par Broker quand un ordre est rempli, pour         |
    //| lier le ticket à la détection dans DATAS.                 |
    //+--------------------------------------------------------+
    void SetTicket(const int i_detection, const int i_Ticket)
    {
        DATAS.SetTicket(i_detection, i_Ticket);
    }

    //+--------------------------------------------------------+
    //| GetPositionNb / DeleteDetection / CloseOfPositions    |
    //| Délèguent à DATAS partagé.                                |
    //+--------------------------------------------------------+
    int GetPositionNb(void)               { return(DATAS.GetPositionNb()); }
    void DeleteDetection(void)            { DATAS.DeleteDetection(); }
    void CloseOfPositions(void)           { DATAS.CloseOfPositions(); }

    //+--------------------------------------------------------+
    //| Detection                                               |
    //| Appelée par Koenigin::OnTick() à CHAQUE TICK.           |
    //|                                                          |
    //| ✅ FIX ChatGPT #2 : Strategy décide elle-même s'il y a   |
    //|    une nouvelle bougie sur K_Fibo_TF (pas PERIOD_CURRENT)|
    //|    → marche quel que soit le TF du chart                 |
    //|                                                          |
    //| ✅ FIX ChatGPT #1 : UpdateState est appelé AVANT les      |
    //|    filtres NEWS/hour/day. L'état du scanner évolue même  |
    //|    pendant les périodes filtrées (comme le Pine qui      |
    //|    exécute toujours sur barstate.isconfirmed).           |
    //|                                                          |
    //| Flux :                                                   |
    //|   1. Lecture du tick                                     |
    //|   2. Anti-rejeu sur K_Fibo_TF (nouvelle bougie ?)        |
    //|   3. UpdateState() — TOUJOURS (maj pivots/swing)         |
    //|   4. Filtres d'EXÉCUTION (NEWS, heures, jours)          |
    //|   5. TryFibo() — verrous d'entrée + GetSignal            |
    //+--------------------------------------------------------+
    void Detection(void)
    {
        // Lit les dernières données du marché
        //------------------------------------
        MqlTick l_Tick;
        if (!SymbolInfoTick(Symbol(), l_Tick))
        {
            LOG.WARNING(DATAS.GetStrategyName() + "Lecture du tick impossible", __FUNCTION__);
            return;
        }

        // ✅ FIX ChatGPT #2 : anti-rejeu basé sur K_Fibo_TF (pas PERIOD_CURRENT)
        //-----------------------------------------------------------------------
        // Permet à l'EA de tourner sur un chart M15 ou H4 sans rater de
        // clôture H1. Strategy est appelée à chaque tick par Koenigin,
        // mais ne fait le travail qu'une fois par nouvelle bougie K_Fibo_TF.
        //-----------------------------------------------------------------------
        datetime current_fibo_bar = iTime(Symbol(), K_Fibo_TF, 0);
        if (current_fibo_bar == 0)
        {
            LOG.WARNING(DATAS.GetStrategyName() + "iTime(K_Fibo_TF) indisponible", __FUNCTION__);
            return;
        }
        if (current_fibo_bar == m_LastFiboBarTime)
        {
            return;  // pas de nouvelle bougie sur K_Fibo_TF → on attend
        }
        m_LastFiboBarTime = current_fibo_bar;

        // ✅ FIX ChatGPT #1 : UpdateState AVANT les filtres d'exécution
        // Le scanner analyse toujours les pivots/swing, même en zone NEWS
        // ou hors heures de trading. Le Pine fait pareil (barstate.isconfirmed
        // n'a pas de filtre de trading préalable).
        //----------------------------------------------------------------
        m_FiboScanner.UpdateState(l_Tick);
        // Plus tard : m_OPRScanner.UpdateState(l_Tick);

        // === FILTRES D'EXÉCUTION (n'affectent pas l'état du scanner) ===
        //----------------------------------------------------------------

        // Zone NEWS : on n'entre pas en nouveaux trades pendant la zone
        // de sécurité. On notifie les scanners qui ont des pendings
        // (pour qu'ils reset leur état). Fibo = market orders, donc
        // HasPendingOrderForSymbol est toujours false pour Fibo.
        //----------------------------------------------------------------
        if (!PARAM.OutsideSecurityZone())
        {
            if (m_FiboScanner.HasPendingOrderForSymbol())
            {
                LOG.INFO(DATAS.GetStrategyName() + "Zone NEWS - Annulation pendings + notification scanner Fibo", __FUNCTION__);
                m_FiboScanner.OnOrderCancelled();
            }
            // Plus tard : if (m_OPRScanner.HasPendingOrderForSymbol()) m_OPRScanner.OnOrderCancelled();
            return;
        }

        // Horaires de trading
        //--------------------
        if (!PARAM.HourOfTrading() || !PARAM.DayOfTrading())
        {
            return;
        }

        // === EXÉCUTION DES SCANNERS ===
        //-------------------------------
        TryFibo(l_Tick);
        // Plus tard : TryOPR(l_Tick);
    }

    //+--------------------------------------------------------+
    //| ManagePositions                                         |
    //| Appelée par Koenigin::OnTick() à chaque tick + OnTimer().  |
    //|                                                          |
    //| Flux :                                                   |
    //|   1. Lecture du tick                                     |
    //|   2. Filtre NEWS (annulation pendings)                  |
    //|   3. Pour chaque scanner : scanner.OnTick(tick)           |
    //|      (BE, trailing, invalidation — selon le scanner)     |
    //+--------------------------------------------------------+
    void ManagePositions(void)
    {
        // Lit le tick
        //------------
        MqlTick l_Tick;
        if (!SymbolInfoTick(Symbol(), l_Tick))
        {
            LOG.WARNING(DATAS.GetStrategyName() + "ManagePositions : lecture tick impossible", __FUNCTION__);
            return;
        }

        // Zone NEWS : annulation pendings + notification scanners
        //---------------------------------------------------------
        if (!PARAM.OutsideSecurityZone())
        {
            m_FiboScanner.OnOrderCancelled();
            // Plus tard : m_OPRScanner.OnOrderCancelled();
            return;
        }

        // Délègue la gestion à chaque scanner
        //-------------------------------------
        m_FiboScanner.OnTick(l_Tick);
        // Plus tard : m_OPRScanner.OnTick(l_Tick);
    }
};


//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////

//+------------------------------------------------------------------+
//| ExecuteSignal                                                    |
//| Helper commun à tous les TryXxx(). Prend le signal produit par    |
//| un scanner (déjà rempli dans io_datas), ajoute l'ID de détection, |
//| calcule le lot, persiste, envoie l'ordre au broker.               |
//|                                                                  |
//| ✅ FIX ChatGPT : retourne un bool pour que TryXxx puisse         |
//|    appeler RollbackSignal() en cas d'échec (usedLevel non        |
//|    commit si l'ordre n'est pas réellement parti).                |
//+------------------------------------------------------------------+
bool CStrategy::ExecuteSignal(const string i_scanner_name, STRUCT_STRATEGY &io_datas)
{
    // Alloue un nouvel ID de détection partagé
    //-----------------------------------------
    int l_NoDetection = DATAS.GetNewDetection();
    io_datas.No_detection = l_NoDetection;

    // Calcule le lot à partir de Entry et StopLoss
    //----------------------------------------------
    io_datas.Size = MONEY.CalculateLotSize(io_datas);
    if (io_datas.Size <= 0.0)
    {
        LOG.WARNING(i_scanner_name + " : Taille de lot invalide - signal abandonné", __FUNCTION__);
        return(false);  // échec → TryFibo appellera RollbackSignal
    }

    // Persiste la détection dans DATAS
    //---------------------------------
    DATAS.SetData(l_NoDetection, io_datas);

    // Log structuré
    //--------------
    string l_Header = LOG.InfosLogOperation(DATAS.GetStrategyName(), io_datas.No_detection, Symbol());
    LOG.INFO(l_Header + " : " + i_scanner_name +
             " | " + TrendToString(io_datas.Trend) +
             " | Taille = " + DoubleToString(io_datas.Size,       MONEY.GetDigitLot()) +
             " | Entry = "   + DoubleToString(io_datas.Entry,      Digits()) +
             " | SL = "      + DoubleToString(io_datas.StopLoss,   Digits()) +
             " | TP = "      + DoubleToString(io_datas.TakeProfit, Digits()) +
             " | "           + (io_datas.IsMarketOrder ? "MARCHÉ" : "STOP"),
             __FUNCTION__);

    // Envoie l'ordre au broker
    // Le scanner_name est posé dans le comment de l'ordre par Broker
    // (voir Broker.mqh : l_Request.comment = i_StrategyName + " X-TYPE")
    //-----------------------------------------------------------------
    if (!BROKER.SendOrder(DATAS.GetStrategyName(), io_datas))
    {
        LOG.ERROR(i_scanner_name + " : BROKER.SendOrder a échoué - signal rollback", __FUNCTION__);
        return(false);  // échec → TryFibo appellera RollbackSignal
    }

    return(true);  // succès
}

//+------------------------------------------------------------------+
//| TryFibo                                                           |
//| Orchestration du scanner Fibo :                                   |
//|   1. Verrous (solo journalier optionnel, position ouverte, pending)|
//|   2. GetSignal() — récupère un signal si conditions d'entrée remplies|
//|   3. Si signal → ExecuteSignal                                    |
//|                                                                  |
//| Note : UpdateState() est appelé par Detection() AVANT cette      |
//| méthode, donc l'état du scanner est déjà à jour.                  |
//+------------------------------------------------------------------+
void CStrategy::TryFibo(const MqlTick &i_tick)
{
    // VERROUS D'ENTRÉE
    //--------------------

    // Verrou solo journalier (optionnel, fix #4)
    // Le Pine n'a pas de verrou quotidien — seulement 1 trade par swing
    // et 1 trade simultané. K_One_Trade_Per_Day (défaut false) permet
    // d'activer cette règle supplémentaire si besoin.
    if (K_One_Trade_Per_Day && m_FiboScanner.IsPositionOpenedToday(i_tick))
    {
        return;
    }

    // Position déjà ouverte pour ce scanner ? (solo strict — Pine-fidèle)
    //--------------------------------------------------------------------
    if (m_FiboScanner.HasPositionForSymbol())
    {
        return;
    }

    // Ordre pending déjà posé pour ce scanner ?
    //------------------------------------------
    if (m_FiboScanner.HasPendingOrderForSymbol())
    {
        return;
    }

    // RÉCUPÉRATION DU SIGNAL (touch+close+off-by-one, etc.)
    //----------------------------------------------------------
    STRUCT_STRATEGY l_Datas;
    ZeroMemory(l_Datas);
    if (!m_FiboScanner.GetSignal(i_tick, l_Datas))
    {
        return;  // pas de signal
    }

    // EXÉCUTION (DATAS + MONEY + BROKER)
    //---------------------------------------
    // ✅ FIX ChatGPT : si ExecuteSignal échoue (lot=0, OrderCheck rejeté,
    // OrderSend rejeté), on rollback usedLevel pour que le scanner puisse
    // réessayer sur la prochaine bougie (si conditions encore remplies).
    if (!ExecuteSignal(m_FiboScanner.GetNamePublic(), l_Datas))
    {
        m_FiboScanner.RollbackSignal();
    }
}

// Plus tard :
// void CStrategy::TryOPR(const MqlTick &i_tick) { ... similaire avec m_OPRScanner ... }
