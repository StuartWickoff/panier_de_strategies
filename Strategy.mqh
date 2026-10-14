//+------------------------------------------------------------------+
//|                                                                  |
//| Strategy.mqh — LIAISON (Koenigin architecture)                   |
//|                                                                  |
//| Strategy n'est plus une stratégie à part entière mais une       |
//| LIAISON :                                                        |
//|                                                                  |
//|   - Détient les ressources partagées (CDatas DATAS)              |
//|   - Détient un ou plusieurs membres scanner EXPLICITES          |
//|     (ici : CScannerEma50 m_Ema50Scanner,                        |
//|            CScannerRsi7  m_Rsi7Scanner,                         |
//|            CScannerBb10  m_Bb10Scanner,                         |
//|            CScannerOpr   m_OprScanner)                          |
//|   - Detection() : un SCHEDULER indépendant par scanner (son TF), |
//|     l'état/la lecture des scanners (RSI7 : UpdateState, BB10 :  |
//|     EvaluateBar) évolue AVANT les filtres, puis chaque scanner  |
//|     SÉLECTIONNÉ est appelé via TryXxx()                         |
//|     chaque scanner SÉLECTIONNÉ est appelé via TryXxx()          |
//|     (panier : K_EMA50_Trade / K_RSI7_Trade / K_BB10_Trade,      |
//|      false par défaut — greffé ≠ tradé)                         |
//|   - ManagePositions() délègue à scanner.OnTick()                 |
//|   - SetTicket/GetPositionNb/DeleteDetection/CloseOfPositions    |
//|     → délèguent à DATAS partagé                                  |
//|                                                                  |
//| La logique de marché (pivots, EMA, OPR, …) est dans les         |
//| scanners. Strategy ne sait PAS ce que fait un scanner, il       |
//| appelle juste Detect() et relaie au broker.                      |
//|                                                                  |
//| Chaque scanner a SON verrou SOLO (filtré par SON nom dans le    |
//| comment d'ordre) : 1 position par scanner, pas pour l'EA entier.|
//|                                                                  |
//| Ajouter un scanner = créer Scanner_xxx.mqh (avec son toggle
//| K_Xxx_Trade=false) + ajouter un membre + un scheduler + une
//| méthode TryXxx() + l'appeler dans Detection() sous if (K_Xxx_Trade).
//| Si le scanner est À ÉTAT : appeler son UpdateState() AVANT les
//| filtres d'exécution (pattern RSI7). On ne touche PAS aux autres
//| scanners.
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
// Le scanner apporte SES inputs dans SON fichier (auto-contenu),
// dont son toggle de sélection K_Xxx_Trade (panier).
#include <Koenigin/Scanner_ema50.mqh>
#include <Koenigin/Scanner_rsi7.mqh>
#include <Koenigin/Scanner_bb10.mqh>
#include <Koenigin/Scanner_opr.mqh>
#include <Koenigin/MarketRegime.mqh>
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
    CScannerRsi7  m_Rsi7Scanner;
    CScannerBb10  m_Bb10Scanner;
    CScannerOpr   m_OprScanner;   // OPR : PAS de scheduler de bougie — flux TEMPOREL
                                  // (fenetre 16:45-18:30 evaluee a chaque tick, heures en dur)
    CMarketRegime m_MarketRegime;

    // État interne
    //------------
    bool            m_InitOk;

    // ✅ FIX ChatGPT #2 : scheduler indépendant du chart timeframe
    // Strategy garde en mémoire le timestamp de la dernière bougie
    // traitée sur le TF DE CHAQUE SCANNER (pas PERIOD_CURRENT). Comme
    // ça, un scanner H1 est appelé à chaque nouvelle bougie H1 même si
    // le chart est M15 ou H4. Un scheduler par scanner : leurs TF
    // peuvent différer.
    //----------------------------------------------------------------
    datetime        m_LastEma50BarTime;
    datetime        m_LastRsi7BarTime;
    datetime        m_LastBb10BarTime;

    // Helpers d'exécution (communs à tous les scanners)
    //---------------------------------------------------
    bool ExecuteSignal(const string i_scanner_name, STRUCT_STRATEGY &io_datas);  // retourne TRUE si ordre envoyé avec succès
    void TryEma50(const MqlTick &i_tick);
    void TryRsi7(const MqlTick &i_tick);
    void TryBb10(const MqlTick &i_tick);
    void TryOpr(const MqlTick &i_tick);

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

        // ✅ FIX ChatGPT #2 : init des schedulers indépendants du chart TF
        //---------------------------------------------------------------
        m_LastEma50BarTime = 0;
        m_LastRsi7BarTime  = 0;
        m_LastBb10BarTime  = 0;

        // 1. Configure les données partagées
        //-------------------------------------
        if (!DATAS.Config(i_strategy_name, i_period, i_folder)) return(false);
        if (!m_MarketRegime.Config())
        {
            LOG.ERROR(DATAS.GetStrategyName() + "Initialisation du filtre de régime H4 échouée", __FUNCTION__);
            return(false);
        }

        // 2. Configure chaque scanner enregistré
        //-----------------------------------------
        // Le nom passé au scanner sera le prefix du comment de l'ordre
        // posé par Broker → permet le filtrage par scanner dans
        // HasPositionForSymbol (verrou SOLO par scanner).
        if (!m_Ema50Scanner.Config("Ema50Scanner", K_EMA50_TF))
        {
            LOG.ERROR(DATAS.GetStrategyName() + "Initialisation scanner EMA50 échouée", __FUNCTION__);
            return(false);
        }
        if (!m_Rsi7Scanner.Config("Rsi7Scanner", K_RSI7_TF))
        {
            LOG.ERROR(DATAS.GetStrategyName() + "Initialisation scanner RSI7 échouée", __FUNCTION__);
            return(false);
        }
        if (!m_Bb10Scanner.Config("Bb10Scanner", K_BB10_TF))
        {
            LOG.ERROR(DATAS.GetStrategyName() + "Initialisation scanner BB10 échouée", __FUNCTION__);
            return(false);
        }
        if (!m_OprScanner.Config("OprScanner", K_OPR_TF))
        {
            LOG.ERROR(DATAS.GetStrategyName() + "Initialisation scanner OPR échouée", __FUNCTION__);
            return(false);
        }

        // PANIER : annonce une fois le statut de chaque scanner
        // (greffé ≠ tradé — mémorisé dans le journal au démarrage)
        //------------------------------------------------------------------
        if (K_EMA50_Trade)
            LOG.INFO(DATAS.GetStrategyName() + "Panier : EMA50 SOLO sélectionné (K_EMA50_Trade=true) — trade ACTIF", __FUNCTION__);
        else
            LOG.INFO(DATAS.GetStrategyName() + "Panier : EMA50 SOLO non sélectionné (K_EMA50_Trade=false) — DORMANT, aucun trade", __FUNCTION__);

        if (K_RSI7_Trade)
            LOG.INFO(DATAS.GetStrategyName() + "Panier : RSI7 SOLO sélectionné (K_RSI7_Trade=true) — trade ACTIF", __FUNCTION__);
        else
            LOG.INFO(DATAS.GetStrategyName() + "Panier : RSI7 SOLO non sélectionné (K_RSI7_Trade=false) — DORMANT, aucun trade", __FUNCTION__);

        if (K_BB10_Trade)
            LOG.INFO(DATAS.GetStrategyName() + "Panier : BB10 SOLO sélectionné (K_BB10_Trade=true) — trade ACTIF", __FUNCTION__);
        else
            LOG.INFO(DATAS.GetStrategyName() + "Panier : BB10 SOLO non sélectionné (K_BB10_Trade=false) — DORMANT, aucun trade", __FUNCTION__);

        if (K_OPR_Trade)
            LOG.INFO(DATAS.GetStrategyName() + "Panier : OPR sélectionné (K_OPR_Trade=true) — trade ACTIF", __FUNCTION__);
        else
            LOG.INFO(DATAS.GetStrategyName() + "Panier : OPR non sélectionné (K_OPR_Trade=false) — DORMANT, aucun trade", __FUNCTION__);

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
        m_Rsi7Scanner.End();
        m_Bb10Scanner.End();
        m_OprScanner.End();
        m_MarketRegime.End();

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
    //| ✅ FIX ChatGPT #2 : anti-rejeu sur le TF DE CHAQUE       |
    //|    SCANNER (pas PERIOD_CURRENT) → marche quel que soit   |
    //|    le TF du chart. Un scheduler par scanner.             |
    //|                                                          |
    //| ✅ FIX ChatGPT #1 : l'état évolue avant les filtres.     |
    //|    - EMA50 : SANS ÉTAT (le crossUp se calcule sur les     |
    //|      bougies à la demande) → pas d'UpdateState.          |
    //|    - RSI7 : À ÉTAT (machine à pivots prev*, le Pine met  |
    //|      ses var à jour à CHAQUE clôture) → UpdateState()    |
    //|      appelé à CHAQUE nouvelle bougie K_RSI7_TF, AVANT    |
    //|      les filtres, le verrou SOLO et le toggle panier.    |
    //|      Sinon l'état serait troué (pivots manqués pendant   |
    //|      une position ouverte / une zone NEWS) et les gaps   |
    //|      calculés sur des pivots non adjacents.              |
    //|                                                          |
    //| Flux :                                                   |
    //|   1. Lecture du tick                                     |
    //|   2. Anti-rejeu PAR SCANNER (nouvelle bougie sur SON TF ?) |
    //|   3. État/lecture des scanners (RSI7 : UpdateState, BB10 :   |
    //|      EvaluateBar) — AVANT les filtres, horodatage validé     |
    //|      seulement APRÈS une mise à jour/lecture RÉUSSIE         |
    //|      (sinon retry au tick suivant — FIX AUDIT 3 / P1-2)      |
    //|   4. Filtres d'EXÉCUTION (NEWS, heures, jours)          |
    //|   5. Panier : TryXxx() des scanners sélectionnés dont    |
    //|      la bougie est nouvelle — verrou SOLO + GetSignal    |
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

        // Le régime est calculé sur la dernière bougie H4 clôturée.
        // En cas de données indisponibles, le module reste en Unknown
        // et bloque les nouvelles entrées de ces scanners.
        m_MarketRegime.Update();

        // ✅ FIX ChatGPT #2 : anti-rejeu basé sur le TF DE CHAQUE SCANNER
        //-----------------------------------------------------------------------
        // Permet à l'EA de tourner sur un chart M15 ou H4 sans rater de
        // clôture H1. Strategy est appelée à chaque tick par Koenigin,
        // mais ne fait le travail d'un scanner qu'une fois par nouvelle
        // bougie sur SON TF. Les schedulers sont indépendants : les TF
        // des scanners peuvent différer.
        //-----------------------------------------------------------------------
        bool l_NewEma50 = false;
        bool l_NewRsi7  = false;
        bool l_NewBb10  = false;

        datetime l_BarTime = iTime(Symbol(), K_EMA50_TF, 0);
        if (l_BarTime == 0)
        {
            LOG.WARNING(DATAS.GetStrategyName() + "iTime(K_EMA50_TF) indisponible", __FUNCTION__);
        }
        else if (l_BarTime != m_LastEma50BarTime)
        {
            m_LastEma50BarTime = l_BarTime;
            l_NewEma50 = true;
        }

        datetime l_Rsi7BarTime = iTime(Symbol(), K_RSI7_TF, 0);
        if (l_Rsi7BarTime == 0)
        {
            LOG.WARNING(DATAS.GetStrategyName() + "iTime(K_RSI7_TF) indisponible", __FUNCTION__);
        }
        else if (l_Rsi7BarTime != m_LastRsi7BarTime)
        {
            // ✅ FIX AUDIT 3 : CANDIDATURE seulement — l'horodatage est
            // validé APRÈS une mise à jour d'état RÉUSSIE (voir plus bas).
            // L'ancien code mémorisait ici : une bougie dont les données
            // (Copy*/indicateur) échouaient était définitivement perdue.
            //----------------------------------------------------------------------------------------
            l_NewRsi7 = true;
        }

        datetime l_Bb10BarTime = iTime(Symbol(), K_BB10_TF, 0);
        if (l_Bb10BarTime == 0)
        {
            LOG.WARNING(DATAS.GetStrategyName() + "iTime(K_BB10_TF) indisponible", __FUNCTION__);
        }
        else if (m_LastBb10BarTime == 0)
        {
            // ✅ FIX AUDIT BB10 P1-1 : PREMIER CONTACT = ARMEMENT, pas
            // une opportunité. La bougie clôturée AVANT le lancement
            // de l'EA n'est jamais évaluée (sinon entrée rétroactive
            // sur un signal ancien — même défaut que le démarrage
            // RSI7, corrigé en sémantique « alerte Pine » : l'EA ne
            // trade que les bougies qu'il a vues se former). La
            // prochaine nouvelle bougie sera traitée normalement.
            //---------------------------------------------------------------
            m_LastBb10BarTime = l_Bb10BarTime;   // référence posée SANS candidature
        }
        else if (l_Bb10BarTime != m_LastBb10BarTime)
        {
            // ✅ FIX AUDIT BB10 P1-2 : CANDIDATURE seulement —
            // l'horodatage est validé APRÈS une lecture réussie
            // (EvaluateBar, plus bas, AVANT les filtres). Un échec
            // CopyClose/iLowest ne consomme PAS la bougie : retry au
            // tick suivant (jamais perdue, jamais traitée deux fois).
            // EMA50 garde son schéma d'origine (validation immédiate) :
            // comportement figé par des backtests validés, pas de
            // modification sans nécessité démontrée (mandat audit).
            //---------------------------------------------------------------
            l_NewBb10 = true;
        }

        if (!l_NewEma50 && !l_NewRsi7 && !l_NewBb10 && !K_OPR_Trade) return;  // aucune nouvelle bougie → on attend
        // ✅ OPR : le flux OPR est TEMPOREL (fenêtre 16:45-18:30 évaluée à
        // chaque tick, pas à chaque nouvelle bougie) → quand OPR est
        // sélectionné, on continue vers les filtres même sans nouvelle
        // bougie des autres scanners. K_OPR_Trade=false → retour comme
        // avant (non-régression stricte des 3 scanners).

        // ✅ FIX ChatGPT #1 : l'état AVANT les filtres.
        // RSI7 = scanner À ÉTAT : la machine à pivots tourne à CHAQUE
        // nouvelle bougie K_RSI7_TF — même si le scanner n'est pas
        // sélectionné (K_RSI7_Trade=false), même si une position est
        // ouverte, même si les filtres d'exécution vont bloquer.
        // Fidélité Pine : l'indicateur calcule toujours ; seule
        // l'ENTRÉE est filtrée (un signal filtré = propriété de la
        // bougie, pas de rejeu).
        //
        // ✅ FIX AUDIT 3 : UpdateState retourne le succès. En cas
        // d'échec (backfill, iTime, Copy* indisponible), la bougie
        // n'est PAS validée → elle sera RETENTÉE au tick suivant de
        // la MÊME bougie (jamais perdue, jamais traitée deux fois —
        // les machines déjà à jour sautent, cf. m_LastProcBarL/S
        // dans le scanner). Pas d'exécution ce tick : données
        // incomplètes. EMA50 (SANS ÉTAT) garde son schéma d'origine :
        // un échec de lecture n'y corrompt rien (pas de mémoire).
        //--------------------------------------------------------------
        if (l_NewRsi7)
        {
            if (m_Rsi7Scanner.UpdateState())
            {
                m_LastRsi7BarTime = l_Rsi7BarTime;   // validé APRÈS succès
            }
            else
            {
                l_NewRsi7 = false;                   // retry au tick suivant (même bougie)
                // NB : EMA50 (validé d'office) et BB10 (candidature en
                // attente, évalué plus bas) ne sont PAS bloqués par le
                // retry RSI7 — sinon une panne Copy* du RSI7 avalerait
                // leurs bougies.
                if (!l_NewEma50 && !l_NewBb10 && !K_OPR_Trade) return;   // rien d'autre à faire ce tick
            }
        }

        // ✅ FIX AUDIT BB10 P1-2 : évaluation de la bougie clôturée
        // AVANT les filtres (pattern UpdateState RSI7, adapté au
        // sans-état) :
        //   - EvaluateBar() lit les données et FIGE la décision de la
        //     bougie (sens + SL = propriétés immuables de la bougie
        //     clôturée) ; GetSignal() n'a plus qu'à consommer cette
        //     décision après les filtres (garde ask/bid du tick)
        //   - retour FALSE = données indisponibles → bougie NON
        //     validée → retry au tick suivant (signal préservé)
        //   - retour TRUE = lecture faite → horodatage validé, que la
        //     bougie porte un signal ou non. Les filtres d'exécution
        //     et le verrou SOLO consomment la décision SANS rejouer la
        //     bougie : un signal filtré = trade manqué (convention
        //     projet inchangée — pas d'entrée mi-bougie en fin de
        //     zone NEWS).
        //------------------------------------------------------------------
        if (l_NewBb10)
        {
            if (m_Bb10Scanner.EvaluateBar())
            {
                m_LastBb10BarTime = l_Bb10BarTime;   // validé APRÈS lecture réussie
            }
            else
            {
                l_NewBb10 = false;                   // retry au tick suivant (même bougie)
                if (!l_NewEma50 && !l_NewRsi7 && !K_OPR_Trade) return;   // rien d'autre à faire ce tick
            }
        }

        // === FILTRES D'EXÉCUTION (n'affectent pas l'état des scanners) ===
        //----------------------------------------------------------------

        // Zone NEWS : pas de nouveaux trades pendant la zone de sécurité.
        // Les scanners entrent uniquement au marché (jamais d'ordre
        // pending à annuler) → simple passage de tour.
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

        // === EXÉCUTION DES SCANNERS (PANIER) ===
        //---------------------------------------
        // Greffé ≠ tradé : un scanner est câblé en permanence, mais ne
        // trade QUE s'il est sélectionné (K_Xxx_Trade). Dé-sélectionner
        // en cours de route stoppe les NOUVELLES entrées ; les positions
        // déjà ouvertes courent jusqu'à leur SL/TP broker (intouchables).
        // Un signal émis pendant une période non sélectionnée est une
        // propriété de la bougie : il ne se rejoue pas (Pine-fidèle).
        //---------------------------------------------------------------
        if (l_NewEma50 && K_EMA50_Trade) TryEma50(l_Tick);
        if (l_NewRsi7 && K_RSI7_Trade && m_MarketRegime.AllowsRangeStrategy(eRRS_Rsi7)) TryRsi7(l_Tick);
        if (l_NewBb10 && K_BB10_Trade && m_MarketRegime.AllowsRangeStrategy(eRRS_Bb10)) TryBb10(l_Tick);
        // ✅ OPR : PAS de condition l_NewOpr — le scanner OPR est évalué à
        // CHAQUE TICK quand il est sélectionné (flux temporel, fidélité au
        // pseudo code validé : ses fenêtres/verrous internes décident).
        // Il est appelé ICI, après les filtres maison NEWS/heures/jours
        // (comme les autres scanners — en zone NEWS, pas de détection).
        if (K_OPR_Trade) TryOpr(l_Tick);
    }

    //+--------------------------------------------------------+
    //| ManagePositions                                         |
    //| Appelée par Koenigin::OnTick() à chaque tick + OnTimer().  |
    //|                                                          |
    //| EMA50, RSI7, BB10 : rien à gérer intra-bar — le bracket    |
    //| SL/TP est posé avec l'ordre et porté par le broker        |
    //| (fidélité Pine : pas de BE, pas de trailing).             |
    //|                                                          |
    //| OPR : scanner AVEC management — la recette est réalisée : |
    //| lecture du tick (dans le scanner) → filtre NEWS (dans le  |
    //| scanner : annulation pendings + BE quand même, fidèle     |
    //| BotOPR) → m_OprScanner.OnTick(). Gère en API brute :       |
    //| zone NEWS, clôture forcée >= 22:00, cancel filet >= 18:30,|
    //| BreakEven 0.25R, divergence ST/EMA. Filtré par comment    |
    //| "OprScanner" — n'importe jamais sur les autres scanners.  |
    //+--------------------------------------------------------+
    void ManagePositions(void)
    {
        // EMA50, RSI7, BB10 : aucun management — voir commentaire ci-dessus.

        // OPR : management à chaque tick + OnTimer 1 s (marché gelé compris)
        //----------------------------------------------------------------
        m_OprScanner.OnTick();
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
    // ✅ FIX VERROU SOLO (constaté sur backtest 2025 US100.cash H1) :
    // on passe le NOM DU SCANNER (pas le nom EA) à Broker. Broker le pose
    // dans le comment de l'ordre (l_Request.comment = i_StrategyName +
    // " X-TYPE") et la position hérite ce comment → HasPositionForSymbol()
    // la reconnaît (StringFind(comment, m_Name)) et bloque toute nouvelle
    // entrée tant qu'elle est ouverte — équivalent exact du "not active"
    // du Pine.
    // AVANT : DATAS.GetStrategyName() ("KoeniginUS100.cash(H1) - ") → le
    // comment ne contenait jamais le nom du scanner → le verrou ne voyait
    // aucune position → empilement (jusqu'à 6 simultanées, 154 entrées sur
    // 203 prises en violation du SOLO).
    //-----------------------------------------------------------------
    if (!BROKER.SendOrder(i_scanner_name, io_datas))
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
//|   2. GetSignal() — crossUp (long) et, si K_EMA50_Short,          |
//|      crossDown (short) ; SL = extrême N bougies ; TP = 2R        |
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

    if (!m_MarketRegime.AllowsEmaSignal(l_Datas.Trend))
    {
        return;
    }

    // EXÉCUTION (DATAS + MONEY + BROKER)
    //---------------------------------------
    ExecuteSignal(m_Ema50Scanner.GetNamePublic(), l_Datas);
}

