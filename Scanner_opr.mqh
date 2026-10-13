//+------------------------------------------------------------------+
//|                                                                  |
//| Scanner_opr.mqh — SCANNER OPR (portage de la stratégie d'origine) |
//|                                                                  |
//| Portage de la stratégie OPR du BotOPR_001 (source :               |
//| OprImportantsFiles/Strategy.mqh 1067 l. + BB_ADX_expert.mqh +     |
//| DST.mqh, config NASDAQ) dans l'architecture multi-scanners de     |
//| Koenigin, en scanner AUTO-CONTENU (pattern maison BB10).          |
//|                                                                  |
//| MÉCANISME (fidèle BotOPR_001, US100 M15) :                        |
//|  - Reset journalier -> heures du jour en dur (16:30 / 16:45 /     |
//|    18:30 / 22:00 heure SERVEUR — décision utilisateur : PAS de    |
//|    DST.mqh, les heures sont codées en dur ; 5ers et NYSE          |
//|    partagent le même DST américain -> heures fixes toute l'année) |
//|  - Range = high/low de la bougie M15 de 16:30, lu à partir de     |
//|    16:45 (safe_read = start + PeriodSeconds(TF)), safe_read avec  |
//|    retry au tick suivant si CopyHigh/CopyLow échoue               |
//|  - Fenêtre d'entrée [16:45, 18:30)                                |
//|  - Filtre range >= K_OPR_MinRange_ATR_Ratio x ATR(14, TF)         |
//|    (ATR illisible -> filtre ignoré, permissif — comme BotOPR)     |
//|  - Convergence exigée : SuperTrend(H1, iCustom "supertrend",      |
//|    buffer 2 = direction, shift 1) + EMA20/50 (M5, shift 1)        |
//|  - Prix deja cassé -> ordre MARCHÉ avec garde slippage            |
//|    (K_OPR_MaxSlippage, sinon abandon) ; sinon ordre STOP à        |
//|    high/low + K_OPR_Offset                                        |
//|  - SL 3 modes (Milieu / LowHigh / LowHigh+buffer %) ; TP = rr     |
//|  - Verrou 1 trade/JOUR à 3 couches (deals du jour / franchissement|
//|    d'un pending / position ouverte) + flag mémorisé               |
//|  - Annulations : zone NEWS (pending + BE quand meme), divergence  |
//|    ST/EMA (pending), >= 18:30 (pending), clôture forcée >= 22:00  |
//|  - BreakEven a K_OPR_BE_R : SL = open +- spread +- buffer BE      |
//|    (garde anti-BE-infini), TRADE_ACTION_SLTP brut                 |
//|  - Sizing : MONEY.CalculateLotSize sur Entry/SL PLANNED (jamais   |
//|    le fill réel — fidèle BotOPR), fait par CStrategy::            |
//|    ExecuteSignal (pattern maison : le scanner ne touche pas       |
//|    BROKER/MONEY/DATAS pour l'ordre initial)                       |
//|                                                                  |
//| DEUX POINTS D'ENTRÉE (actés Task 33) :                            |
//|  - TryDetect(tick, o_datas) : DETECTION. Appelé par TryOpr()      |
//|    depuis CStrategy::Detection() panier, APRES les filtres maison |
//|    (NEWS/heures/jours) — l'évaluation est TEMPORELLE (a chaque    |
//|    tick dans la fenetre), pas liée a une nouvelle bougie :        |
//|    d'ou les 3 retours précoces corrigés par "&& !K_OPR_Trade"     |
//|    dans Detection() (non-régression stricte quand OPR est off).   |
//|    Retourne TRUE + o_datas rempli quand un ordre doit etre posé   |
//|    (CStrategy::ExecuteSignal fait sizing/SetData/SendOrder,       |
//|    dispatch IsMarketOrder -> marché ou BUY-STOP/SELL-STOP).       |
//|  - OnTick() : MANAGEMENT. Appelé par CStrategy::ManagePositions() |
//|    (donc a chaque tick + OnTimer 1 s, marche gelé compris).       |
//|    API BRUTE (OrderSend direct) : aucune dépendance BROKER/       |
//|    DATAS/MONEY pour les annulations/clôtures/BE (règle maison).   |
//|                                                                  |
//| IDENTITÉ : par COMMENT "OprScanner" (POSITION_COMMENT,            |
//| ORDER_COMMENT, DEAL_COMMENT) — DÉVIATION NÉCESSAIRE vs BotOPR    |
//| (qui filtrait par magic seul) car le magic est PARTAGÉ par tout   |
//| le panier Koenigin : sans le comment, un BUY-STOP Ema50Scanner    |
//| franchi verrouillerait la journée OPR. Le comment d'ordre est     |
//| posé par Broker : "OprScanner BUY-STOP"/"SELL-STOP" (préfixe du   |
//| nom du scanner, pattern verrou SOLO) ; la position et le deal     |
//| d'entrée l'héritent -> les 3 couches du verrou journalier le      |
//| reconnaissent.                                                   |
//|                                                                  |
//| === TRADUCTION BotOPR -> PANIER KOENIGIN (écarts documentés) ===   |
//|                                                                  |
//| - GetSymbolConfig NASDAQ (DST.mqh) -> INPUTS auto-contenus :      |
//|   risk_reward=1.0 -> K_OPR_TP_R ; offset_points=1.0 ->           |
//|   K_OPR_Offset (valeur BRUTE en prix, non multipliée par          |
//|   _Point — sémantique BotOPR) ; apply_be/breakeven_r=0.25 ->      |
//|   K_OPR_BE / K_OPR_BE_R ; buffer_be=2.0 -> K_OPR_BE_Buffer_Points |
//|   (multiplié par _Point, sémantique BotOPR).                      |
//| - IsSessionValid() : no-op dans le BotOPR (excluded_months/days   |
//|   ZeroMemory=0) -> NON PORTÉ : aucun jour/mois exclu, documenté.  |
//| - Les statiques JOURNALIÈRES de Detection() et FindStop()         |
//|   (dupliquées dans le BotOPR, memes valeurs) -> FUSIONNÉES en un  |
//|   seul état journalier (DailyRefresh + m_RangeHigh/Low) : meme    |
//|   comportement observable, structure clarifiée. Le verrou mémorisé|
//|   (m_LockedDay/m_PositionOpened) reste séparé (fidèle            |
//|   IsPositionOpenedToday).                                        |
//| - Blocs temporels de Detection() BotOPR (NEWS-annule, >= 22:00    |
//|   clôture forcée, >= 18:30 annule) -> DÉPLACÉS dans OnTick() du   |
//|   scanner (management) : Koenigin appelle ManagePositions() AVANT |
//|   Detection() dans le meme OnTick -> meme ordre effectif que le   |
//|   BotOPR (cancel puis return de détection). La détection          |
//|   TryDetect reste bornée par sa fenetre [16:45, 18:30).           |
//| - "Invalidation de dernière minute" BotOPR (st != ema re-testé    |
//|   entre SetData et SendOrder) : code mort défensif — les deux     |
//|   lectures se font dans le meme flux avec les memes variables     |
//|   locales, la condition ne peut jamais changer entre les deux     |
//|   points. Couverte par la convergence exigée en amont -> omise,   |
//|   comportement observable identique.                              |
//| - DATAS.CancelPendingOrder/CloseOfPositions (magic+symbole, SANS  |
//|   comment -> attraperait tout le panier) -> API BRUTE dans le     |
//|   scanner, filtrée par comment "OprScanner" (TRADE_ACTION_REMOVE /|
//|   TRADE_ACTION_DEAL / TRADE_ACTION_SLTP).                         |
//| - Le BotOPR évaluait Detection() a chaque NOUVELLE BOUGIE du chart|
//|   (NewCandle PERIOD_CURRENT) ; le panier évalue a chaque TICK     |
//|   (FIX ChatGPT #2) : l'ordre STOP est posé plus prompt, au meme   |
//|   niveau (high/low + offset) — pseudo code validé Task 33.        |
//| - supertrend.ex5 REQUIS : iCustom "supertrend" (minuscules),      |
//|   FAIL-FAST au Config si le handle est invalide. La source        |
//|   (supertrend.mq5, Salman Soltaniyan, MIT) est au racine du dépôt |
//|   : la compiler dans MQL5/Indicators. Buffer 2 = direction        |
//|   (1 = haut, -1 = bas) — confirmé sur le code source.             |
//|                                                                  |
//| Le scanner ne fait AUCUN appel direct a BROKER, MONEY ou DATAS.   |
//| Il remplit STRUCT_STRATEGY (TryDetect) et CStrategy fait le reste |
//| (ExecuteSignal) ; le management intra-position est en API brute   |
//| dans OnTick(). Comme les autres scanners : DORMANT tant que       |
//| K_OPR_Trade = false (greffé != tradé).                            |
//+------------------------------------------------------------------+


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////
// Heures OP en dur, heure SERVEUR (décision utilisateur :
// PAS de DST.mqh — 5ers et NYSE partagent le même DST
// américain, compensation parfaite -> heures fixes toute
// l'année). Source : DST.mqh l.8 + Strategy.mqh BotOPR.
#define OPR_HOUR_START     "16:30"   // ouverture de la bougie du range
#define OPR_HOUR_SESSION   "16:45"   // 1res entrées possibles (= safe_read en M15)
#define OPR_HOUR_END       "18:30"   // fin des entrées + annulation des pendings
#define OPR_HOUR_CLOSE     "22:00"   // clôture forcée des positions

