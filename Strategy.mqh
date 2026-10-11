//+------------------------------------------------------------------+
//|                                                                  |
//| Strategy.mqh — LIAISON (Koenigin architecture)                   |
//|                                                                  |
//| Strategy n'est plus une stratégie à part entière mais une       |
//| LIAISON :                                                        |
//|                                                                  |
//|   - Détient les ressources partagées (CDatas DATAS)              |
//|   - Détient un ou plusieurs membres scanner EXPLICITES          |
//|     (ici : CScannerEma50 m_Ema50Scanner)                       |
//|   - Detection() appelle chaque scanner via TryXxx()              |
//|   - ManagePositions() délègue à scanner.OnTick()                 |
//|   - SetTicket/GetPositionNb/DeleteDetection/CloseOfPositions    |
//|     → délèguent à DATAS partagé                                  |
//|                                                                  |
//| La logique de marché (pivots, EMA, OPR, …) est dans les         |
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
#include <Koenigin/Type.mqh>
#include <Koenigin/Tools.mqh>
#include <Koenigin/Log.mqh>
#include <Koenigin/Alert.mqh>
#include <Koenigin/Parameters.mqh>
#include <Koenigin/Context.mqh>
#include <Koenigin/Money.mqh>
#include <Koenigin/Visu.mqh>
#include <Koenigin/Monitoring.mqh>
#include <Koenigin/Broker.mqh>
#include <Koenigin/Datas.mqh>

// === Scanner(s) enregistrés ===
// Chaque scanner est une classe concrete (pas d'héritage).
// On include son fichier pour pouvoir le déclarer en membre.
// Le scanner apporte SES inputs dans SON fichier (auto-contenu).
#include <Koenigin/Scanner_ema50.mqh>
// Pour en brancher un autre :
// #include <Koenigin/Scanner_xxx.mqh>


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
    CScannerEma50 m_Ema50Scanner;

    // État interne
    //------------
    bool            m_InitOk;

    // ✅ FIX ChatGPT #2 : scheduler indépendant du chart timeframe
    // Strategy garde en mémoire le timestamp de la dernière bougie
    // traitée sur K_EMA50_TF (pas PERIOD_CURRENT). Comme ça, le
    // scanner H1 est appelé à chaque nouvelle bougie H1 même si
    // le chart est M15 ou H4.
    //----------------------------------------------------------------
    datetime        m_LastEma50BarTime;

    // Helpers d'exécution (communs à tous les scanners)
    //---------------------------------------------------
    bool ExecuteSignal(const string i_scanner_name, STRUCT_STRATEGY &io_datas);  // retourne TRUE si ordre envoyé avec succès
    void TryEma50(const MqlTick &i_tick);

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
        m_LastEma50BarTime = 0;

        // 1. Configure les données partagées
        //-------------------------------------
        if (!DATAS.Config(i_strategy_name, i_period, i_folder)) return(false);

        // 2. Configure chaque scanner enregistré
        //-----------------------------------------
        // Le nom passé au scanner sera le prefix du comment de l'ordre
        // posé par Broker → permet le filtrage par scanner dans
        // IsPositionOpenedToday.
        if (!m_Ema50Scanner.Config("Ema50Scanner", K_EMA50_TF))
        {
            LOG.ERROR(DATAS.GetStrategyName() + "Initialisation scanner EMA50 échouée", __FUNCTION__);
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
        m_Ema50Scanner.End();

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
    //| ✅ FIX ChatGPT #2 : anti-rejeu sur K_EMA50_TF (pas       |
    //|    PERIOD_CURRENT) → marche quel que soit le TF du chart |
    //|                                                          |
    //| ✅ FIX ChatGPT #1 : l'état évolue avant les filtres.     |
    //|    EMA50 n'a PAS d'état à maintenir (le crossUp se       |
    //|    calcule sur les bougies à la demande, et la position  |
    //|    réelle + SL/TP broker remplacent l'état persistant    |
    //|    du Pine) → pas d'UpdateState.                         |
    //|                                                          |
    //| Flux :                                                   |
    //|   1. Lecture du tick                                     |
    //|   2. Anti-rejeu sur K_EMA50_TF (nouvelle bougie ?)       |
    //|   3. Filtres d'EXÉCUTION (NEWS, heures, jours)          |
    //|   4. TryEma50() — verrou SOLO + GetSignal                |
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

        // ✅ FIX ChatGPT #2 : anti-rejeu basé sur K_EMA50_TF (pas PERIOD_CURRENT)
        //-----------------------------------------------------------------------
        // Permet à l'EA de tourner sur un chart M15 ou H4 sans rater de
        // clôture H1. Strategy est appelée à chaque tick par Koenigin,
        // mais ne fait le travail qu'une fois par nouvelle bougie K_EMA50_TF.
        //-----------------------------------------------------------------------
        datetime current_ema50_bar = iTime(Symbol(), K_EMA50_TF, 0);
        if (current_ema50_bar == 0)
        {
            LOG.WARNING(DATAS.GetStrategyName() + "iTime(K_EMA50_TF) indisponible", __FUNCTION__);
            return;
        }
        if (current_ema50_bar == m_LastEma50BarTime)
        {
            return;  // pas de nouvelle bougie sur K_EMA50_TF → on attend
        }
        m_LastEma50BarTime = current_ema50_bar;

        // === FILTRES D'EXÉCUTION (n'affectent pas l'état du scanner) ===
        //----------------------------------------------------------------

        // Zone NEWS : pas de nouveaux trades pendant la zone de sécurité.
        // EMA50 entre uniquement au marché (jamais d'ordre pending à
        // annuler) → simple passage de tour.
        //----------------------------------------------------------------
        if (!PARAM.OutsideSecurityZone())
        {
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
        TryEma50(l_Tick);
    }

    //+--------------------------------------------------------+
    //| ManagePositions                                         |
    //| Appelée par Koenigin::OnTick() à chaque tick + OnTimer().  |
    //|                                                          |
    //| EMA50 : rien à gérer intra-bar — le bracket SL/TP est    |
    //| posé avec l'ordre et porté par le broker (fidélité       |
    //| Pine : pas de BE, pas de trailing). Le Pine sortait      |
    //| uniquement au SL/TP simulés ; ici c'est le broker qui    |
    //| s'en charge.                                             |
    //|                                                          |
    //| Recette pour un scanner AVEC management (BE, trailing,  |
    //| invalidation) : lecture du tick → filtre NEWS →          |
    //| scanner.OnTick(tick).                                    |
    //+--------------------------------------------------------+
    void ManagePositions(void)
    {
        // EMA50 : aucun management — voir commentaire ci-dessus.
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
        return(false);  // échec → TryXxx appellera RollbackSignal
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
        return(false);  // échec → TryXxx appellera RollbackSignal
    }

    return(true);  // succès
}