//+------------------------------------------------------------------+
//| TryRsi7                                                            |
//| Orchestration du scanner RSI7 :                                   |
//|   1. Verrou SOLO (position ouverte → pas de nouvelle entrée,      |
//|      Pine : "not active" — filtré par LE nom de CE scanner)      |
//|   2. GetSignal() — divergence cachée confirmée à la clôture ;    |
//|      SL = extrême N bougies ; TP = 3R ; long (div. haussière)    |
//|      + short optionnel (div. baissière, input K_RSI7_Short)      |
//|   3. Si signal → ExecuteSignal                                     |
//|                                                                  |
//| Note : l'état pivots (prev*) vit dans UpdateState(), appelé à      |
//| chaque nouvelle bougie AVANT les filtres (et retenté au tick      |
//| suivant tant qu'il retourne FALSE — FIX AUDIT 3) — TryRsi7 ne fait |
//| que consommer le drapeau de divergence de la bougie. Un échec     |
//| d'ExecuteSignal ne se rollbacke pas : l'état pivots n'est PAS lié |
//| à un ordre (il évoluerait pareil dans le Pine, alerte prise ou non) |
//| — le trade est manqué, comme une alerte Pine non exécutée.        |
//+------------------------------------------------------------------+
void CStrategy::TryRsi7(const MqlTick &i_tick)
{
    // VERROU SOLO (1 trade simultané max — Pine-fidèle)
    //----------------------------------------------------
    if (m_Rsi7Scanner.HasPositionForSymbol())
    {
        return;
    }

    // RÉCUPÉRATION DU SIGNAL (divergence cachée confirmée à la bougie
    // qui vient de clôturer — drapeau posé par UpdateState)
    //------------------------------------------------------------------
    STRUCT_STRATEGY l_Datas;
    ZeroMemory(l_Datas);
    if (!m_Rsi7Scanner.GetSignal(i_tick, l_Datas))
    {
        return;  // pas de signal
    }

    // EXÉCUTION (DATAS + MONEY + BROKER)
    //---------------------------------------
    ExecuteSignal(m_Rsi7Scanner.GetNamePublic(), l_Datas);
}