// TF annexes (indicateurs) — le TF de TRAVAIL (bougie du range)
// est l'input K_OPR_TF (M15 par défaut, comme BotOPR K_ORB_TF)
#define OPR_TF_EMA         PERIOD_M5    // EMA20/50 (annexe, BotOPR : M5 en dur)
#define OPR_TF_ST          PERIOD_H1    // SuperTrend (annexe, BotOPR : H1 en dur)

// Indicateur SuperTrend externe (iCustom) : le fichier compilé
// "supertrend.ex5" (minuscules) doit être dans MQL5/Indicators.
// Source au racine du dépôt : supertrend.mq5 (Soltaniyan, MIT).
#define OPR_ST_NAME        "supertrend"

// ATR du filtre de range (BotOPR : iATR(Symbol(), K_ORB_TF, 14))
#define OPR_ATR_PERIOD     14

// TakeWicksIntoAccount passé a true en dur (BotOPR l.165)
#define OPR_ST_WICKS       true

//////////////////////////////////////////////////////////
//                                                      //
//              I N P U T S                             //
//                                                      //
//////////////////////////////////////////////////////////
// Auto-contenus (convention "panier de stratégies") :
// 16 inputs, références BotOPR entre parenthèses.
//============================================
//---   Paramètres SCANNER OPR (BotOPR_001 d'origine)
//============================================
input group              "📁 STRATÉGIE OPR NASDAQ"
input bool               K_OPR_Trade              = false;          // Panier : trader OPR ?
input ENUM_TIMEFRAMES    K_OPR_TF                 = PERIOD_M15;    // TF de la bougie du range (BotOPR : K_ORB_TF)
input uint               K_OPR_EMA_Fast            = 20;            // Période EMA courte M5 (BotOPR : 20)
input uint               K_OPR_EMA_Slow            = 50;            // Période EMA longue M5 (BotOPR : 50)
input uint               K_OPR_ST_Period           = 10;            // Période SuperTrend H1 (BotOPR : 10)
input double             K_OPR_ST_Multiplier       = 3.0;           // Multiplicateur SuperTrend H1 (BotOPR : 3)
input ENUM_APPLIED_PRICE K_OPR_ST_Source           = PRICE_MEDIAN;  // Prix source SuperTrend (BotOPR : median)
input ENUM_OPR_SL_TYPE   K_OPR_SL_Type             = eOprSL_LowHigh;      // Type de SL (BotOPR défaut : LowHigh)
input double             K_OPR_SL_Buffer_Ratio     = 0.10;          // Buffer SL en % de la range (mode LowHighBuffer)
input double             K_OPR_TP_R                = 1.0;           // TP en R (BotOPR : rr 1.0)
input bool               K_OPR_BE                  = true;          // BreakEven actif ? (BotOPR : true)
input double             K_OPR_BE_R                = 0.25;          // Ratio R qui déclenche le BE (BotOPR : 0.25)
input double             K_OPR_BE_Buffer_Points    = 2.0;           // Buffer BE en points x _Point (BotOPR : 2.0)
input double             K_OPR_Offset              = 1.0;           // Offset anti fausse cassure (BRUT en prix, BotOPR : 1.0)
input double             K_OPR_MaxSlippage         = 5.0;           // Slippage max bascule marché (BotOPR : 5.0)
input double             K_OPR_MinRange_ATR_Ratio  = 0.5;           // Range min = X x ATR(14) (BotOPR : 0.5)

//////////////////////////////////////////////////////////
//                                                      //
//              É N U M É R É S                         //
//                                                      //
//////////////////////////////////////////////////////////
// Type de Stop Loss (BotOPR : ENUM_SL_TYPE, BB_ADX_expert.mqh)
enum ENUM_OPR_SL_TYPE
{
    eOprSL_Mid           ,  // Milieu du range
    eOprSL_LowHigh       ,  // Low/High de la range
    eOprSL_LowHighBuffer ,  // Low/High + buffer (% de la range)
};

//////////////////////////////////////////////////////////
//                                                      //
//                 I N C L U D E S                      //
//                                                      //
//////////////////////////////////////////////////////////
#include <Koenigin/Type.mqh>
#include <Koenigin/Log.mqh>
#include <Koenigin/Tools.mqh>


//+------------------------------------------------------------------+
//| EnumOprSlToString                                                 |
//| Libellé du mode SL pour les logs.                                 |
//+------------------------------------------------------------------+
string EnumOprSlToString(const ENUM_OPR_SL_TYPE i_type)
{
    switch (i_type)
    {
        case eOprSL_Mid:           return("Milieu");
        case eOprSL_LowHigh:       return("LowHigh");
        case eOprSL_LowHighBuffer: return("LowHighBuffer");
    }
    return("?");
}

