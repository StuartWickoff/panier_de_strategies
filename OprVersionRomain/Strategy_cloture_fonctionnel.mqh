//+------------------------------------------------------------------+
//|                                                                  |
//| Gérer une stratégie en s'appuyant sur les données                |
//| communes                                                         |
//| (Le code est compatible MT4 et MT5)                              |
//|                                                                  |
//| - Détection d'une opportunité                                    |
//| - Affectation avec un ticket ouvert                              |
//| - Gestion des positions avec les détections                      |
//|                                                                  |
//+------------------------------------------------------------------+
//| Liste  des fonctions : (A compléter avec IA)


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
#include <OPR_Bot/Datas.mqh>
#include <OPR_Bot/DST.mqh>

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
    // Données de la stratégie
    //------------------------
    CDatas        DATAS;
  
    // Données des indicateurs et ORB
    //--------------------------------
    int     m_HandleEMA20;    // Handle EMA20
    int     m_HandleEMA50;    // Handle EMA50
    int     m_HandleST;       // Handle SuperTrend
    int     m_HandleATR;      // Handle ATR (filtre range ORB)
    
    // ✅ MFE/MAE tracking — AJOUT ICI
    //---------------------------------
    STRUCT_MFE_TRACK m_MfeTrack[];
    int              m_MfeCount;    
    int              m_MfeFileHandle;  // ← AJOUT : handle fichier global    
    bool             m_MfeHeaderWritten;  // ← Ajoute ça avec tes autres membres

    // ✅ VARIABLES POUR VERROUILLAGE JOURNALIER
    //-------------------------------------------
    int             m_LockedDay;           // Jour verrouillé
    bool            m_PositionOpened;      // Flag position ouverte
    
    // Données
    //--------
    ENUM_TIMEFRAMES m_Period;
    bool            m_InitOk;

    // Fonctions
    //----------
    double   FindStop(const STRUCT_STRATEGY &i_datas);
    bool     CheckSuperTrend(ENUM_TREND &i_trend);
    bool     CheckEMA(ENUM_TREND &i_trend);
    void     ApplyBreakEven(const MqlTick &i_tick);    
    bool     IsSessionValid(void);
    bool     IsPositionOpenedToday(const MqlTick &i_tick);
    bool     HasPositionForSymbol(void);
    bool     HasPendingOrderForSymbol(void);
    int      FindMFEIdx(const ulong i_ticket);
    
    // ✅ MFE/MAE functions — AJOUT ICI
    //----------------------------------
    void     InitMFETrack(const ulong i_ticket, const double i_entry,
                          const double i_sl, const datetime i_open_time);
    void     UpdateMFE(void);
    void     ExportMFE(const int i_idx);
    void CheckTimeStop(const uint i_time_cut_min, const double i_r_cut); 

//==================================
//--- PUBLIC
//==================================    
public:
    // Fonctions
    //----------
    bool   Config(const string            i_strategy_name,
                  const ENUM_TIMEFRAMES   i_period,
                  const string            i_folder);

    bool   ConfigOk(void) { return(m_InitOk);  }

    void    End(void);

    // Infos venants de l'extérieur
    //-----------------------------
    void    SetTicket(const int i_detection, const int i_Ticket)     { DATAS.SetTicket(i_detection, i_Ticket); }

    // Gestion des données
    //--------------------
    int    GetPositionNb(void)                                      { return(DATAS.GetPositionNb()); }

    void    DeleteDetection(void)                                    { DATAS.DeleteDetection(); }

    void    CloseOfPositions(void)                                   { DATAS.CloseOfPositions(); }

    void    Detection(void);

    void    ManagePositions(void);                                   
};