//+------------------------------------------------------------------+
//| TryEma50                                                           |
//| Orchestration du scanner EMA50 :                                   |
//|   1. Verrou SOLO (position ouverte → pas de nouvelle entrée,      |
//|      Pine : "not active")                                         |
//|   2. GetSignal() — crossUp EMA50 + SL plus bas N bougies + TP 2R  |
//|   3. Si signal → ExecuteSignal                                     |
//|                                                                  |
//| Note : EMA50 = ordres au marché uniquement → pas de verrou         |
//| pending. Le signal est sans état (crossUp = propriété de la       |
//| bougie) : un échec d'ExecuteSignal ne se rollbacke pas — le trade |
//| est manqué, comme une alerte Pine non exécutée.                  |
//+------------------------------------------------------------------+
void CStrategy::TryEma50(const MqlTick &i_tick)
{
    // VERROU SOLO (1 trade simultané max — Pine-fidèle)
    //----------------------------------------------------
    if (m_Ema50Scanner.HasPositionForSymbol())
    {
        return;
    }

    // RÉCUPÉRATION DU SIGNAL (crossUp sur la bougie qui vient de clôturer)
    //----------------------------------------------------------------------
    STRUCT_STRATEGY l_Datas;
    ZeroMemory(l_Datas);
    if (!m_Ema50Scanner.GetSignal(i_tick, l_Datas))
    {
        return;  // pas de signal
    }

    // EXÉCUTION (DATAS + MONEY + BROKER)
    //---------------------------------------
    ExecuteSignal(m_Ema50Scanner.GetNamePublic(), l_Datas);
}

//+------------------------------------------------------------------+
//| Ajouter un scanner = définir son TryXxx() ici :                   |
//|   verrous → m_XxxScanner.GetSignal() → ExecuteSignal() →          |
//|   m_XxxScanner.RollbackSignal() si le scanner a un état à          |
//|   restaurer en cas d'échec d'ordre.                              |
//+------------------------------------------------------------------+