//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CScannerOpr
{
//==================================
//--- PRIVATE
//==================================
private:
    // Identité du scanner
    //---------------------
    string          m_Name;             // Nom logique ("OprScanner") — préfixe du comment d'ordre/position/deal
    ENUM_TIMEFRAMES m_TF;               // TF de travail (K_OPR_TF, bougie du range)

    // Handles d'indicateurs (comme BotOPR Config)
    //----------------------------------------------
    int             m_HandleEMA20;      // EMA rapide (M5)
    int             m_HandleEMA50;      // EMA lente (M5)
    int             m_HandleST;         // SuperTrend (H1, iCustom "supertrend")
    int             m_HandleATR;        // ATR(14) sur K_OPR_TF — filtre de range

    // État journalier (fusion des statiques dupliquées Detection/FindStop BotOPR)
    //-----------------------------------------------------------------------------
    int             m_Day;              // Jour courant déjà initialisé (-1 = jamais)
    datetime        m_Start;            // 16:30 du jour
    datetime        m_SafeRead;         // 16:30 + PeriodSeconds(TF) (16:45 en M15)
    datetime        m_Session;          // 16:45 du jour (1res entrées)
    datetime        m_End;              // 18:30 du jour (fin des entrées)
    datetime        m_Close;            // 22:00 du jour (clôture forcée)
    double          m_RangeHigh;        // High de la bougie du range (0 = pas encore lu)
    double          m_RangeLow;         // Low de la bougie du range (0 = pas encore lu)

    // Verrou journalier mémorisé (fidèle IsPositionOpenedToday BotOPR)
    //-------------------------------------------------------------------
    int             m_LockedDay;        // Jour du dernier reset du verrou
    bool            m_PositionOpened;   // Flag mémorisé "un trade a été pris aujourd'hui"

    //+--------------------------------------------------------+
    //| DailyRefresh                                            |
    //|--------------------------------------------------------|
    //| Reset journalier IDEMPOTENT (partagé TryDetect/OnTick).  |
    //| Fusion des statiques "opr_day" de Detection() BotOPR et  |
    //| de FindStop() (dupliquées, memes valeurs) + du reset du   |
    //| verrou mémorisé dans IsPositionOpenedToday.               |
    //| Les heures sont EN DUR (heure serveur) : 16:30 / 16:45 /  |
    //| 18:30 / 22:00 (décision utilisateur, pas de DST.mqh).     |
    //+--------------------------------------------------------+
    void DailyRefresh(void)
    {
        MqlDateTime dt;
        TimeCurrent(dt);

        if (dt.day == m_Day) return;   // déjà initialisé pour aujourd'hui

        // Nouvelle journée : reset du range + heures du jour
        //-----------------------------------------------------
        m_Day       = dt.day;
        m_RangeHigh = 0.0;
        m_RangeLow  = 0.0;

        string l_Today = TimeToString(TimeCurrent(), TIME_DATE);
        m_Start     = StringToTime(l_Today + " " + OPR_HOUR_START);
        m_SafeRead   = m_Start + PeriodSeconds(m_TF);
        m_Session    = StringToTime(l_Today + " " + OPR_HOUR_SESSION);
        m_End        = StringToTime(l_Today + " " + OPR_HOUR_END);
        m_Close      = StringToTime(l_Today + " " + OPR_HOUR_CLOSE);

        LOG.INFO(m_Name + " : Nouvelle journée | Start="   + TimeToString(m_Start) +
                 " | Session=" + TimeToString(m_Session) +
                 " | End="     + TimeToString(m_End) +
                 " | Close="   + TimeToString(m_Close), __FUNCTION__);
    }

    //+--------------------------------------------------------+
    //| ReadRange                                               |
    //|--------------------------------------------------------|
    //| Lecture du range de la bougie de 16:30, a partir de      |
    //| m_SafeRead (16:45 en M15). SAFE_READ : si CopyHigh/      |
    //| CopyLow échoue -> FALSE = retry au tick suivant (le      |
    //| range n'est jamais marqué lu a moitié : si le high est   |
    //| lu mais pas le low, les deux sont relus — idempotent).   |
    //| Trop tot (< m_SafeRead) -> FALSE sans lecture.           |
    //| Déjà lu -> TRUE.                                         |
    //+--------------------------------------------------------+
    bool ReadRange(void)
    {
        // Trop tôt : la bougie de 16:30 n'est pas clôturée
        //---------------------------------------------------
        if (TimeCurrent() < m_SafeRead) return(false);

        // Déjà mémorisé pour aujourd'hui
        //--------------------------------
        if (m_RangeHigh != 0.0 && m_RangeLow != 0.0) return(true);

        // Lecture (une bougie, celle de 16:30)
        //----------------------------------------
        double l_High[], l_Low[];

        if (CopyHigh(Symbol(), m_TF, m_Start, 1, l_High) == 1)
        {
            m_RangeHigh = l_High[0];
            LOG.INFO(m_Name + " : OPR High enregistré : " + DoubleToString(m_RangeHigh, _Digits), __FUNCTION__);
        }
        else
        {
            LOG.WARNING(m_Name + " : Impossible de lire OPR High — retry au tick suivant", __FUNCTION__);
            return(false);
        }

        if (CopyLow(Symbol(), m_TF, m_Start, 1, l_Low) == 1)
        {
            m_RangeLow = l_Low[0];
            LOG.INFO(m_Name + " : OPR Low enregistré : " + DoubleToString(m_RangeLow, _Digits), __FUNCTION__);
        }
        else
        {
            LOG.WARNING(m_Name + " : Impossible de lire OPR Low — retry au tick suivant", __FUNCTION__);
            return(false);
        }

        return(true);
    }

    //+--------------------------------------------------------+
    //| FindStop                                                |
    //|--------------------------------------------------------|
    //| SL selon K_OPR_SL_TYPE, sur le range DU JOUR (déjà lu    |
    //| par TryDetect — fusion des statiques dupliquées BotOPR,  |
    //| memes valeurs) :                                         |
    //|   Bull : Mid = (h+l)/2 ; LowHigh = low ;                 |
    //|          LowHighBuffer = low - range x ratio              |
    //|   Bear : Mid = (h+l)/2 ; LowHigh = high ;                |
    //|          LowHighBuffer = high + range x ratio             |
    //| Fallback (enum inconnu) = Mid, comme BotOPR.             |
    //+--------------------------------------------------------+
    double FindStop(const ENUM_TREND i_trend)
    {
        double l_Range = m_RangeHigh - m_RangeLow;

        if (i_trend == eT_Bull)
        {
            switch (K_OPR_SL_Type)
            {
                case eOprSL_Mid:           return((m_RangeHigh + m_RangeLow) / 2.0);
                case eOprSL_LowHigh:       return(m_RangeLow);
                case eOprSL_LowHighBuffer: return(m_RangeLow - l_Range * K_OPR_SL_Buffer_Ratio);
            }
        }
        else
        {
            switch (K_OPR_SL_Type)
            {
                case eOprSL_Mid:           return((m_RangeHigh + m_RangeLow) / 2.0);
                case eOprSL_LowHigh:       return(m_RangeHigh);
                case eOprSL_LowHighBuffer: return(m_RangeHigh + l_Range * K_OPR_SL_Buffer_Ratio);
            }
        }
        return((m_RangeHigh + m_RangeLow) / 2.0);   // fallback BotOPR
    }

    //+--------------------------------------------------------+
    //| CheckSuperTrend                                         |
    //|--------------------------------------------------------|
    //| Direction ST (bougie clôturée, shift 1) via buffer 2     |
    //| de l'indicateur iCustom "supertrend" (direction :        |
    //| 1 = haut, -1 = bas — confirmé sur le code source).       |
    //| Échec de lecture -> FALSE + warning (retry global : le    |
    //| tick suivant réévaluera, comme BotOPR).                  |
    //+--------------------------------------------------------+
    bool CheckSuperTrend(ENUM_TREND &io_trend)
    {
        double l_Dir[];

        if (CopyBuffer(m_HandleST, 2, 1, 1, l_Dir) != 1)
        {
            LOG.WARNING(m_Name + " : SuperTrend indisponible", __FUNCTION__);
            return(false);
        }
        ArraySetAsSeries(l_Dir, true);

        if      (l_Dir[0] > 0.0) io_trend = eT_Bull;
        else if (l_Dir[0] < 0.0) io_trend = eT_Bear;
        else                     return(false);   // 0 = pas de tendance (comme BotOPR)

        return(true);
    }

    //+--------------------------------------------------------+
    //| CheckEMA                                                |
    //|--------------------------------------------------------|
    //| EMA rapide/lente (M5, bougie clôturée, shift 1) :        |
    //| rapide > lente = Bull, < = Bear, = = pas de tendance.    |
    //+--------------------------------------------------------+
    bool CheckEMA(ENUM_TREND &io_trend)
    {
        double l_Fast[], l_Slow[];

        if (CopyBuffer(m_HandleEMA20, 0, 1, 1, l_Fast) != 1)
        {
            LOG.WARNING(m_Name + " : EMA20 indisponible", __FUNCTION__);
            return(false);
        }
        if (CopyBuffer(m_HandleEMA50, 0, 1, 1, l_Slow) != 1)
        {
            LOG.WARNING(m_Name + " : EMA50 indisponible", __FUNCTION__);
            return(false);
        }
        ArraySetAsSeries(l_Fast, true);
        ArraySetAsSeries(l_Slow, true);

        if      (l_Fast[0] > l_Slow[0]) io_trend = eT_Bull;
        else if (l_Fast[0] < l_Slow[0]) io_trend = eT_Bear;
        else                            return(false);

        return(true);
    }

    //+--------------------------------------------------------+
    //| IsPositionOpenedToday                                   |
    //|--------------------------------------------------------|
    //| Verrou 1 trade/JOUR, 3 couches (fidèle BotOPR) :          |
    //|  (a) flag mémorisé (reset au changement de jour)         |
    //|  (b) historique des deals du jour : DEAL_ENTRY_IN +      |
    //|      comment "OprScanner" (déviATION vs magic seul —     |
    //|      magic partagé par le panier)                        |
    //|  (c) franchissement du niveau d'un pending OPR           |
    //|      (BUY_STOP : ask >= entry ; SELL_STOP : bid <= entry)|
    //|  (d) position ouverte actuellement (comment OPR)          |
    //| HistorySelect échoue -> FALSE (permissif, comme BotOPR).  |
    //+--------------------------------------------------------+
    bool IsPositionOpenedToday(const MqlTick &i_tick)
    {
        MqlDateTime dt;
        TimeCurrent(dt);

        // Reset du verrou mémorisé au changement de jour
        //--------------------------------------------------
        if (dt.day != m_LockedDay)
        {
            m_LockedDay      = dt.day;
            m_PositionOpened = false;
            LOG.INFO(m_Name + " : Nouveau jour — verrouillage réinitialisé", __FUNCTION__);
        }

        if (m_PositionOpened) return(true);

        // (b) Deals d'entrée du jour
        //-----------------------------
        datetime l_DayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");

        if (!HistorySelect(l_DayStart, TimeCurrent())) return(false);

        int l_Deals = HistoryDealsTotal();
        for (int i = l_Deals - 1; i >= 0; i--)
        {
            ulong l_Ticket = HistoryDealGetTicket(i);

            if (HistoryDealGetString (l_Ticket, DEAL_SYMBOL) != Symbol())              continue;
            if (HistoryDealGetInteger(l_Ticket, DEAL_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (HistoryDealGetInteger(l_Ticket, DEAL_ENTRY)  != DEAL_ENTRY_IN)         continue;
            if (StringFind(HistoryDealGetString(l_Ticket, DEAL_COMMENT), m_Name) < 0)  continue;

            LOG.INFO(m_Name + " : Position ouverte trouvée dans l'historique d'aujourd'hui", __FUNCTION__);
            m_PositionOpened = true;
            return(true);
        }

        // (c) Franchissement du niveau d'un pending OPR
        //-------------------------------------------------
        for (int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = OrderGetTicket(i);

            if (OrderGetString (l_Ticket, ORDER_SYMBOL) != Symbol())              continue;
            if (OrderGetInteger(l_Ticket, ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (StringFind(OrderGetString(l_Ticket, ORDER_COMMENT), m_Name) < 0)   continue;

            double l_Entry = OrderGetDouble (l_Ticket, ORDER_PRICE_OPEN);
            long   l_Type  = OrderGetInteger(l_Ticket, ORDER_TYPE);

            if (l_Type == ORDER_TYPE_BUY_STOP  && i_tick.ask >= l_Entry)
            {
                LOG.INFO(m_Name + " : Cassure OPR détectée — verrouillage journée (BUY)", __FUNCTION__);
                m_PositionOpened = true;
                return(true);
            }
            if (l_Type == ORDER_TYPE_SELL_STOP && i_tick.bid <= l_Entry)
            {
                LOG.INFO(m_Name + " : Cassure OPR détectée — verrouillage journée (SELL)", __FUNCTION__);
                m_PositionOpened = true;
                return(true);
            }
        }

        // (d) Positions ouvertes actuellement
        //---------------------------------------
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = PositionGetTicket(i);

            if (PositionGetString (l_Ticket, POSITION_SYMBOL) != Symbol())              continue;
            if (PositionGetInteger(l_Ticket, POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (StringFind(PositionGetString(l_Ticket, POSITION_COMMENT), m_Name) < 0)  continue;

            LOG.INFO(m_Name + " : Position détectée (ouverte actuellement)", __FUNCTION__);
            m_PositionOpened = true;
            return(true);
        }

        return(false);
    }

    //+--------------------------------------------------------+
    //| HasPendingOrderForSymbol                                |
    //| Un ordre en attente existe-t-il pour CE scanner ?         |
    //| (symbole + magic + comment "OprScanner").                 |
    //+--------------------------------------------------------+
    bool HasPendingOrderForSymbol(void)
    {
        for (int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = OrderGetTicket(i);

            if (OrderGetString (l_Ticket, ORDER_SYMBOL) != Symbol())              continue;
            if (OrderGetInteger(l_Ticket, ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (StringFind(OrderGetString(l_Ticket, ORDER_COMMENT), m_Name) < 0)   continue;

            return(true);
        }
        return(false);
    }

    //+--------------------------------------------------------+
    //| CancelPendingOrders                                     |
    //|--------------------------------------------------------|
    //| Annulation des pendings OPR en API BRUTE (règle maison : |
    //| aucune dépendance DATAS/BROKER — CancelPendingOrder du    |
    //| dépôt filtre par magic+symbole SANS comment et attraperait|
    //| tout le panier). TRADE_ACTION_REMOVE, filtré par comment. |
    //+--------------------------------------------------------+
    void CancelPendingOrders(void)
    {
        for (int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = OrderGetTicket(i);

            if (OrderGetString (l_Ticket, ORDER_SYMBOL) != Symbol())              continue;
            if (OrderGetInteger(l_Ticket, ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (StringFind(OrderGetString(l_Ticket, ORDER_COMMENT), m_Name) < 0)   continue;

            MqlTradeRequest l_Request;
            MqlTradeResult  l_Result;
            ZeroMemory(l_Request);
            ZeroMemory(l_Result);

            l_Request.action = TRADE_ACTION_REMOVE;
            l_Request.order  = l_Ticket;

            ResetLastError();
            if (!OrderSend(l_Request, l_Result))
            {
                LOG.ERROR(m_Name + " : Annulation pending #" + IntegerToString((int)l_Ticket) +
                          " échec : " + ErrorToString(GetLastError()), __FUNCTION__);
            }
            else if (l_Result.retcode == TRADE_RETCODE_DONE         ||
                     l_Result.retcode == TRADE_RETCODE_PLACED        ||
                     l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
                LOG.INFO(m_Name + " : Pending #" + IntegerToString((int)l_Ticket) + " annulé", __FUNCTION__);
            }
            else
            {
                LOG.WARNING(m_Name + " : Annulation pending #" + IntegerToString((int)l_Ticket) +
                            " refusée | Retcode : " + IntegerToString(l_Result.retcode) +
                            " | " + l_Result.comment, __FUNCTION__);
            }
        }
    }

    //+--------------------------------------------------------+
    //| ForceClosePositions                                     |
    //|--------------------------------------------------------|
    //| Clôture forcée des positions OPR (>= 22:00) en API       |
    //| BRUTE : TRADE_ACTION_DEAL au prix courant, volume et      |
    //| sens inversés, garde anti-course (PositionSelectByTicket, |
    //| comme ApplyBreakEven BotOPR).                            |
    //+--------------------------------------------------------+
    void ForceClosePositions(void)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = PositionGetTicket(i);

            if (PositionGetString (l_Ticket, POSITION_SYMBOL) != Symbol())              continue;
            if (PositionGetInteger(l_Ticket, POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (StringFind(PositionGetString(l_Ticket, POSITION_COMMENT), m_Name) < 0)  continue;

            long l_Type = PositionGetInteger(l_Ticket, POSITION_TYPE);

            // Race : la position peut s'être fermée (TP/SL) entre-temps
            //--------------------------------------------------------------
            if (!PositionSelectByTicket(l_Ticket))
            {
                LOG.INFO(m_Name + " : Position #" + IntegerToString((int)l_Ticket) +
                         " déjà fermée (TP/SL atteint) — clôture ignorée", __FUNCTION__);
                continue;
            }

            MqlTradeRequest l_Request;
            MqlTradeResult  l_Result;
            ZeroMemory(l_Request);
            ZeroMemory(l_Result);

            l_Request.action    = TRADE_ACTION_DEAL;
            l_Request.position  = l_Ticket;
            l_Request.symbol    = Symbol();
            l_Request.volume    = PositionGetDouble(l_Ticket, POSITION_VOLUME);
            l_Request.type      = (l_Type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            l_Request.price     = (l_Type == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID)
                                                                : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            l_Request.deviation = I_Deviation;
            l_Request.magic     = K_Magic + I_Robot_ID;
            l_Request.comment   = m_Name + " CLOSE-22H";

            ResetLastError();
            if (!OrderSend(l_Request, l_Result))
            {
                LOG.ERROR(m_Name + " : Clôture forcée #" + IntegerToString((int)l_Ticket) +
                          " échec : " + ErrorToString(GetLastError()), __FUNCTION__);
            }
            else if (l_Result.retcode == TRADE_RETCODE_DONE         ||
                     l_Result.retcode == TRADE_RETCODE_PLACED        ||
                     l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
                LOG.INFO(m_Name + " : Clôture forcée #" + IntegerToString((int)l_Ticket) +
                         " (OPR_Close 22:00)", __FUNCTION__);
            }
            else
            {
                LOG.WARNING(m_Name + " : Clôture forcée #" + IntegerToString((int)l_Ticket) +
                            " refusée | Retcode : " + IntegerToString(l_Result.retcode) +
                            " | " + l_Result.comment, __FUNCTION__);
            }
        }
    }

    //+--------------------------------------------------------+
    //| ApplyBreakEven                                          |
    //|--------------------------------------------------------|
    //| BE fidèle BotOPR (TRADE_ACTION_SLTP brut) :              |
    //|  - garde anti-BE-infini : BUY SL >= open / SELL SL <=     |
    //|    open (et > 0) -> déjà BE, skip                        |
    //|  - risque initial = |open - SL| (0 -> skip)               |
    //|  - ratio = profit / risque ; < K_OPR_BE_R -> pas encore    |
    //|  - BUY : NewSL = open + spread + buffer x _Point ;         |
    //|    SELL : NewSL = open - spread - buffer x _Point          |
    //|  - update seulement si ça AVANCE le SL (jamais reculer)    |
    //|  - garde race : PositionSelectByTicket avant l'envoi       |
    //+--------------------------------------------------------+
    void ApplyBreakEven(const MqlTick &i_tick)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong  l_Ticket = PositionGetTicket(i);

            if (PositionGetString (l_Ticket, POSITION_SYMBOL) != Symbol())              continue;
            if (PositionGetInteger(l_Ticket, POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (StringFind(PositionGetString(l_Ticket, POSITION_COMMENT), m_Name) < 0)  continue;

            double l_OpenPrice    = PositionGetDouble (l_Ticket, POSITION_PRICE_OPEN);
            double l_CurrentSL    = PositionGetDouble (l_Ticket, POSITION_SL);
            double l_CurrentTP    = PositionGetDouble (l_Ticket, POSITION_TP);
            double l_CurrentPrice = PositionGetDouble (l_Ticket, POSITION_PRICE_CURRENT);
            long   l_Type         = PositionGetInteger(l_Ticket, POSITION_TYPE);
            ulong  l_Magic        = PositionGetInteger(l_Ticket, POSITION_MAGIC);
            int    l_Digits       = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

            // Garde anti-BE-infini : SL déjà au-delà de l'entrée
            //------------------------------------------------------
            if (l_Type == POSITION_TYPE_BUY  && l_CurrentSL >= l_OpenPrice)             continue;
            if (l_Type == POSITION_TYPE_SELL && l_CurrentSL <= l_OpenPrice
                                                 && l_CurrentSL >  0.0)                continue;

            double l_InitialRisk = MathAbs(l_OpenPrice - l_CurrentSL);
            if (l_InitialRisk == 0.0) continue;

            double l_CurrentProfit = (l_Type == POSITION_TYPE_BUY) ? (l_CurrentPrice - l_OpenPrice)
                                                                   : (l_OpenPrice - l_CurrentPrice);
            double l_Ratio = l_CurrentProfit / l_InitialRisk;

            // Ratio cible non atteint -> pas encore de BE
            //-----------------------------------------------
            if (l_Ratio < K_OPR_BE_R) continue;

            bool   l_Update = false;
            double l_Spread = i_tick.ask - i_tick.bid;
            double l_Buffer = K_OPR_BE_Buffer_Points * _Point;
            double l_NewSL;

            if (l_Type == POSITION_TYPE_BUY)
            {
                l_NewSL = l_OpenPrice + l_Spread + l_Buffer;
                if (l_CurrentSL < l_NewSL) l_Update = true;
            }
            else
            {
                l_NewSL = l_OpenPrice - l_Spread - l_Buffer;
                if (l_CurrentSL > l_NewSL) l_Update = true;
            }

            LOG.INFO(m_Name + " : BE check | Ratio : "    + DoubleToString(l_Ratio, 2) + "R" +
                     " | Spread : "  + DoubleToString(l_Spread,    l_Digits) +
                     " | Buffer : "  + DoubleToString(l_Buffer,    l_Digits) +
                     " | NewSL : "   + DoubleToString(l_NewSL,     l_Digits) +
                     " | CurrentSL : " + DoubleToString(l_CurrentSL, l_Digits) +
                     " | Update : "  + (l_Update ? "OUI" : "NON"), __FUNCTION__);

            if (!l_Update) continue;

            // Race : la position peut s'être fermée entre-temps
            //-----------------------------------------------------
            if (!PositionSelectByTicket(l_Ticket))
            {
                LOG.INFO(m_Name + " : Position #" + IntegerToString((int)l_Ticket) +
                         " déjà fermée (TP/SL atteint) — BE ignoré", __FUNCTION__);
                continue;
            }

            MqlTradeRequest l_Request;
            MqlTradeResult  l_Result;
            ZeroMemory(l_Request);
            ZeroMemory(l_Result);

            l_Request.action   = TRADE_ACTION_SLTP;
            l_Request.position = l_Ticket;
            l_Request.symbol   = Symbol();
            l_Request.sl       = NormalizeDouble(l_NewSL, l_Digits);
            l_Request.tp       = l_CurrentTP;
            l_Request.magic    = l_Magic;

            ResetLastError();
            if (!OrderSend(l_Request, l_Result))
            {
                LOG.ERROR(m_Name + " : OrderSend BE échec : " + ErrorToString(GetLastError()), __FUNCTION__);
            }
            else if (l_Result.retcode == TRADE_RETCODE_DONE         ||
                     l_Result.retcode == TRADE_RETCODE_PLACED        ||
                     l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
                LOG.INFO(m_Name + " : BE appliqué #" + IntegerToString((int)l_Ticket) +
                         " | Ratio : "      + DoubleToString(l_Ratio, 2) + "R" +
                         " | Nouveau SL : " + DoubleToString(l_NewSL,  l_Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING(m_Name + " : BE refusé #" + IntegerToString((int)l_Ticket) +
                            " | Retcode : " + IntegerToString(l_Result.retcode) +
                            " | " + l_Result.comment, __FUNCTION__);
            }
        }
    }

//==================================
//--- PUBLIC
//==================================
public:

    //+--------------------------------------------------------+
    //| Config                                                  |
    //| Initialise l'état + les 4 handles d'indicateurs          |
    //| (fail-fast, comme BotOPR Config : EMA20/50 M5, SuperTrend |
    //| H1 iCustom "supertrend" [ex5 requis], ATR(14) TF).        |
    //| Validation fail-fast des inputs (pattern maison BB10).    |
    //+--------------------------------------------------------+
    bool Config(const string i_name, const ENUM_TIMEFRAMES i_tf)
    {
        m_Name = i_name;
        m_TF   = i_tf;

        // État journalier (jamais initialisé)
        //--------------------------------------
        m_Day          = -1;
        m_RangeHigh    = 0.0;
        m_RangeLow     = 0.0;
        m_Start        = 0;
        m_SafeRead      = 0;
        m_Session      = 0;
        m_End          = 0;
        m_Close        = 0;

        // Verrou journalier mémorisé
        //-----------------------------
        m_LockedDay      = -1;
        m_PositionOpened = false;

        // Handles
        //----------
        m_HandleEMA20 = INVALID_HANDLE;
        m_HandleEMA50 = INVALID_HANDLE;
        m_HandleST    = INVALID_HANDLE;
        m_HandleATR   = INVALID_HANDLE;

        // ✅ Validation fail-fast des inputs (références BotOPR ; une
        // config invalide ne doit pas dégrader le scanner en silence)
        //----------------------------------------------------------------
        if (K_OPR_EMA_Fast < 1 || K_OPR_EMA_Slow < 1)
        {
            LOG.ERROR(m_Name + " : Périodes EMA invalides (référence BotOPR : 20/50)", __FUNCTION__);
            return(false);
        }
        if (K_OPR_ST_Period < 1)
        {
            LOG.ERROR(m_Name + " : K_OPR_ST_Period invalide (référence BotOPR : 10)", __FUNCTION__);
            return(false);
        }
        if (K_OPR_ST_Multiplier <= 0.0)
        {
            LOG.ERROR(m_Name + " : K_OPR_ST_Multiplier invalide (référence BotOPR : 3.0)", __FUNCTION__);
            return(false);
        }
        if (K_OPR_TP_R <= 0.0)
        {
            LOG.ERROR(m_Name + " : K_OPR_TP_R invalide (référence BotOPR : 1.0)", __FUNCTION__);
            return(false);
        }
        if (K_OPR_BE_R < 0.0)
        {
            LOG.ERROR(m_Name + " : K_OPR_BE_R invalide (référence BotOPR : 0.25)", __FUNCTION__);
            return(false);
        }
        if (K_OPR_MinRange_ATR_Ratio < 0.0)
        {
            LOG.ERROR(m_Name + " : K_OPR_MinRange_ATR_Ratio invalide (référence BotOPR : 0.5)", __FUNCTION__);
            return(false);
        }

        // EMA rapide/lente (M5 — TF annexe en dur, comme BotOPR)
        //----------------------------------------------------------
        m_HandleEMA20 = iMA(Symbol(), OPR_TF_EMA, (int)K_OPR_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
        if (m_HandleEMA20 == INVALID_HANDLE)
        {
            LOG.ERROR(m_Name + " : Impossible d'initialiser l'indicateur EMA20 !!!", __FUNCTION__);
            return(false);
        }
        m_HandleEMA50 = iMA(Symbol(), OPR_TF_EMA, (int)K_OPR_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
        if (m_HandleEMA50 == INVALID_HANDLE)
        {
            LOG.ERROR(m_Name + " : Impossible d'initialiser l'indicateur EMA50 !!!", __FUNCTION__);
            return(false);
        }

        // SuperTrend (H1, iCustom) — le fichier "supertrend.ex5"
        // (minuscules) doit être dans MQL5/Indicators (source au
        // racine du dépôt). Buffer 2 = direction.
        //------------------------------------------------------------
        m_HandleST = iCustom(Symbol(), OPR_TF_ST, OPR_ST_NAME,
                             (int)K_OPR_ST_Period,        // ATRPeriod
                             K_OPR_ST_Multiplier,         // Multiplier
                             K_OPR_ST_Source,             // SourcePrice
                             OPR_ST_WICKS);               // TakeWicksIntoAccount
        if (m_HandleST == INVALID_HANDLE)
        {
            LOG.ERROR(m_Name + " : Impossible d'initialiser l'indicateur SuperTrend !!!" +
                      " Vérifier que supertrend.ex5 est compilé dans MQL5/Indicators", __FUNCTION__);
            return(false);
        }

        // ATR (filtre de range) sur le TF de travail
        //-----------------------------------------------
        m_HandleATR = iATR(Symbol(), m_TF, OPR_ATR_PERIOD);
        if (m_HandleATR == INVALID_HANDLE)
        {
            LOG.ERROR(m_Name + " : Impossible d'initialiser l'indicateur ATR !!!", __FUNCTION__);
            return(false);
        }

        LOG.INFO(m_Name + " : Scanner OPR initialisé (TF="    + PeriodToString(m_TF) +
                 ", EMA "   + IntegerToString((int)K_OPR_EMA_Fast)  + "/" + IntegerToString((int)K_OPR_EMA_Slow) + " M5" +
                 ", ST "    + IntegerToString((int)K_OPR_ST_Period) + "x" + DoubleToString(K_OPR_ST_Multiplier, 1) + " H1" +
                 ", SL="    + EnumOprSlToString(K_OPR_SL_Type) +
                 ", TP_R="  + DoubleToString(K_OPR_TP_R, 2) +
                 ", BE "    + (K_OPR_BE ? "ON" : "OFF") + " à " + DoubleToString(K_OPR_BE_R, 2) + "R)", __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| End                                                     |
    //| Libère les 4 handles (comme BotOPR End).                 |
    //+--------------------------------------------------------+
    void End(void)
    {
        if (m_HandleEMA20 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA20);
        if (m_HandleEMA50 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA50);
        if (m_HandleST    != INVALID_HANDLE) IndicatorRelease(m_HandleST);
        if (m_HandleATR   != INVALID_HANDLE) IndicatorRelease(m_HandleATR);
    }

    //+--------------------------------------------------------+
    //| HasPositionForSymbol                                    |
    //| Une position OUVERTE existe-t-elle pour CE scanner ?      |
    //| (verrou, filtré par comment — couche (d) du verrou        |
    //| journalier ; exposé aussi pour TryOpr si besoin).         |
    //+--------------------------------------------------------+
    bool HasPositionForSymbol(void)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = PositionGetTicket(i);

            if (PositionGetString (l_Ticket, POSITION_SYMBOL) != Symbol())              continue;
            if (PositionGetInteger(l_Ticket, POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
            if (StringFind(PositionGetString(l_Ticket, POSITION_COMMENT), m_Name) < 0)  continue;

            return(true);
        }
        return(false);
    }

    //+--------------------------------------------------------+
    //| TryDetect                                               |
    //|--------------------------------------------------------|
    //| POINT D'ENTRÉE 1 : DÉTECTION (les "15 étapes" du pseudo   |
    //| code validé). Appelé par TryOpr() depuis Detection()      |
    //| panier, APRES les filtres maison NEWS/heures/jours.       |
    //| Flux fidèle Detection() BotOPR, adaptation panier :       |
    //|  1. remise a zéro de o_datas                            |
    //|  2. DailyRefresh (reset journalier + heures en dur)      |
    //|  3. verrou 1 trade/jour : IsPositionOpenedToday          |
    //|     (les couches NEWS/22h du BotOPR sont gérées par le   |
    //|     panier en amont et par OnTick en management)         |
    //|  4. lecture du range (safe_read + retry)                 |
    //|  5. fin de détection >= 18:30 (cancel filet = OnTick)    |
    //|  6. filtre ATR (range >= ratio x ATR ; permissif)        |
    //|  7. lecture ST + EMA (échec -> retry au tick suivant)    |
    //|  8. pending OPR existant : divergence -> annulation      |
    //|     (API brute), puis return (comme BotOPR)              |
    //|  9. position OPR ouverte -> return                       |
    //| 10. convergence ST == EMA exigée                         |
    //| 11. fenêtre [16:45, 18:30) + sens :                      |
    //|     - prix déjà cassé + slippage <= max -> MARCHÉ        |
    //|       (Entry = ask/bid du tick)                          |
    //|     - prix déjà cassé + slippage > max -> abandon        |
    //|     - sinon -> STOP (Entry = high/low + offset)          |
    //|     SL = FindStop, TP = entry ± rr x risque,             |
    //|     IsMarketOrder true/false.                            |
    //| Retourne TRUE + o_datas rempli -> TryOpr appellera       |
    //| ExecuteSignal (sizing MONEY sur Entry PLANNÉ, SetData,   |
    //| BROKER.SendOrder dispatch -> BUY-STOP/SELL-STOP/marché). |
    //| L'"invalidation de dernière minute" BotOPR est couverte  |
    //| par l'étape 10 (code mort défensif — documenté en tête). |
    //+--------------------------------------------------------+
    bool TryDetect(const MqlTick &i_tick, STRUCT_STRATEGY &o_datas)
    {
        // (1)
        ZeroMemory(o_datas);

        // (2) Reset journalier + heures du jour
        //----------------------------------------
        DailyRefresh();

        // (3) Verrou journalier 3 couches
        //----------------------------------
        if (IsPositionOpenedToday(i_tick)) return(false);

        // (4) Lecture du range (trop tôt / échec -> retry)
        //---------------------------------------------------
        if (!ReadRange()) return(false);

        // (5) Fin de détection : >= 18:30
        // (l'annulation des pendings est le "cancel filet" d'OnTick)
        //---------------------------------------------------------------
        if (TimeCurrent() >= m_End) return(false);

        // (6) Filtre ATR — range trop petite
        //--------------------------------------
        if (K_OPR_MinRange_ATR_Ratio > 0.0)
        {
            double l_Atr[];
            if (CopyBuffer(m_HandleATR, 0, 1, 1, l_Atr) == 1)
            {
                double l_Range = m_RangeHigh - m_RangeLow;
                if (l_Range < K_OPR_MinRange_ATR_Ratio * l_Atr[0])
                {
                    LOG.INFO(m_Name + " : Range OPR trop petite (" + DoubleToString(l_Range, _Digits) +
                             ") vs ATR x ratio (" + DoubleToString(K_OPR_MinRange_ATR_Ratio * l_Atr[0], _Digits) +
                             ") — session ignorée", __FUNCTION__);
                    return(false);
                }
            }
            else
            {
                LOG.WARNING(m_Name + " : ATR indisponible — filtre range ignoré", __FUNCTION__);
            }
        }

        // (7) Lecture des tendances ST + EMA
        //--------------------------------------
        ENUM_TREND l_StTrend = eT_Unknown;
        ENUM_TREND l_EmaTrend = eT_Unknown;
        if (!CheckSuperTrend(l_StTrend)) return(false);
        if (!CheckEMA(l_EmaTrend))        return(false);

        // (8) Ordre en attente : validité (divergence -> annulation)
        //--------------------------------------------------------------
        if (HasPendingOrderForSymbol())
        {
            if (l_StTrend != l_EmaTrend)
            {
                LOG.INFO(m_Name + " : Divergence ST/EMA — annulation ordre", __FUNCTION__);
                CancelPendingOrders();
            }
            return(false);
        }

        // (9) Position en cours -> pas de nouvelle détection
        //-----------------------------------------------------
        if (HasPositionForSymbol()) return(false);

        // (10) Convergence obligatoire ST + EMA
        //-----------------------------------------
        if (l_StTrend != l_EmaTrend) return(false);

        // (11) Fenêtre + sens -> MARCHÉ (slippage) ou STOP
        //-----------------------------------------------------
        double l_Offset = K_OPR_Offset;
        double l_Rr     = K_OPR_TP_R;
        bool    l_InWindow = (TimeCurrent() >= m_Session && TimeCurrent() < m_End);

        // === CONTRÔLE SI ACHAT ===
        //---------------------------
        if ((l_StTrend == eT_Bull) && l_InWindow)
        {
            if (i_tick.ask > m_RangeHigh + l_Offset)
            {
                // Prix déjà cassé -> vérification slippage
                //-------------------------------------------
                double l_Slippage = (i_tick.ask - (m_RangeHigh + l_Offset));
                if ((K_OPR_MaxSlippage > 0.0) && (l_Slippage > K_OPR_MaxSlippage))
                {
                    LOG.INFO(m_Name + " : Cassure trop lointaine (" + DoubleToString(l_Slippage, 0) +
                             " pts) > max autorisé (" + DoubleToString(K_OPR_MaxSlippage, 0) +
                             " pts) — abandon", __FUNCTION__);
                    return(false);
                }
                // Slippage acceptable -> bascule ordre au marché
                //--------------------------------------------------
                o_datas.Trend         = eT_Bull;
                o_datas.Entry         = i_tick.ask;
                o_datas.StopLoss      = this.FindStop(eT_Bull);
                o_datas.TakeProfit    = o_datas.Entry + l_Rr * (o_datas.Entry - o_datas.StopLoss);
                o_datas.IsMarketOrder = true;
                LOG.WARNING(m_Name + " : [INSTANT BREAKOUT] Bascule ordre au MARCHÉ | Slippage : " +
                            DoubleToString(l_Slippage, 0) + " pts", __FUNCTION__);
                return(true);
            }
            else
            {
                // Prix pas encore cassé -> ordre stop classique
                //-------------------------------------------------
                o_datas.Trend         = eT_Bull;
                o_datas.Entry         = m_RangeHigh + l_Offset;
                o_datas.StopLoss      = this.FindStop(eT_Bull);
                o_datas.TakeProfit    = o_datas.Entry + l_Rr * (o_datas.Entry - o_datas.StopLoss);
                o_datas.IsMarketOrder = false;
                LOG.INFO(m_Name + " : Détection ACHAT — ordre BUY STOP a poser | Entry=" +
                         DoubleToString(o_datas.Entry, _Digits) +
                         " | SL=" + DoubleToString(o_datas.StopLoss, _Digits) +
                         " | TP=" + DoubleToString(o_datas.TakeProfit, _Digits), __FUNCTION__);
                return(true);
            }
        }

        // === CONTRÔLE SI VENTE ===
        //---------------------------
        if ((l_StTrend == eT_Bear) && l_InWindow)
        {
            if (i_tick.bid < m_RangeLow - l_Offset)
            {
                // Prix déjà cassé -> vérification slippage
                //-------------------------------------------
                double l_Slippage = ((m_RangeLow - l_Offset) - i_tick.bid);
                if ((K_OPR_MaxSlippage > 0.0) && (l_Slippage > K_OPR_MaxSlippage))
                {
                    LOG.INFO(m_Name + " : Cassure trop lointaine (" + DoubleToString(l_Slippage, 0) +
                             " pts) > max autorisé (" + DoubleToString(K_OPR_MaxSlippage, 0) +
                             " pts) — abandon", __FUNCTION__);
                    return(false);
                }
                // Slippage acceptable -> bascule ordre au marché
                //--------------------------------------------------
                o_datas.Trend         = eT_Bear;
                o_datas.Entry         = i_tick.bid;
                o_datas.StopLoss      = this.FindStop(eT_Bear);
                o_datas.TakeProfit    = o_datas.Entry - l_Rr * (o_datas.StopLoss - o_datas.Entry);
                o_datas.IsMarketOrder = true;
                LOG.WARNING(m_Name + " : [INSTANT BREAKOUT] Bascule ordre au MARCHÉ | Slippage : " +
                            DoubleToString(l_Slippage, 0) + " pts", __FUNCTION__);
                return(true);
            }
            else
            {
                // Prix pas encore cassé -> ordre stop classique
                //-------------------------------------------------
                o_datas.Trend         = eT_Bear;
                o_datas.Entry         = m_RangeLow - l_Offset;
                o_datas.StopLoss      = this.FindStop(eT_Bear);
                o_datas.TakeProfit    = o_datas.Entry - l_Rr * (o_datas.StopLoss - o_datas.Entry);
                o_datas.IsMarketOrder = false;
                LOG.INFO(m_Name + " : Détection VENTE — ordre SELL STOP a poser | Entry=" +
                         DoubleToString(o_datas.Entry, _Digits) +
                         " | SL=" + DoubleToString(o_datas.StopLoss, _Digits) +
                         " | TP=" + DoubleToString(o_datas.TakeProfit, _Digits), __FUNCTION__);
                return(true);
            }
        }

        return(false);   // pas de fenêtre / pas de sens
    }

    //+--------------------------------------------------------+
    //| OnTick                                                  |
    //|--------------------------------------------------------|
    //| POINT D'ENTRÉE 2 : MANAGEMENT. Appelé par CStrategy::     |
    //| ManagePositions() a chaque tick + OnTimer 1 s (marché     |
    //| gelé compris). Ordre fidèle BotOPR (ManagePositions +     |
    //| blocs temporels de Detection) :                          |
    //|  1. lecture du tick                                     |
    //|  2. DailyRefresh (heures du jour)                       |
    //|  3. zone NEWS : annulation pendings + BE quand meme,     |
    //|     puis return (priorité absolue)                       |
    //|  4. >= 22:00 : clôture forcée + annulation, return       |
    //|  5. >= 18:30 : cancel filet des pendings (sans return    |
    //|     — le BE continue)                                   |
    //|  6. BreakEven (si K_OPR_BE)                              |
    //|  7. divergence ST/EMA : pending -> annulation            |
    //| Tout en API BRUTE, filtré par comment "OprScanner".      |
    //+--------------------------------------------------------+
    void OnTick(void)
    {
        // (1) Lecture du tick courant
        //------------------------------
        MqlTick l_Tick;
        if (!SymbolInfoTick(Symbol(), l_Tick))
        {
            LOG.WARNING(m_Name + " : ManagePositions — impossible de lire le tick", __FUNCTION__);
            return;
        }

        // (2) Heures du jour
        //---------------------
        DailyRefresh();

        // (3) Zone NEWS : priorité absolue
        //------------------------------------
        if (!PARAM.OutsideSecurityZone())
        {
            if (HasPendingOrderForSymbol())
            {
                LOG.INFO(m_Name + " : Zone NEWS — annulation des ordres en attente", __FUNCTION__);
                CancelPendingOrders();
            }

            // BE actif meme en zone NEWS pour protéger les positions
            //----------------------------------------------------------
            if (K_OPR_BE) ApplyBreakEven(l_Tick);
            return;
        }

        // (4) Clôture forcée a OPR_Close (22:00)
        //------------------------------------------
        if (TimeCurrent() >= m_Close)
        {
            if (HasPositionForSymbol() || HasPendingOrderForSymbol())
            {
                LOG.INFO(m_Name + " : Clôture forcée (OPR_Close) — positions fermées, pendings annulés", __FUNCTION__);
            }
            ForceClosePositions();
            CancelPendingOrders();
            return;
        }

        // (5) >= 18:30 : cancel filet (pendings non exécutés)
        //------------------------------------------------------
        if (TimeCurrent() >= m_End)
        {
            if (HasPendingOrderForSymbol())
            {
                LOG.INFO(m_Name + " : OPR End dépassé — annulation des ordres en attente", __FUNCTION__);
                CancelPendingOrders();
            }
            // pas de return : le BE continue (fidèle ManagePositions BotOPR)
        }

        // (6) BreakEven
        //----------------
        if (K_OPR_BE) ApplyBreakEven(l_Tick);

        // (7) Divergence ST/EMA
        //------------------------
        if (HasPendingOrderForSymbol())
        {
            ENUM_TREND l_StTrend  = eT_Unknown;
            ENUM_TREND l_EmaTrend = eT_Unknown;
            if (!CheckSuperTrend(l_StTrend) || !CheckEMA(l_EmaTrend) || (l_StTrend != l_EmaTrend))
            {
                LOG.INFO(m_Name + " : Divergence ST/EMA (tick) — annulation ordre", __FUNCTION__);
                CancelPendingOrders();
            }
        }
    }

    //+--------------------------------------------------------+
    //| GetNamePublic                                           |
    //+--------------------------------------------------------+
    string GetNamePublic(void) { return(m_Name); }

};  // fin de la classe CScannerOpr

//////////////////////////////////////////////////////////
//                                                      //
//              F O N C T I O N S                       //
//                                                      //