//+------------------------------------------------------------------+
//| Config                                                           |
//| Initialise l'objet avec la création des indicateurs              |
//| INPUT:                                                           |
//|  Nom de la stratégie                                             |
//|  Période de la stratégie                                         |                                                                 
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
bool CStrategy::Config(const string            i_strategy_name,
                       const ENUM_TIMEFRAMES   i_period,
                       const string            i_folder)
{
    // Initialisation (également des indicateurs)
    //---------------    
    m_InitOk = false;
    m_Period = i_period;    

    // ✅ INITIALISER LE VERROUILLAGE
    //--------------------------------
    m_LockedDay = -1;
    m_PositionOpened = false;    
    
    // ✅ INITIALISER MFE/MAE TRACKING — AJOUT ICI
    //---------------------------------------------
    m_MfeCount = 0;
    ArrayResize(m_MfeTrack, 0);

    // ✅ Ouverture fichier CSV (unique)
    string l_File = K_Repertory + "mfe_export.csv";
    // Dans Config(), remplace tout le bloc FileOpen/FileTell/FileWrite par :
    m_MfeFileHandle = FileOpen(l_File, FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
    if(m_MfeFileHandle == INVALID_HANDLE)
        LOG.ERROR("ExportMFE : FileOpen échec #" + IntegerToString(GetLastError()), __FUNCTION__);
    m_MfeHeaderWritten = false;  // ← L'header sera écrit par ExportMFE()   
    
    // Configure la classe pour les données
    //-------------------------------------
    if (!DATAS.Config(i_strategy_name, i_period, i_folder)) return(false);

    // TODO : Initialisation des spécificités de la stratégie
    //-------------------------------------------------------

    // Initialisation
    //---------------
    m_HandleEMA20  = INVALID_HANDLE;
    m_HandleEMA50  = INVALID_HANDLE;
    m_HandleST     = INVALID_HANDLE; 
    m_HandleATR    = INVALID_HANDLE;      

    // Création des handles pour les indicateurs

    // EMA20 et EMA50 (M5)
    //--------------------
    m_HandleEMA20  = iMA(Symbol(), PERIOD_M5, K_CStrat_EMA_Short, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA20 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA20 !!!", __FUNCTION__);
        return(false);
    }
    m_HandleEMA50 = iMA(Symbol(), PERIOD_M5, K_CStrat_EMA_Long, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA50 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA50 !!!", __FUNCTION__);
        return(false);
    }

    // ✅ SuperTrend v2 (Soltaniyan) - H1
    // Paramètres : ATRPeriod, Multiplier, SourcePrice, TakeWicksIntoAccount
    // IMPORTANT : le fichier doit s'appeler "supertrend.ex5" (minuscules)
    //------------------------------------------------------------------------
    m_HandleST = iCustom(Symbol(), PERIOD_H1, "supertrend",
                         K_CStrat_ST_Period,      // STPeriod
                         K_CStrat_ST_Multiplier,  // Multiplier
                         PRICE_MEDIAN,            // SourcePrice
                         true);                   // TakeWicksIntoAccount
    if (m_HandleST == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur SuperTrend !!!", __FUNCTION__);
        return(false);
    }
    
    // ATR sur K_ORB_TF — filtre de range minimum
   //---------------------------------------------
   m_HandleATR = iATR(Symbol(), K_ORB_TF, 14);
   if (m_HandleATR == INVALID_HANDLE)
   {
       LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur ATR !!!", __FUNCTION__);
       return(false);
   }
    
    // Fin de l'initialisation
    //------------------------
    m_InitOk = true;
    LOG.INFO(DATAS.GetStrategyName() + "Stratégie OPR initialisée", __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------------+
//| End                                                              |
//| Ferme l'objet                                                    |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::End(void)
{ 
// Compte les tracks actifs (remplace ArraysCount pseudo-code)
int l_ActiveCount = 0;
for (int i = 0; i < m_MfeCount; i++)
    if (m_MfeTrack[i].active) l_ActiveCount++;
Print("🔚 END | m_MfeCount=", m_MfeCount, " | Active=", l_ActiveCount);
    // ✅ Exporte les trades restants ouverts à la fin du backtest
    //-----------------------------------------------------------
    for (int i = 0; i < m_MfeCount; i++)
    {
        if (m_MfeTrack[i].active)
        {
            ExportMFE(i);
            m_MfeTrack[i].active = false;
        }
    }
    
    // ✅ Ferme le fichier CSV
    if (m_MfeFileHandle != INVALID_HANDLE)
    {
        FileClose(m_MfeFileHandle);
        m_MfeFileHandle = INVALID_HANDLE;
    }    
 
    // Gère les données de la stratégie
    //---------------------------------
    DATAS.End(); 

    // TODO : Terminaison des spécificités de la stratégie
    //----------------------------------------------------

    if (m_HandleEMA20 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA20);
    if (m_HandleEMA50 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA50);
    if (m_HandleST    != INVALID_HANDLE) IndicatorRelease(m_HandleST);
    if (m_HandleATR   != INVALID_HANDLE) IndicatorRelease(m_HandleATR);
}

//+--------------------------------------------------------------------+
//| Detection                                                          |
//| Analyse la stratégie en cas de nouvelle bougie                     |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |    
//|  None                                                              |
//+--------------------------------------------------------------------+
void CStrategy::Detection(void)
{ 
    // Variables locales
    //------------------
    STRUCT_STRATEGY          l_Datas;
    STRUCT_SYMBOL_CONFIG     l_Config = GetSymbolConfig(I_Symbol_Key);
    int                      l_NoDetection;
    bool                     l_DetectionOk;
    MqlTick                  l_TickData;
    string                   l_Header;
    
    // Initialise le traitement
    //-------------------------
    l_NoDetection = 0;
    l_DetectionOk = false;
    ZeroMemory(l_Datas);

    // Lit les dernières données du marché    
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_TickData)) 
    {
        LOG.WARNING(DATAS.GetStrategyName() + "Lecture des données récentes du marché impossible", __FUNCTION__);
        return;
    }

    // Données et valeurs statiques pour qu'elles ne changent pas à chaque tick
    //-------------------------------------------------------------------------
    static datetime opr_start     = 0;
    static datetime opr_session   = 0;
    static datetime opr_end       = 0;
    static datetime opr_close     = 0;
    static datetime safe_read_time = 0;
    static double   opr_high      = 0.0;
    static double   opr_low       = 0.0;
    static int      opr_day       = -1;   
    MqlDateTime     dt;
    TimeCurrent(dt);    
    
    // On ne rentre ici qu'une seule fois par jour, à minuit (ou au premier tick du jour)
    //-----------------------------------------------------------------------------------
    if (dt.day != opr_day)
    {
        // Reset journalier
        //-----------------
        opr_high = 0.0;
        opr_low  = 0.0;
        opr_day  = dt.day;

        // Récupère les heures OPR dynamiques selon marché + DST
        //-------------------------------------------------------
        int dyn_start_h,   dyn_start_m;
        int dyn_session_h, dyn_session_m;
        int dyn_end_h,     dyn_end_m;
        int dyn_close_h,   dyn_close_m;

        GetOprHours(l_Config.market,
                    dyn_start_h,   dyn_start_m,
                    dyn_session_h, dyn_session_m,
                    dyn_end_h,     dyn_end_m,
                    dyn_close_h,   dyn_close_m);

        // Construction des datetime cibles pour aujourd'hui
        //--------------------------------------------------
        string today_str = TimeToString(TimeCurrent(), TIME_DATE);
        opr_start      = StringToTime(today_str + " " + StringFormat("%02d:%02d", dyn_start_h,   dyn_start_m));
        int tf_seconds = PeriodSeconds(K_ORB_TF);
        safe_read_time = opr_start + tf_seconds;
        opr_session    = StringToTime(today_str + " " + StringFormat("%02d:%02d", dyn_session_h, dyn_session_m));
        opr_end        = StringToTime(today_str + " " + StringFormat("%02d:%02d", dyn_end_h,     dyn_end_m));
        opr_close      = StringToTime(today_str + " " + StringFormat("%02d:%02d", dyn_close_h,   dyn_close_m));

        LOG.INFO("DST | Offset serveur : GMT+" + IntegerToString(GetServerOffset()) +
                 " | EU été : "                + (IsEuropeanSummer() ? "OUI" : "NON"), __FUNCTION__);
        LOG.INFO("Nouvelle journée : OPR Start=" + TimeToString(opr_start) +
                 " | Session=" + TimeToString(opr_session) +
                 " | End="     + TimeToString(opr_end) +
                 " | Close="   + TimeToString(opr_close), __FUNCTION__);
    }

    // ✅ VÉRIFICATION SESSION (Jour + Mois)
    //--------------------------------------
    if (!IsSessionValid())
    {
        if (OrdersTotal() > 0)
        {
            LOG.INFO("Session invalide - Annulation des ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }       

    // ✅ VÉRIFICATION : Une position est-elle ouverte aujourd'hui ?
    //-------------------------------------------------------------
    if (IsPositionOpenedToday(l_TickData))
    {
        return;
    }

    // ✅ VÉRIFICATION ZONE NEWS
    //-------------------------
    if (!PARAM.OutsideSecurityZone())
    {
        if (HasPendingOrderForSymbol())
        {
           LOG.INFO("🔴 Zone NEWS - Annulation des ordres en attente", __FUNCTION__);
           DATAS.CancelPendingOrder();
        }
        return;
    }
        
    // Clôture forcée à OPR_Close
    //---------------------------
    if (TimeCurrent() >= opr_close)
    {
        if (PositionsTotal() > 0)
        {
            LOG.INFO("Clôture forcée des positions : OPR_Close", __FUNCTION__);
            DATAS.CloseOfPositions();            
        }
        DATAS.CancelPendingOrder();
        return;
    }

    // Logique de récupération de l'OPR high et low
    //----------------------------------------------
    if (TimeCurrent() >= safe_read_time)
    {
        if (opr_high == 0.0 || opr_low == 0.0)
        {
            double high_buf[], low_buf[];
            
            if (CopyHigh(Symbol(), K_ORB_TF, opr_start, 1, high_buf) == 1) 
            {
                opr_high = high_buf[0];
                LOG.INFO("OPR High enregistré: " + DoubleToString(opr_high, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR High", __FUNCTION__);
                return;
            }
            
            if (CopyLow(Symbol(), K_ORB_TF, opr_start, 1, low_buf) == 1) 
            {
                opr_low = low_buf[0];
                LOG.INFO("OPR Low enregistré: " + DoubleToString(opr_low, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR Low", __FUNCTION__);
                return;
            }
        }
    }
    else
    {
        return;  // Trop tôt
    }

    // Annulation des ordres non exécutés après OPR_End
    //--------------------------------------------------
    if (TimeCurrent() >= opr_end)
    {
        if (OrdersTotal() > 0)
        {
            LOG.INFO("OPR - End dépassé - Annulation ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }
    
    // Après le bloc qui lit opr_high et opr_low, avant "=== ANALYSE INDICATEURS ==="
   // Filtre ATR — range ORB trop petite
   //------------------------------------
   if (K_MinRange_ATR_Ratio > 0.0)
   {
       double atr_buf[];
       if (CopyBuffer(m_HandleATR, 0, 1, 1, atr_buf) == 1)
       {
           double range = opr_high - opr_low;
           double atr   = atr_buf[0];
           if (range < K_MinRange_ATR_Ratio * atr)
           {
               LOG.INFO("Range ORB trop petite (" + DoubleToString(range, _Digits) +
                        ") vs ATR×ratio ("        + DoubleToString(K_MinRange_ATR_Ratio * atr, _Digits) +
                        ") - Session ignorée", __FUNCTION__);
               return;
           }
       }
       else
       {
           LOG.WARNING("ATR indisponible - filtre range ignoré", __FUNCTION__);
       }
   }

    // === ANALYSE INDICATEURS ===
    //----------------------------
    ENUM_TREND st_trend  = eT_Unknown;
    ENUM_TREND ema_trend = eT_Unknown;
    
    if (!CheckSuperTrend(st_trend)) return;
    if (!CheckEMA(ema_trend)) return;

    // SI ORDRE EN ATTENTE, VÉRIFIER VALIDITÉ
    //----------------------------------------
    if (HasPendingOrderForSymbol())
    {
        if (st_trend != ema_trend)
        {
            LOG.INFO("Divergence ST/EMA - Annulation ordre", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }

    // Analyse OPR (seulement si pas de trade en cours)
    //-------------------------------------------------
    if (HasPositionForSymbol()) return; 

    // Convergence obligatoire ST + EMA
    //---------------------------------
    if (st_trend != ema_trend) return;

    // Offset anti fausse cassure (issu de la config actif)
    //------------------------------------------------------
    double offset = l_Config.offset_points;

    //--------------------
    // Contrôle si achat
    //--------------------
    if ((st_trend == eT_Bull) && (TimeCurrent() >= opr_session) && (TimeCurrent() < opr_end))
    {
        if (K_UseLimitEntry)
        {
            // Après le bloc if (opr_high == 0.0 || opr_low == 0.0) complet
            double opr_mid = (opr_high + opr_low) / 2.0;
            // LIMIT : entrée au mid, on vérifie que le prix n'est pas déjà passé sous le mid
            if (l_TickData.bid < opr_mid)
            {
                LOG.INFO("BUY LIMIT : prix déjà sous le mid — entrée manquée", __FUNCTION__);
                return;
            }
            l_NoDetection              = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend              = eT_Bull;
            l_Datas.Entry              = opr_mid;
            l_Datas.StopLoss = opr_low - (opr_high - opr_low) * K_SL_Buffer_Ratio;
            double rr                  = (K_TP_Override > 0) ? K_TP_Override : l_Config.risk_reward;
            l_Datas.TakeProfit         = l_Datas.Entry + rr * (l_Datas.Entry - l_Datas.StopLoss);
            l_DetectionOk              = true;
            LOG.INFO("Ordre BUY LIMIT placé au mid : " + DoubleToString(opr_mid, _Digits), __FUNCTION__);
        }
        else
        {
            // STOP : logique originale
            if (l_TickData.ask > opr_high + offset)
            {
                LOG.INFO("Range OPR déjà cassé par le haut", __FUNCTION__);
                return;
            }
            l_NoDetection              = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend              = eT_Bull;
            l_Datas.Entry              = opr_high + offset;
            l_Datas.StopLoss           = this.FindStop(l_Datas);
            double rr                  = (K_TP_Override > 0) ? K_TP_Override : l_Config.risk_reward;
            l_Datas.TakeProfit         = l_Datas.Entry + rr * (l_Datas.Entry - l_Datas.StopLoss);
            l_DetectionOk              = true;
            LOG.INFO("Ordre BUY STOP placé", __FUNCTION__);
        }
    }

    //--------------------
    // Contrôle si vente
    //--------------------    
    else if ((st_trend == eT_Bear) && (TimeCurrent() >= opr_session) && (TimeCurrent() < opr_end))
    {
        if (K_UseLimitEntry)
        {
            // Après le bloc if (opr_high == 0.0 || opr_low == 0.0) complet
            double opr_mid = (opr_high + opr_low) / 2.0;        
            // LIMIT : entrée au mid, on vérifie que le prix n'est pas déjà passé au-dessus du mid
            if (l_TickData.ask > opr_mid)
            {
                LOG.INFO("SELL LIMIT : prix déjà au-dessus du mid — entrée manquée", __FUNCTION__);
                return;
            }
            l_NoDetection              = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend              = eT_Bear;
            l_Datas.Entry              = opr_mid;
            l_Datas.StopLoss = opr_high + (opr_high - opr_low) * K_SL_Buffer_Ratio;
            double rr                  = (K_TP_Override > 0) ? K_TP_Override : l_Config.risk_reward;
            l_Datas.TakeProfit         = l_Datas.Entry - rr * (l_Datas.StopLoss - l_Datas.Entry);
            l_DetectionOk              = true;
            LOG.INFO("Ordre SELL LIMIT placé au mid : " + DoubleToString(opr_mid, _Digits), __FUNCTION__);
        }
        else
        {
            // STOP : logique originale
            if (l_TickData.bid < opr_low - offset)
            {
                LOG.INFO("Range OPR déjà cassé par le bas", __FUNCTION__);
                return;
            }
            l_NoDetection              = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend              = eT_Bear;
            l_Datas.Entry              = opr_low - offset;
            l_Datas.StopLoss           = this.FindStop(l_Datas);
            double rr                  = (K_TP_Override > 0) ? K_TP_Override : l_Config.risk_reward;
            l_Datas.TakeProfit         = l_Datas.Entry - rr * (-l_Datas.Entry + l_Datas.StopLoss);
            l_DetectionOk              = true;
            LOG.INFO("Ordre SELL STOP placé", __FUNCTION__);
        }
    }
    // Gère les paramètres de la détection
    //--------------------------------------
    if (l_DetectionOk)
    {        
        l_Datas.Size = MONEY.CalculateLotSize(l_Datas);

        if (l_Datas.Size <= 0.0)
        {
            LOG.WARNING("Taille de lot invalide", __FUNCTION__);
            return;
        }

        l_Header = LOG.InfosLogOperation(DATAS.GetStrategyName(), l_Datas.No_detection, Symbol());
        LOG.INFO(l_Header +
                 " : Opportunité " + TrendToString(l_Datas.Trend) +
                 " : Taille = "    + DoubleToString(l_Datas.Size,       MONEY.GetDigitLot()) +
                 " , Entry = "     + DoubleToString(l_Datas.Entry,      Digits()) +
                 " , SL = "        + DoubleToString(l_Datas.StopLoss,   Digits()) +
                 " , TP = "        + DoubleToString(l_Datas.TakeProfit, Digits()), __FUNCTION__);

        DATAS.SetData(l_NoDetection, l_Datas);

        // Invalidation de dernière minute
        //--------------------------------
        if (st_trend != ema_trend)
        {
            LOG.INFO(" Invalidation immédiate - ST != EMA", __FUNCTION__);
            return;
        }
        BROKER.SendOrder(DATAS.GetStrategyName(), l_Datas);
    }    
}

//+------------------------------------------------------------------+
//| ManagePositions                                                  |
//| Appelée à chaque tick depuis OnTick()                            |
//| Gère dans l'ordre :                                              |
//|  1. Zone NEWS  → annulation immédiate des ordres en attente      |
//|  2. BreakEven  → déplacement du SL si ratio atteint              |
//|  3. Divergence ST/EMA → annulation si conditions invalides       |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ManagePositions(void)
{
    // Variables locales
    //------------------
    MqlTick              l_Tick;
    STRUCT_SYMBOL_CONFIG l_Config    = GetSymbolConfig(I_Symbol_Key);
    ENUM_TREND           l_StTrend   = eT_Unknown;
    ENUM_TREND           l_EmaTrend  = eT_Unknown;

    // Lecture du tick courant
    //------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("ManagePositions : Impossible de lire le tick", __FUNCTION__);
        return;
    }
    
    // 1. ZONE NEWS : Priorité absolue
    //--------------------------------
    if (!PARAM.OutsideSecurityZone())
    {
        if (HasPendingOrderForSymbol())
        {
            LOG.INFO("🔴 Zone NEWS (tick) - Annulation immédiate des ordres", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }

        // BE actif même en zone NEWS pour protéger les positions ouvertes
        //-----------------------------------------------------------------
        if (l_Config.apply_be)
        {
            ApplyBreakEven(l_Tick);
        }
        return;
    }

    // ✅ 1. MISE À JOUR DU TRACKING D'ABORD
    UpdateMFE();

    // ✅ 2. PUIS LES DÉCISIONS (BE, Time-stop)
    if (l_Config.apply_be) ApplyBreakEven(l_Tick);
    CheckTimeStop(K_TimeStop_Minutes, K_TimeStop_R_Max);    

    // 2. BREAKEVEN
    //-------------
    if (l_Config.apply_be)
    {
        ApplyBreakEven(l_Tick);
    }

    // ✅ 3. TIME-STOP (paramétrable)
    //--------------------------------
    CheckTimeStop(K_TimeStop_Minutes, K_TimeStop_R_Max);
    
    // 4. DIVERGENCE ST/EMA (une seule fois !)
    //---------------------
    if (HasPendingOrderForSymbol())
    {
        if (!CheckSuperTrend(l_StTrend) || !CheckEMA(l_EmaTrend) || (l_StTrend != l_EmaTrend))
        {
            LOG.INFO("⚡ Divergence ST/EMA (tick) - Annulation ordre", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
    }
}

//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////

//+------------------------------------------------------------------+
//| IsPositionOpenedToday                                            |
//| Détecte si une position est ouverte, verrouille si oui           |
//| INPUT:                                                           |
//|  i_tick : tick courant                                           |
//| OUTPUT:                                                          |
//|  TRUE si position déjà ouverte aujourd'hui                       |
//+------------------------------------------------------------------+
bool CStrategy::IsPositionOpenedToday(const MqlTick &i_tick)
{
    MqlDateTime dt;
    TimeCurrent(dt);
    
    // Reset à minuit
    if (dt.day != m_LockedDay)
    {
        m_LockedDay = dt.day;
        m_PositionOpened = false;
        LOG.INFO("✅ Nouveau jour - Verrouillage réinitialisé", __FUNCTION__);
    }
    
    if (m_PositionOpened) return(true);
    
    // 1. Vérifie les positions OUVERTES
    //----------------------------------
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_MAGIC) != (K_Magic + I_Robot_ID)) continue;
        
        LOG.INFO("🔒 Position détectée (ouverte) | #" + IntegerToString(l_Ticket), __FUNCTION__);
        m_PositionOpened = true;

        // Tracking immédiat
        // APRÈS — SL original via historique de l'ordre
        double   l_OriginalSL  = 0;
        double   l_EntryPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
        datetime l_OpenTime    = (datetime)PositionGetInteger(POSITION_TIME);
         
        if (HistorySelectByPosition(l_Ticket))
        {
            for (int d = 0; d < HistoryDealsTotal(); d++)
            {
                ulong l_DTicket = HistoryDealGetTicket(d);
                if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(l_DTicket, DEAL_ENTRY) != DEAL_ENTRY_IN)
                    continue;
         
                ulong l_OrderTicket = (ulong)HistoryDealGetInteger(l_DTicket, DEAL_ORDER);
                if (HistoryOrderSelect(l_OrderTicket))
                    l_OriginalSL = HistoryOrderGetDouble(l_OrderTicket, ORDER_SL);
                break;
            }
        }
        
        if (l_OriginalSL > 0)
            InitMFETrack(l_Ticket, l_EntryPrice, l_OriginalSL, l_OpenTime);
        else
            LOG.WARNING("SL original introuvable #" + IntegerToString(l_Ticket) +
                        " — MFE ignoré", __FUNCTION__);
        return(true);
    }

    // 2. Vérifie l'HISTORIQUE du jour
    //---------------------------------
    datetime day_start = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
    if (HistorySelect(day_start, TimeCurrent()))
    {
        for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
            ulong l_DealTicket = HistoryDealGetTicket(i);
            if (HistoryDealGetString(l_DealTicket, DEAL_SYMBOL) != Symbol()) continue;
            if (HistoryDealGetInteger(l_DealTicket, DEAL_MAGIC) != (K_Magic + I_Robot_ID)) continue;
            if (HistoryDealGetInteger(l_DealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;

            LOG.INFO("🔒 Trade trouvé dans l'historique | Deal#" + IntegerToString(l_DealTicket), __FUNCTION__);
            m_PositionOpened = true;

            ulong l_PosTicket = (ulong)HistoryDealGetInteger(l_DealTicket, DEAL_POSITION_ID);
            double l_Entry = HistoryDealGetDouble(l_DealTicket, DEAL_PRICE);
            datetime l_Time = (datetime)HistoryDealGetInteger(l_DealTicket, DEAL_TIME);
            
            // Récupération du SL via l'ordre parent OU fallback position
            double l_SL = 0;
            ulong l_OrderTicket = (ulong)HistoryDealGetInteger(l_DealTicket, DEAL_ORDER);
            
            // Méthode 1 : via l'ordre historique
            if(HistoryOrderSelect(l_OrderTicket))
            {
                l_SL = HistoryOrderGetDouble(l_OrderTicket, ORDER_SL);
            }
            else
            {
                // Méthode 2 (fallback) : via la position si encore accessible
                if(PositionSelectByTicket(l_PosTicket))
                {
                    l_SL = PositionGetDouble(POSITION_SL);
                    LOG.INFO("📊 SL récupéré via PositionSelect (fallback) | #" + IntegerToString(l_PosTicket), __FUNCTION__);
                }
                else
                {
                    // Méthode 3 (dernier recours) : estimer le SL depuis l'entry + config
                    STRUCT_SYMBOL_CONFIG cfg = GetSymbolConfig(I_Symbol_Key);
                    double rr = (K_TP_Override > 0) ? K_TP_Override : cfg.risk_reward;
                    // Hypothèse : SL = entry ± (TP-entry)/rr → approximation grossière
                    // À éviter si possible, mais mieux que 0
                    LOG.WARNING("⚠️ SL introuvable pour #" + IntegerToString(l_PosTicket) + " — MFE ignoré", __FUNCTION__);
                }
            }
            
            // Initialisation du tracking (seulement si SL valide)
            if(l_SL > 0)
                InitMFETrack(l_PosTicket, l_Entry, l_SL, l_Time);
            else
                LOG.WARNING("📊 MFE ignoré : SL=0 pour #" + IntegerToString(l_PosTicket), __FUNCTION__);
            return(true);  // ← ICI, pas dans la boucle de InitMFETrack            
        }
    }
    
    return(false);
}
//+------------------------------------------------------------------+
//| IsSessionValid                                                   |
//| Vérifie si le jour et le mois sont valides pour trader           |
//| La configuration est lue depuis GetSymbolConfig()                |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si le jour et le mois sont valides                         |
//+------------------------------------------------------------------+
bool CStrategy::IsSessionValid(void)
{
    STRUCT_SYMBOL_CONFIG l_Config = GetSymbolConfig(I_Symbol_Key);
    MqlDateTime          l_Dt;
    TimeCurrent(l_Dt);

    // Vérification des mois exclus
    //------------------------------
    for (int i = 0; i < l_Config.nb_excl_months; i++)
    {
        if (l_Dt.mon == l_Config.excluded_months[i]) return(false);
    }

    // Vérification des jours exclus
    //-------------------------------
    for (int i = 0; i < l_Config.nb_excl_days; i++)
    {
        if (l_Dt.day_of_week == l_Config.excluded_days[i]) return(false);
    }

    return(true);
}

//+------------------------------------------------------------------+
//| HasPositionForSymbol                                             |
//| Détecte si une position est ouverte pour l'actif                 |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si une position est ouverte                                |
//+------------------------------------------------------------------+
bool CStrategy::HasPositionForSymbol(void)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL)  != Symbol())              continue;
        if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| HasPendingOrderForSymbol                                         |
//| Détecte si un ordre est en attente pour l'actif                  |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si un ordre est en attente                                 |
//+------------------------------------------------------------------+
bool CStrategy::HasPendingOrderForSymbol(void)
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = OrderGetTicket(i);
        if (OrderGetString(ORDER_SYMBOL)  != Symbol())              continue;
        if (OrderGetInteger(ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| FindStop                                                         |
//| Calcule le stop loss (milieu du range OPR)                       |
//| INPUT:                                                           |
//|  i_datas : données de la détection                               |
//| OUTPUT:                                                          |
//|  Prix du stop loss (milieu du range OPR)                         |
//+------------------------------------------------------------------+
double CStrategy::FindStop(const STRUCT_STRATEGY &i_datas)
{
    static datetime opr_start      = 0;
    static datetime safe_read_time = 0;
    static double   opr_high       = 0.0;
    static double   opr_low        = 0.0;
    static int      opr_day        = -1;

    MqlDateTime dt;
    TimeCurrent(dt);

    if (dt.day != opr_day)
    {
        opr_high = 0.0;
        opr_low  = 0.0;
        opr_day  = dt.day;

        // Récupère uniquement start_h/m (FindStop n'a besoin que de opr_start)
        //-----------------------------------------------------------------------
        STRUCT_SYMBOL_CONFIG l_Config = GetSymbolConfig(I_Symbol_Key);
        int dyn_start_h,  dyn_start_m;
        int dyn_dummy_h,  dyn_dummy_m;

        GetOprHours(l_Config.market,
                    dyn_start_h,  dyn_start_m,
                    dyn_dummy_h,  dyn_dummy_m,
                    dyn_dummy_h,  dyn_dummy_m,
                    dyn_dummy_h,  dyn_dummy_m);

        string today_str   = TimeToString(TimeCurrent(), TIME_DATE);
        opr_start          = StringToTime(today_str + " " + StringFormat("%02d:%02d", dyn_start_h, dyn_start_m));
        int tf_seconds = PeriodSeconds(K_ORB_TF);
        safe_read_time = opr_start + tf_seconds;

        LOG.INFO("FindStop | Nouvelle journée : OPR Start=" + TimeToString(opr_start), __FUNCTION__);
    }

    if (TimeCurrent() >= safe_read_time)
    {
        if (opr_high == 0.0 || opr_low == 0.0)
        {
            double high_buf[], low_buf[];

            if (CopyHigh(Symbol(), K_ORB_TF, opr_start, 1, high_buf) == 1) 
            {
                opr_high = high_buf[0];
                LOG.INFO("OPR High enregistré: " + DoubleToString(opr_high, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR High", __FUNCTION__);
            }
            
            if (CopyLow(Symbol(), K_ORB_TF, opr_start, 1, low_buf) == 1) 
            {
                opr_low = low_buf[0];
                LOG.INFO("OPR Low enregistré: " + DoubleToString(opr_low, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR Low", __FUNCTION__);
            }                        
        }
    }

    // Retourne le milieu de range comme stop loss
    //---------------------------------------------
    double range = opr_high - opr_low;

   if (i_datas.Trend == eT_Bull)
   {
       switch(K_SL_Type)
       {
           case eSL_Mid:           return((opr_high + opr_low) / 2.0);
           case eSL_LowHigh:       return(opr_low);
           case eSL_LowHighBuffer: return(opr_low - range * K_SL_Buffer_Ratio);
       }
   }
   else
   {
       switch(K_SL_Type)
       {
           case eSL_Mid:           return((opr_high + opr_low) / 2.0);
           case eSL_LowHigh:       return(opr_high);
           case eSL_LowHighBuffer: return(opr_high + range * K_SL_Buffer_Ratio);
       }
   }
   return((opr_high + opr_low) / 2.0); // fallback
}

//+------------------------------------------------------------------+
//| CheckSuperTrend                                                  |
//| Vérifie direction ST (bougie clôturée)                           |
//| INPUT:                                                           |
//|  i_trend : tendance détectée (par référence)                     |
//| OUTPUT:                                                          |
//|  TRUE si on a une tendance de la ST                              |
//+------------------------------------------------------------------+
bool CStrategy::CheckSuperTrend(ENUM_TREND &i_trend)
{
    double st_direction[];

    if (CopyBuffer(m_HandleST, 2, 1, 1, st_direction) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "SuperTrend indisponible", __FUNCTION__);
        return(false);
    }    
    ArraySetAsSeries(st_direction, true);

    if      (st_direction[0] > 0.0) i_trend = eT_Bull;
    else if (st_direction[0] < 0.0) i_trend = eT_Bear;
    else                            return(false);

    return(true);
}

//+------------------------------------------------------------------+
//| Retourne l'index du tracking pour un ticket (-1 si absent)       |
//+------------------------------------------------------------------+
int CStrategy::FindMFEIdx(const ulong i_ticket)
{
   for(int i=0; i<m_MfeCount; i++)
      if(m_MfeTrack[i].ticket == i_ticket && m_MfeTrack[i].active) return(i);
   return(-1);
}

//+------------------------------------------------------------------+
//| CheckEMA                                                         |
//| Vérifie EMA20 vs EMA50 (bougie clôturée)                         |
//| INPUT:                                                           |
//|  i_trend : tendance détectée (par référence)                     |
//| OUTPUT:                                                          |
//|  TRUE si on a une tendance sur les EMAs                          |
//+------------------------------------------------------------------+
bool CStrategy::CheckEMA(ENUM_TREND &i_trend)
{
    double ema20[];
    double ema50[];

    if (CopyBuffer(m_HandleEMA20, 0, 1, 1, ema20) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA20 indisponible", __FUNCTION__);
        return(false);
    }    
    if (CopyBuffer(m_HandleEMA50, 0, 1, 1, ema50) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA50 indisponible", __FUNCTION__);
        return(false);
    }    
    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);

    if      (ema20[0] > ema50[0]) i_trend = eT_Bull;
    else if (ema20[0] < ema50[0]) i_trend = eT_Bear;
    else                          return(false);

    return(true);
}

//+------------------------------------------------------------------+
//| ApplyBreakEven                                                   |
//| Déplace le SL au niveau du prix d'entrée + buffer                |
//| dès que le ratio cible est atteint                               |
//| INPUT:                                                           |
//|  i_tick : tick courant (pour le spread)                          |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ApplyBreakEven(const MqlTick &i_tick)
{
    // Variables locales
    //------------------
    STRUCT_SYMBOL_CONFIG l_Config = GetSymbolConfig(I_Symbol_Key);
    MqlTradeRequest      l_Request;
    MqlTradeResult       l_Result;
    ulong    l_Ticket;
    ulong    l_Magic;
    string   l_Symbol;
    double   l_OpenPrice;
    double   l_CurrentSL;
    double   l_CurrentTP;
    double   l_CurrentPrice;
    double   l_CurrentProfit;
    double   l_Ratio;
    double   l_InitialRisk;
    double   l_NewSL;
    double   l_Point;
    double   l_Spread;
    double   l_Buffer;
    bool     l_Update;
    long     l_Type;
    int      l_Digits;     

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        l_Ticket = PositionGetTicket(i);
        l_Symbol = PositionGetString(POSITION_SYMBOL);
        
        if (l_Symbol != Symbol())                                          continue;
        if (PositionGetInteger(POSITION_MAGIC) != (K_Magic + I_Robot_ID)) continue;

        l_OpenPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
        l_CurrentSL    = PositionGetDouble(POSITION_SL);
        l_CurrentTP    = PositionGetDouble(POSITION_TP);
        l_CurrentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        l_Type         = PositionGetInteger(POSITION_TYPE);
        l_Magic        = PositionGetInteger(POSITION_MAGIC);
        l_Digits       = (int)SymbolInfoInteger(l_Symbol, SYMBOL_DIGITS);
        l_Point        = SymbolInfoDouble(l_Symbol, SYMBOL_POINT);
        
        // ✅ FIX BE INFINI : SL déjà au-delà du prix d'entrée → BE déjà appliqué
        //------------------------------------------------------------------------
        if (l_Type == POSITION_TYPE_BUY  && l_CurrentSL >= l_OpenPrice)           continue;
        if (l_Type == POSITION_TYPE_SELL && l_CurrentSL <= l_OpenPrice
                                         && l_CurrentSL >  0.0)                   continue;

        l_InitialRisk = MathAbs(l_OpenPrice - l_CurrentSL);
        if (l_InitialRisk == 0) continue;

        if (l_Type == POSITION_TYPE_BUY)
            l_CurrentProfit = l_CurrentPrice - l_OpenPrice;
        else
            l_CurrentProfit = l_OpenPrice - l_CurrentPrice;
        
        l_Ratio = l_CurrentProfit / l_InitialRisk;

        // Ratio cible non atteint → pas encore de BE
        //--------------------------------------------
        double be_ratio = (K_BE_Override > 0) ? K_BE_Override : l_Config.breakeven_r;
        if (l_Ratio < be_ratio) continue;
        
        l_Update = false;
        l_Spread = i_tick.ask - i_tick.bid;
        l_Buffer = l_Config.buffer_be * l_Point;
                    
        if (l_Type == POSITION_TYPE_BUY)
        {
            l_NewSL = l_OpenPrice + l_Spread + (l_Config.buffer_be * 0.01);
            if (l_CurrentSL < l_NewSL) l_Update = true;
        }
        else
        {
            l_NewSL = l_OpenPrice - l_Spread - (l_Config.buffer_be * 0.01);
            if (l_CurrentSL > l_NewSL) l_Update = true;
        }
         
        LOG.INFO("🔍 BE check | " + l_Symbol +
                 " | Ratio : "     + DoubleToString(l_Ratio,      2) + "R" +
                 " | Spread : "    + DoubleToString(l_Spread,      l_Digits) +
                 " | Buffer : "    + DoubleToString(l_Buffer,      l_Digits) +
                 " | NewSL : "     + DoubleToString(l_NewSL,       l_Digits) +
                 " | CurrentSL : " + DoubleToString(l_CurrentSL,   l_Digits) +
                 " | Update : "    + (l_Update ? "OUI" : "NON"), __FUNCTION__);         

        if (!l_Update) continue;

        ZeroMemory(l_Request);
        ZeroMemory(l_Result);

        l_Request.action   = TRADE_ACTION_SLTP;
        l_Request.position = l_Ticket;
        l_Request.symbol   = l_Symbol;
        l_Request.sl       = NormalizeDouble(l_NewSL, l_Digits);
        l_Request.tp       = l_CurrentTP;
        l_Request.magic    = l_Magic;

        ResetLastError();
        if (!OrderSend(l_Request, l_Result))
        {
            LOG.ERROR("OrderSend BE échec : " + ErrorToString(GetLastError()), __FUNCTION__);
        }
        else
        {
            if (l_Result.retcode == TRADE_RETCODE_DONE         ||
                l_Result.retcode == TRADE_RETCODE_PLACED        ||
                l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
                LOG.INFO("✅ BE appliqué #" + IntegerToString(l_Ticket) +
                         " | Ratio : "       + DoubleToString(l_Ratio,  2) + "R" +
                         " | Nouveau SL : "  + DoubleToString(l_NewSL,  l_Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("⚠️ BE refusé #"  + IntegerToString(l_Ticket) +
                            " | Retcode : "   + IntegerToString(l_Result.retcode) +
                            " | "             + l_Result.comment, __FUNCTION__);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| InitMFETrack                                                     |
//+------------------------------------------------------------------+
void CStrategy::InitMFETrack(const ulong    i_ticket,
                              const double   i_entry,
                              const double   i_sl,
                              const datetime i_open_time)
{
Print("📊 INIT | Ticket#", i_ticket, " | Count=", m_MfeCount+1, " | Risk=", MathAbs(i_entry-i_sl));
    // Vérifie si déjà tracké
    //-----------------------
    for (int i = 0; i < m_MfeCount; i++)
        if (m_MfeTrack[i].ticket == i_ticket) return;

    double l_Risk = MathAbs(i_entry - i_sl);
    if (l_Risk == 0)
    {
        LOG.WARNING("InitMFETrack : risk=0 ignoré | #" + IntegerToString(i_ticket) + 
                    " | entry=" + DoubleToString(i_entry, _Digits) +
                    " | sl=" + DoubleToString(i_sl, _Digits), __FUNCTION__);
        return;
    }

    int idx = m_MfeCount;
    ArrayResize(m_MfeTrack, idx + 1);

    m_MfeTrack[idx].ticket       = i_ticket;
    m_MfeTrack[idx].entry        = i_entry;
    m_MfeTrack[idx].original_sl  = i_sl;
    m_MfeTrack[idx].initial_risk = l_Risk;
    m_MfeTrack[idx].mfe          = 0.0;
    m_MfeTrack[idx].mae          = 0.0;
    m_MfeTrack[idx].open_time    = i_open_time;
    m_MfeTrack[idx].active       = true;
    m_MfeCount++;

    LOG.INFO("📊 MFE init | #" + IntegerToString(i_ticket) +
             " | Entry="  + DoubleToString(i_entry, _Digits) +
             " | SL="     + DoubleToString(i_sl,    _Digits) +
             " | Risk="   + DoubleToString(l_Risk,  _Digits), __FUNCTION__);
             
    // ✅ Initialise les checkpoints temporels
    m_MfeTrack[idx].r_5  = 0.0; m_MfeTrack[idx].r_10 = 0.0;
    m_MfeTrack[idx].r_15 = 0.0; m_MfeTrack[idx].r_20 = 0.0;
    m_MfeTrack[idx].r_30 = 0.0; m_MfeTrack[idx].r_45 = 0.0;
    m_MfeTrack[idx].r_60 = 0.0;                 
}

//+------------------------------------------------------------------+
//| UpdateMFE + Tracking temporel                                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| UpdateMFE : met à jour MFE/MAE + checkpoints                    |
//+------------------------------------------------------------------+
void CStrategy::UpdateMFE(void)
{
   for(int i=0; i<m_MfeCount; i++)
   {
      if(!m_MfeTrack[i].active) continue;

      // Vérifie si la position existe encore
      bool found = false;
      for(int p=PositionsTotal()-1; p>=0; p--)
         if(PositionGetTicket(p) == m_MfeTrack[i].ticket) { found = true; break; }
      
      if(!found) { ExportMFE(i); m_MfeTrack[i].active = false; continue; }
      if(!PositionSelectByTicket(m_MfeTrack[i].ticket)) continue;

      double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
      double entry = m_MfeTrack[i].entry;
      long type = PositionGetInteger(POSITION_TYPE);
      double risk = m_MfeTrack[i].initial_risk;
      if(risk <= 0) continue;

      // Excursion courante (signée)
      double excursion = (type == POSITION_TYPE_BUY) ? (cur - entry) : (entry - cur);
      
      // ✅ MAJ MFE (max favorable historique, en points)
      if(excursion > 0 && excursion > m_MfeTrack[i].mfe)
         m_MfeTrack[i].mfe = excursion;
      
      // ✅ MAJ MAE (max adverse historique, en points)
      if(excursion < 0 && MathAbs(excursion) > m_MfeTrack[i].mae)
         m_MfeTrack[i].mae = MathAbs(excursion);

      // ✅ Checkpoints temporels : utiliser le MFE/R courant (pas l'excursion signée)
      double r_max_so_far = m_MfeTrack[i].mfe / risk;  // ← MFE historique en R
      int mins = (int)(TimeCurrent() - m_MfeTrack[i].open_time) / 60;
      
      if(mins >= 5  && r_max_so_far > m_MfeTrack[i].r_5)  m_MfeTrack[i].r_5  = r_max_so_far;
      if(mins >= 10 && r_max_so_far > m_MfeTrack[i].r_10) m_MfeTrack[i].r_10 = r_max_so_far;
      if(mins >= 15 && r_max_so_far > m_MfeTrack[i].r_15) m_MfeTrack[i].r_15 = r_max_so_far;
      if(mins >= 20 && r_max_so_far > m_MfeTrack[i].r_20) m_MfeTrack[i].r_20 = r_max_so_far;
      if(mins >= 30 && r_max_so_far > m_MfeTrack[i].r_30) m_MfeTrack[i].r_30 = r_max_so_far;
      if(mins >= 45 && r_max_so_far > m_MfeTrack[i].r_45) m_MfeTrack[i].r_45 = r_max_so_far;
      if(mins >= 60 && r_max_so_far > m_MfeTrack[i].r_60) m_MfeTrack[i].r_60 = r_max_so_far;
      
      // ✅ Propagation forward : garantir r_5 <= r_10 <= ... <= r_60
      if(m_MfeTrack[i].r_10 < m_MfeTrack[i].r_5)  m_MfeTrack[i].r_10 = m_MfeTrack[i].r_5;
      if(m_MfeTrack[i].r_15 < m_MfeTrack[i].r_10) m_MfeTrack[i].r_15 = m_MfeTrack[i].r_10;
      if(m_MfeTrack[i].r_20 < m_MfeTrack[i].r_15) m_MfeTrack[i].r_20 = m_MfeTrack[i].r_15;
      if(m_MfeTrack[i].r_30 < m_MfeTrack[i].r_20) m_MfeTrack[i].r_30 = m_MfeTrack[i].r_20;
      if(m_MfeTrack[i].r_45 < m_MfeTrack[i].r_30) m_MfeTrack[i].r_45 = m_MfeTrack[i].r_30;
      if(m_MfeTrack[i].r_60 < m_MfeTrack[i].r_45) m_MfeTrack[i].r_60 = m_MfeTrack[i].r_45;
   }
}

//+------------------------------------------------------------------+
//| ExportMFE — Version corrigée + colonnes temporelles             |
//+------------------------------------------------------------------+
void CStrategy::ExportMFE(const int i_idx)
{
   double l_Risk = m_MfeTrack[i_idx].initial_risk;
   if(l_Risk == 0) return;

   // Calculs finaux
   double l_RMax   = m_MfeTrack[i_idx].mfe / l_Risk;  // ← mfe
   double l_MAE    = m_MfeTrack[i_idx].mae / l_Risk;  // ← mae
   double l_RFinal = 0.0;
   string l_Result = "BE";
   datetime l_CloseTime = TimeCurrent();
   
   bool is_buy = (m_MfeTrack[i_idx].original_sl < m_MfeTrack[i_idx].entry);

   // Récupération résultat historique
   if(HistorySelectByPosition(m_MfeTrack[i_idx].ticket))
   {
      for(int d = HistoryDealsTotal()-1; d >= 0; d--)
      {
         ulong dt = HistoryDealGetTicket(d);
         if(HistoryDealGetInteger(dt, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         
         double closePrice = HistoryDealGetDouble(dt, DEAL_PRICE);
         l_CloseTime = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
         double exc = is_buy ? (closePrice - m_MfeTrack[i_idx].entry) 
                             : (m_MfeTrack[i_idx].entry - closePrice);
         l_RFinal = exc / l_Risk;
         break;
      }
   }

   // Classification
   double tp_ratio = (K_TP_Override > 0) ? K_TP_Override : GetSymbolConfig(I_Symbol_Key).risk_reward;
   if      (l_RFinal >= tp_ratio * 0.95) l_Result = "TP";
   else if (l_RFinal <= -0.95)           l_Result = "SL";
   else                                  l_Result = "BE";

   int duration = (int)(l_CloseTime - m_MfeTrack[i_idx].open_time) / 60;

   // ✅ Écriture CSV — Header unique + colonnes temporelles
   if(m_MfeFileHandle != INVALID_HANDLE)
   {
      // Header une seule fois
      if(!m_MfeHeaderWritten)
      {
         FileWrite(m_MfeFileHandle,
            "ticket","result","r_max","r_final","mae_r","duration_min",
            "r_5","r_10","r_15","r_20","r_30","r_45","r_60",
            "entry_time","close_time","type");
         m_MfeHeaderWritten = true;
      }

      // Data — paramètres séparés (FILE_CSV gère le ;)
      FileWrite(m_MfeFileHandle,
         IntegerToString(m_MfeTrack[i_idx].ticket),
         l_Result,
         DoubleToString(l_RMax, 4),
         DoubleToString(l_RFinal, 4),
         DoubleToString(l_MAE, 4),
         IntegerToString(duration),
         DoubleToString(m_MfeTrack[i_idx].r_5, 4),
         DoubleToString(m_MfeTrack[i_idx].r_10, 4),
         DoubleToString(m_MfeTrack[i_idx].r_15, 4),
         DoubleToString(m_MfeTrack[i_idx].r_20, 4),
         DoubleToString(m_MfeTrack[i_idx].r_30, 4),
         DoubleToString(m_MfeTrack[i_idx].r_45, 4),
         DoubleToString(m_MfeTrack[i_idx].r_60, 4),
         TimeToString(m_MfeTrack[i_idx].open_time, TIME_DATE|TIME_MINUTES),
         TimeToString(l_CloseTime, TIME_DATE|TIME_MINUTES),
         (is_buy ? "BUY" : "SELL"));
      
      FileFlush(m_MfeFileHandle);
   }
   else
   {
      LOG.ERROR("ExportMFE : handle invalide", __FUNCTION__);
   }
}

//+------------------------------------------------------------------+
//| CheckTimeStop : coupe si duration > X ET MFE_historique < Y     |
//| Sortie au marché (pas de niveau fixe)                           |
//+------------------------------------------------------------------+
void CStrategy::CheckTimeStop(const uint i_time_cut_min, const double i_r_cut)
{
   if(!K_TimeStop_Enabled) return;
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (K_Magic + I_Robot_ID)) continue;
      
      int idx = FindMFEIdx(t);
      if(idx < 0) continue;
      
      // Critère 1 : durée > seuil
      int dur = (int)(TimeCurrent() - m_MfeTrack[idx].open_time) / 60;
      if(dur <= (int)i_time_cut_min) continue;
      
      double risk = m_MfeTrack[idx].initial_risk;
      if(risk <= 0) continue;
      
      // Critère 2 : MFE historique < seuil (jamais montré de momentum)
      double r_max_so_far = m_MfeTrack[idx].mfe / risk;
      if(r_max_so_far >= i_r_cut) continue;
      
      // ✅ Critère 3 : trade ACTUELLEMENT négatif
      // Si le prix est en territoire favorable (même légèrement), on laisse courir
      if(!PositionSelectByTicket(t)) continue;
      double cur      = PositionGetDouble(POSITION_PRICE_CURRENT);
      double entry    = m_MfeTrack[idx].entry;
      long   pos_type = PositionGetInteger(POSITION_TYPE);
      double current_excursion = (pos_type == POSITION_TYPE_BUY) 
                                  ? (cur - entry) 
                                  : (entry - cur);
      
      if(current_excursion >= 0) continue;  // ← Trade positif ou à l'entrée → on ne coupe pas
      
      // Les 3 critères sont réunis → sortie au marché
      MqlTradeRequest req = {}; 
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_DEAL;
      req.position = t;
      req.symbol   = Symbol();
      req.volume   = PositionGetDouble(POSITION_VOLUME);
      req.price    = (pos_type == POSITION_TYPE_BUY) 
                     ? SymbolInfoDouble(Symbol(), SYMBOL_BID) 
                     : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      req.type     = (pos_type == POSITION_TYPE_BUY) 
                     ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.magic    = K_Magic + I_Robot_ID;
      req.deviation = 20;
      
      if(OrderSend(req, res) && 
         (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
      {
         LOG.INFO("⏱ Time-stop | #" + IntegerToString(t) +
                  " | dur=" + IntegerToString(dur) + "min" +
                  " | mfe_R=" + DoubleToString(r_max_so_far, 3) +
                  " | cur_R=" + DoubleToString(current_excursion/risk, 3) +
                  " | sortie=" + DoubleToString(res.price, _Digits), 
                  __FUNCTION__);
      }
   }
}