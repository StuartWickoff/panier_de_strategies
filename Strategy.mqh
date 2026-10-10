//+------------------------------------------------------------------+
//|                                                                  |
//| Strategy.mqh — LIAISON (Koenigin architecture)                   |
//|                                                                  |
//| Strategy n'est plus une stratégie à part entière mais une       |
//| LIAISON :                                                        |
//|                                                                  |
//|   - Détient les ressources partagées (CDatas DATAS)              |
//|   - Détient un ou plusieurs membres scanner EXPLICITES          |
//|     (aucun scanner branché actuellement)                        |
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
// Aucun scanner branché actuellement. Pour en brancher un :
// #include <OPR_Bot/Scanner_xxx.mqh>


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
    // Aucun scanner branché actuellement :
    // CScannerXxx  m_XxxScanner;

    // État interne
    //------------
    bool            m_InitOk;

    // Helpers d'exécution (communs à tous les scanners)
    //---------------------------------------------------
    bool ExecuteSignal(const string i_scanner_name, STRUCT_STRATEGY &io_datas);  // retourne TRUE si ordre envoyé avec succès
    // Ajouter ici : void TryXxx(const MqlTick &i_tick);

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

        // 1. Configure les données partagées
        //-------------------------------------
        if (!DATAS.Config(i_strategy_name, i_period, i_folder)) return(false);

        // 2. Configure chaque scanner enregistré
        //-----------------------------------------
        // Le nom passé au scanner sera le prefix du comment de l'ordre
        // posé par Broker → permet le filtrage par scanner dans
        // IsPositionOpenedToday.
        // Aucun scanner branché actuellement :
        // if (!m_XxxScanner.Config("XxxScanner", K_Xxx_TF))
        // {
        //     LOG.ERROR(DATAS.GetStrategyName() + "Initialisation scanner Xxx échouée", __FUNCTION__);
        //     return(false);
        // }

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
        // Aucun scanner branché actuellement : m_XxxScanner.End();

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
    //| Aucun scanner branché : rien à détecter.                |
    //|                                                          |
    //| Recette d'intégration d'un scanner (règles des FIX) :  |
    //|   1. Lecture du tick                                     |
    //|   2. Anti-rejeu sur le TF du SCANNER (pas               |
    //|      PERIOD_CURRENT) → marche quel que soit le TF       |
    //|      du chart                                            |
    //|   3. UpdateState() — TOUJOURS, AVANT les filtres        |
    //|      (l'état évolue même en zone filtrée, comme le      |
    //|      Pine sur barstate.isconfirmed)                     |
    //|   4. Filtres d'EXÉCUTION (NEWS, heures, jours)          |
    //|   5. TryXxx() — verrous d'entrée + GetSignal            |
    //+--------------------------------------------------------+
    void Detection(void)
    {
        // Aucun scanner branché.
    }

    //+--------------------------------------------------------+
    //| ManagePositions                                         |
    //| Appelée par Koenigin::OnTick() à chaque tick + OnTimer().  |
    //|                                                          |
    //| Aucun scanner branché : rien à gérer.                   |
    //|                                                          |
    //| Recette d'intégration d'un scanner :                    |
    //|   1. Lecture du tick                                     |
    //|   2. Filtre NEWS (annulation pendings)                  |
    //|   3. Pour chaque scanner : scanner.OnTick(tick)           |
    //|      (BE, trailing, invalidation — selon le scanner)     |
    //+--------------------------------------------------------+
    void ManagePositions(void)
    {
        // Aucun scanner branché.
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
//| Ajouter ici les TryXxx() — orchestration d'un scanner :          |
//|                                                                  |
//|   1. Verrous d'entrée (solo journalier optionnel, position       |
//|      ouverte, pending)                                           |
//|   2. m_XxxScanner.GetSignal() — conditions d'entrée remplies ?   |
//|   3. Si signal → ExecuteSignal(m_XxxScanner.GetNamePublic(),     |
//|      datas). En cas d'échec → m_XxxScanner.RollbackSignal()      |
//|                                                                  |
//| Note : UpdateState() est appelé par Detection() AVANT les        |
//| TryXxx(), donc l'état du scanner est déjà à jour.                |
//+------------------------------------------------------------------+