//+------------------------------------------------------------------+
//| TryBb10                                                            |
//| Orchestration du scanner BB10 :                                   |
//|   1. Verrou SOLO (position ouverte → pas de nouvelle entrée,      |
//|      Pine : "not active" — filtré par LE nom de CE scanner)      |
//|   2. GetSignal() — consomme la décision figée par EvaluateBar()   |
//|      (appelé AVANT les filtres dans Detection) ; garde            |
//|      d'exécution sur le ask/bid du tick courant                   |
//|   3. Si signal → ExecuteSignal                                     |
//|                                                                  |
//| Note prix (✅ doc audit BB10 P2, écart assumé) : le lot (MONEY)   |
//| et le TP sont fondés sur l'entrée du tick de détection ; Broker   |
//| relit un tick frais juste avant OrderSend. Dans le TESTEUR les    |
//| deux lectures voient le MÊME tick (figé pendant l'OnTick) →       |
//| aucun écart en backtest/parité ; en live l'écart est borné au     |
//| mouvement d'un tick pendant le calcul de lot (même pile          |
//| d'appel). Le ré-ancrage du TP sur le fill réel (TRADE_ACTION_SLTP |
//| post-fill) toucherait le pipeline partagé EMA50/RSI7 →            |
//| volontairement non fait (mandat : correctifs ciblés).             |
//|                                                                  |
//| Note : BB10 = ordres au marché uniquement → pas de verrou         |
//| pending. La décision est figée par bougie (sans état glissant) : |
//| un échec d'ExecuteSignal ne se rollbacke pas — le trade est       |
//| manqué, comme une alerte Pine non exécutée.                      |
//+------------------------------------------------------------------+
void CStrategy::TryBb10(const MqlTick &i_tick)
{
    // VERROU SOLO (1 trade simultané max — Pine-fidèle)
    //----------------------------------------------------
    if (m_Bb10Scanner.HasPositionForSymbol())
    {
        return;
    }

    // RÉCUPÉRATION DU SIGNAL (réintégration sur la bougie qui vient
    // de clôturer — bande recalculée à la demande, sans état)
    //------------------------------------------------------------------
    STRUCT_STRATEGY l_Datas;
    ZeroMemory(l_Datas);
    if (!m_Bb10Scanner.GetSignal(i_tick, l_Datas))
    {
        return;  // pas de signal
    }

    // EXÉCUTION (DATAS + MONEY + BROKER)
    //---------------------------------------
    ExecuteSignal(m_Bb10Scanner.GetNamePublic(), l_Datas);
}

//+------------------------------------------------------------------+
//| TryOpr                                                            |
//| Orchestration du scanner OPR (stratégie d'origine BotOPR_001) :   |
//|   1. m_OprScanner.TryDetect() — le flux BotOPR complet :          |
//|      reset journalier + heures en dur, verrou 1 trade/jour        |
//|      3 couches, lecture range safe_read+retry, filtre ATR,        |
//|      convergence ST/EMA, divergence-cancel, fenêtre               |
//|      [16:45, 18:30), STOP vs INSTANT BREAKOUT (slippage)          |
//|   2. Si signal → ExecuteSignal (sizing MONEY sur Entry PLANNÉ,    |
//|      SetData, BROKER.SendOrder dispatch IsMarketOrder →          |
//|      ordre au marché ou BUY-STOP/SELL-STOP)                       |
//|                                                                  |
//| Les verrous (journalier, pending, position) et le management     |
//| (NEWS/22h/18h30/BE/divergence) vivent DANS le scanner             |
//| (TryDetect / OnTick) : TryOpr est le relais panier, appelé       |
//| à chaque tick après les filtres maison (flux temporel).          |
//| Un échec d'ExecuteSignal ne se rollbacke pas : le verrou          |
//| journalier n'est armé que par l'exécution RÉELLE (deal du        |
//| jour / franchissement du pending / position ouverte) — le trade  |
//| est manqué, comme BotOPR.                                        |
//+------------------------------------------------------------------+
void CStrategy::TryOpr(const MqlTick &i_tick)
{
    // RÉCUPÉRATION DU SIGNAL (flux complet 15 étapes dans le scanner)
    //------------------------------------------------------------------
    STRUCT_STRATEGY l_Datas;
    ZeroMemory(l_Datas);
    if (!m_OprScanner.TryDetect(i_tick, l_Datas))
    {
        return;  // pas de signal (verrou/filtre/fenêtre/échec lecture)
    }

    // EXÉCUTION (DATAS + MONEY + BROKER — dispatch marché vs stop)
    //---------------------------------------------------------------
    ExecuteSignal(m_OprScanner.GetNamePublic(), l_Datas);
}

//+------------------------------------------------------------------+
//| Ajouter un scanner = définir son TryXxx() ici :                   |
//|   1. Scanner_xxx.mqh : input bool K_Xxx_Trade = false (panier)   |
//|   2. Un membre + un scheduler m_LastXxxBarTime (init 0 au Config) |
//|   3. Detection() : détection nouvelle bougie sur K_Xxx_TF ; si    |
//|      le scanner est À ÉTAT → m_XxxScanner.UpdateState() AVANT les |
//|      filtres ; s'il est SANS ÉTAT → m_XxxScanner.EvaluateBar()    |
//|      AVANT les filtres (fige la décision de la bougie clôturée).  |
//|      Dans les DEUX cas : armement au 1er contact (m_LastXxxBarTime |
//|      == 0 → référence sans candidature, aucune entrée rétroactive)|
//|      ET horodatage validé seulement après un retour TRUE (échec =  |
//|      retry au tick suivant, jamais de bougie perdue). Seul EMA50   |
//|      garde la validation immédiate historique (backtests figés) ;  |
//|      puis if (new_xxx && K_Xxx_Trade) TryXxx(l_Tick);             |
//|   4. TryXxx : verrous → m_XxxScanner.GetSignal() →               |
//|      ExecuteSignal()                                              |
//|   5. m_XxxScanner.RollbackSignal() si le scanner a un état lié à  |
//|      l'ordre à restaurer en cas d'échec.                          |
//+------------------------------------------------------------------+
