//+------------------------------------------------------------------+
//|                                                                  |
//|        Gestion des aspects monétaires de robot                   |
//|             (Compatible MT4 et MT5)                              |
//|                                                                  |
//+------------------------------------------------------------------+
//| Liste  des fonctions :
//| - Config      : Configuration de la classe (A compléter avec IA)


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////

class CMoney
{
//================================
//---  PRIVATE
//================================
private:
    // Données du marché
    //------------------
    double    m_MinLot;         // Taille minimum du lot
    double    m_MaxLot;         // Taille maximum du lot
    double    m_StepLot;        // Pas de variation du lot
    double    m_Point;          // Pas du marché
    double    m_TickSize;       // Taille du tick
    int       m_StopMini;       // Taille minimum du stop
    int       m_Digit;          // Nombre de décimales du prix
    int       m_DigitLot;       // Nombre de décimales la taille de lot


    // Données de configuration
    //-------------------------
    double   m_Risk;            // Taille du risque (% du capital)
    double   m_MaxDayLoss;      // Niveau de perte max journalière (% du capital)
    double   m_MaxWeekLoss;     // Niveau de perte max hebdomadaire (% du capital)
    double   m_TrailingStop;    // Taille du trailing stop 
    double   m_MaxRiskAuth;    // Risque max autorisé pour fallback MinLot (%)

    // Données calculées cycliquement
    //-------------------------------
    double   m_DayResult;       // Résultat de la journée
    double   m_WeekResult;      // Résultat de la semaine
    bool     m_DayResultOk;     // Le résultat de la journée est dans les limites
    bool     m_WeekResultOk;    // Le résultat de la semaine est dans les limites
    double   m_Daily_Result;

    // Fonctions
    //----------
    void    VerifyDayResult(void);
    void    VerifyWeekResult(void);
    double  GetResult(const datetime i_TimeMin);


//================================
//---  PUBLIC
//================================
public: 
    void   Config(void);
    void   Cyclic(void);

    // Infos venants de l'extérieur
    //-----------------------------
    void  SetRisk          (const double i_risk)           { m_Risk          = MathAbs(i_risk);     }   
    void  SetDailyMaxLoss  (const double i_LossLevel)      { m_MaxDayLoss    = MathAbs(i_LossLevel);}
    void  SetWeeklyMaxLoss (const double i_LossLevel)      { m_MaxWeekLoss   = MathAbs(i_LossLevel);}
    void  SetTrailingStop  (const double i_Trailing)       { m_TrailingStop  = MathAbs(i_Trailing); }
    void  SetMaxRiskAuth   (const double i_max)            { m_MaxRiskAuth   = MathAbs(i_max);        }

    // Fonctions pour extraire les données
    //------------------------------------
    int     GetDigit(void)               { return(m_Digit);        }
    int     GetDigitLot(void)            { return(m_DigitLot);     }
    bool    GetStateDayResult(void)      { return(m_DayResultOk);  }
    bool    GetStateWeekResult(void)     { return(m_WeekResultOk); }
    double  GetDayResult(void)           { return(m_DayResult);    }
    double  GetWeekResult(void)          { return(m_WeekResult);   }
    bool    GetFinanceState(void)        { return(m_DayResultOk && m_WeekResultOk); }
    double  GetDaily_Result(void);

    // Traitement des données
    //-----------------------
    double  CalculateLotSize(const STRUCT_STRATEGY &i_param);
    bool    TicketInProgress(const int i_NoTicket);
    void    ResultTicketClosed(const string i_StrategyName, const STRUCT_STRATEGY &i_param);
    bool    ControlFreeMargin(const string i_StrategyName, const STRUCT_STRATEGY &i_param);

};

//////////////////////////////////////////////////////////
//                                                      //
//              F U N C T I O N S                       //
//                                                      //
//////////////////////////////////////////////////////////
//+----------------------------------------------------------------+
//| Config                                                         |
//| Initialise les données de l'objet                              |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CMoney::Config(void)
{
    // Initialisation des données
    //---------------------------
    m_MinLot      = 0.0;
    m_MaxLot      = 0.0;
    m_StepLot     = 0.0;
    m_Point       = 0.0;
    m_TickSize    = 0.0;
    m_StopMini    = 0;
    m_Digit       = 0;
    m_DigitLot    = 0;

    m_Risk           = 0.0;
    m_MaxDayLoss     = 0.0;
    m_MaxWeekLoss    = 0.0;
    m_TrailingStop   = 0.0;
    m_MaxRiskAuth    = 0.0;

    m_DayResultOk    = true;
    m_WeekResultOk   = true;
    m_DayResult      = 0.0;
    m_WeekResult     = 0.0;

    m_Daily_Result   = 0.0;
}

/*
Cyclic
Lecture des infos du marché
INPUT:
None
OUTPUT:
None
*/
void CMoney::Cyclic(void)
{
    // Lecture des données du marché
    //-----------------------------
    m_MinLot    =      SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    m_MaxLot    =      SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    m_StepLot   =      SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    m_Point     =      SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    m_TickSize  =      SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    m_StopMini  = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    m_Digit     = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    m_DigitLot  =      (m_StepLot == 0) ? 0 : int(-MathLog10(m_StepLot));
     
    // Calcul les résultats
    //---------------------
    VerifyDayResult();
    VerifyWeekResult();
}

/*
CalculateLotSize
Tente de calculer une taille de lot avec les données de la 
détection, la configuration et les données du marché
INPUT:
Données de la détection
OUTPUT:
Taille de lot calculée
*/
double CMoney::CalculateLotSize(const STRUCT_STRATEGY &i_param)
{
    // Données locales
    //----------------
    string     l_Symbol;
    double     l_Balance;
    double     l_TickVal;
    double     l_TickSize;
    double     l_LotSize;
    double     l_RiskAmount;
    double     l_RiskPoints;
    int        l_Digits;

    // Récupération des données
    //-------------------------
    l_Symbol   = Symbol();
    l_Balance = (K_BalanceMode == eBM_Compound)
            ? AccountInfoDouble(ACCOUNT_BALANCE)
            : (double)I_TAILLE_DU_COMPTE;
    l_TickVal  = SymbolInfoDouble(l_Symbol, SYMBOL_TRADE_TICK_VALUE);
    l_TickSize = SymbolInfoDouble(l_Symbol, SYMBOL_TRADE_TICK_SIZE);  // ✅ RE-LECTURE DIRECTE
    l_Digits   = (int)SymbolInfoInteger(l_Symbol, SYMBOL_DIGITS);

    // ✅ CALCUL DE LA DISTANCE (TOUJOURS POSITIVE)
    //---------------------------------------------
    l_RiskPoints = MathAbs(i_param.Entry - i_param.StopLoss);

    // Contrôle les données disponibles
    //---------------------------------
    if ((l_RiskPoints == 0) || (l_TickSize == 0) || (m_StepLot == 0) || (l_TickVal == 0))
    {
        LOG.WARNING("Détection #" + IntegerToString(i_param.No_detection) + 
                   " : Données invalides (RiskPoints=" + DoubleToString(l_RiskPoints, 5) +
                   ", TickSize=" + DoubleToString(l_TickSize, 5) + 
                   ", TickVal=" + DoubleToString(l_TickVal, 5) + ")", __FUNCTION__);
        return(0.0);
    }

    // ✅ CALCUL DU RISQUE CIBLE
    //-------------------------
    l_RiskAmount = l_Balance * (m_Risk / 100.0);

    // ✅ FORMULE UNIVERSELLE
    //----------------------
    // Lot = RiskAmount / ((RiskPoints / TickSize) * TickValue)
    l_LotSize = l_RiskAmount / ((l_RiskPoints / l_TickSize) * l_TickVal);

    // ✅ LOG DÉTAILLÉ **AVANT** NORMALISATION
    //----------------------------------------
    LOG.INFO("🔬 CALCUL LOT BRUT" +
             "\n   📊 Symbole : " + l_Symbol +
             "\n   💵 Balance : " + DoubleToString(l_Balance, 2) +
             "\n   🎯 Risque % : " + DoubleToString(m_Risk, 3) + "%" +
             "\n   🎯 Risque cible : " + DoubleToString(l_RiskAmount, 2) + " USD" +
             "\n   📈 Entry : " + DoubleToString(i_param.Entry, l_Digits) +
             "\n   🛑 StopLoss : " + DoubleToString(i_param.StopLoss, l_Digits) +
             "\n   📏 Distance : " + DoubleToString(l_RiskPoints, l_Digits) +
             "\n   🔧 TickValue : " + DoubleToString(l_TickVal, 5) +
             "\n   🔧 TickSize : " + DoubleToString(l_TickSize, 5) +
             "\n   🔧 Point : " + DoubleToString(m_Point, 5) +
             "\n   ➗ RiskPoints/TickSize : " + DoubleToString(l_RiskPoints/l_TickSize, 2) +
             "\n   💰 Lot brut : " + DoubleToString(l_LotSize, 4), __FUNCTION__);

    // Règle la taille de lot aux limites du marché
    //---------------------------------------------
    l_LotSize = MathMin(m_MaxLot, MathFloor(l_LotSize / m_StepLot) * m_StepLot);
    
    if (l_LotSize < m_MinLot)
    {
        // Fallback MinLot avec vérification du risque maximum autorisé
        if (m_MaxRiskAuth > 0.0)
        {
            double l_RiskAtMinLot    = (l_RiskPoints / l_TickSize) * l_TickVal * m_MinLot;
            double l_RiskPctAtMinLot = (l_RiskAtMinLot / l_Balance) * 100.0;
    
            if (l_RiskPctAtMinLot <= m_MaxRiskAuth)
            {
                LOG.WARNING("Lot brut (" + DoubleToString(l_LotSize, 4) +
                           ") < MinLot → Fallback MinLot autorisé" +
                           " | Risque réel : " + DoubleToString(l_RiskPctAtMinLot, 3) +
                           "% ≤ " + DoubleToString(m_MaxRiskAuth, 3) + "% max", __FUNCTION__);
                l_LotSize = m_MinLot;
            }
            else
            {
                LOG.WARNING("Lot brut (" + DoubleToString(l_LotSize, 4) +
                           ") < MinLot → Fallback REFUSÉ" +
                           " | Risque MinLot : " + DoubleToString(l_RiskPctAtMinLot, 3) +
                           "% > " + DoubleToString(m_MaxRiskAuth, 3) + "% max → Annulé", __FUNCTION__);
                return(0.0);
            }
        } 
        else
        {
            // Comportement original si K_Max_Risk_Auth non défini (= 0)
            LOG.WARNING("Lot calculé (" + DoubleToString(l_LotSize, 4) +
                       ") < MinLot (" + DoubleToString(m_MinLot, 2) + ") → Annulé", __FUNCTION__);
            return(0.0);
        }
    }

    // ✅ VÉRIFICATION DU RISQUE RÉEL
    //-------------------------------
    double l_NbTicks = l_RiskPoints / l_TickSize;
    double l_RisqueReel = l_NbTicks * l_TickVal * l_LotSize;
    double l_Ecart = l_RisqueReel - l_RiskAmount;
    
    LOG.INFO("💸 RÉSULTAT FINAL" +
             "\n   📦 Lot final : " + DoubleToString(l_LotSize, m_DigitLot) +
             "\n   💵 Risque réel : " + DoubleToString(l_RisqueReel, 2) + " USD" +
             "\n   ⚖️  Écart : " + DoubleToString(l_Ecart, 2) + " USD" +
             "\n   " + ((MathAbs(l_Ecart) > 2.0) ? "⚠️ ÉCART ANORMAL !" : "✅ OK"), __FUNCTION__);

    return(NormalizeDouble(l_LotSize, m_DigitLot));
}
/*
TicketInProgress
Cherche un ticket et indique s'il est en cours ou pas
INPUT:
Numéro de ticket recherché
OUTPUT:
TRUE si le ticket est trouvé
*/
bool CMoney::TicketInProgress(const int i_NoTicket)
{
    // Local data
    //-----------
    int l_Total;
    int l_Loop;
    int l_Ticket;

//##################
//###### MQL5 ######
//##################
#ifdef __MQL5__
    // Recherche parmi les positions ouvertes
    //--------------------------------------
    l_Total = PositionsTotal();
    for (l_Loop = l_Total - 1; l_Loop >= 0; l_Loop--)
    {
        // Teste le numéro du ticket
        //--------------------------
        l_Ticket = (int)PositionGetTicket(l_Loop);
        if (l_Ticket == i_NoTicket) return(true);        
    }
    
//##################
//###### MQL4 ######
//##################
#else
    // Recherche parmi les ordres ouverts
    //-----------------------------------
    l_Total = OrdersTotal();
    for (l_Loop = l_Total - 1; l_Loop >= 0; l_Loop--)
    {
        // Sélectionne l'ordre
        //--------------------
        if (OrderSelect(l_Loop, SELECT_BY_POS))
        {
            // Teste le numéro du ticket
            //--------------------------
            l_Ticket = OrderTicket();
            if (l_Ticket == i_NoTicket) return(true);        
        }
    }
#endif
//##################
//##################
   // Ticket non trouvé
   //------------------
    return(false);
}
//+-----------------------------------------------------------+
//| GetDaily_Result                                           |
//| Retourne le resultat quotidien et remet a zero            |
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  Valeur de la journée en %                                |
//+-----------------------------------------------------------+
double CMoney::GetDaily_Result(void)
{
    // Variables locales
    //------------------
    double l_Result;
    
    // Retourne le resultat quotidien et remet à zero pour le jour suivant
    //--------------------------------------------------------------------
    l_Result = m_Daily_Result;
    m_Daily_Result = 0.0;
    return(l_Result);
}

/*
ResultTicketClosed
Cherche un ticket fermé et affiche les résultats
INPUT:
Nom de la stratégie
Numéro du ticket recherché
OUTPUT:
None
*/  
void CMoney::ResultTicketClosed(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Données locales
    //----------------
    int    l_Total;
    int    l_Loop;
    double l_Profit;
    bool   l_Find;
    string   l_Text;
    double   l_Progression;
    double   l_Balance;
    string   l_Header;

    // Initialisation
    //---------------
    l_Find   = false;
    l_Profit = 0.0;

//##################
//###### MQL5 ######
//##################
#ifdef __MQL5__
    // Recherche dans les historique des positions
    //--------------------------------------------
    int l_Ticket;
    if (HistorySelectByPosition(i_param.No_ticket))
    {
        l_Find   = true;
        l_Total = HistoryDealsTotal();
        for (l_Loop = l_Total - 1; l_Loop >= 0; l_Loop--)
        {
            // Calcul de tous les résultats liés à la position
            //------------------------------------------------
            l_Ticket  = (int)HistoryDealGetTicket(l_Loop);
            l_Profit += HistoryDealGetDouble(l_Ticket, DEAL_COMMISSION);
            l_Profit += HistoryDealGetDouble(l_Ticket, DEAL_SWAP);
            l_Profit += HistoryDealGetDouble(l_Ticket, DEAL_PROFIT);
            l_Profit += HistoryDealGetDouble(l_Ticket, DEAL_FEE);                        
        }
    }
    
//##################
//###### MQL4 ######
//##################
#else
    // Recherche dans l'historique des ordres
    //---------------------------------------
    l_Total = OrdersHistoryTotal();
    for (l_Loop = l_Total - 1; l_Loop >= 0; l_Loop--)
    {
        // Vérifie si on y a accès
        //------------------------
        if (!OrderSelect(l_Loop, SELECT_BY_POS, MODE_HISTORY)) continue;

        // Teste le numéro
        //----------------
        if (OrderTicket() == i_param.No_ticket)
        {
            l_Profit += OrderCommission();
            l_Profit += OrderSwap();
            l_Profit = OrderProfit();            
            l_Find   = true;
            break;
        }
    }    

#endif
//##################        
//##################

   // Sort les résultats
   //-------------------
    if (l_Find)
    {
        // Construit l'entête des messages
        //--------------------------------
        l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

        // Calcul de la progression du compte
        //-----------------------------------
        l_Balance = AccountInfoDouble(ACCOUNT_BALANCE);
        l_Progression = 100.0 * (l_Profit / (l_Balance - l_Profit));

        l_Text = (l_Profit >= 0.0) ? " : Fermeture en GAIN : " : " : Fermeture en Perte : ";

        LOG.INFO(l_Header + l_Text + DoubleToString(l_Profit, 2) + " (" + DoubleToString(l_Progression, 3) + "%)", __FUNCTION__);
        
        // Mémorise les résultats
        //-----------------------
        m_Daily_Result += l_Progression;
    }
}

//+------------------------------------------------------------+
//| ControlFreeMargin                                          |
//| Controle de la marge libre pour l'ouverture d'une position |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| None                                                       |
//+------------------------------------------------------------+
bool CMoney::ControlFreeMargin(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Données locales
    //----------------
    double l_FreeMargin;
    string l_Header;

    // Lecture des données utiles
    //---------------------------
    l_FreeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

//##################
//###### MQL5 ######
//##################
#ifdef __MQL5__

    double    l_MarginNeeded;
    bool      l_Result;
    MqlTick   l_Tick;

    // Lecture des données utiles
    //---------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick)) 
    {
        LOG.WARNING(l_Header + " : Impossible de lire les données du marché ! Detection annulée !", __FUNCTION__);
        return(false);
    }

    // Calcule le besoin de marge
    //---------------------------
    ResetLastError();
    l_Result = OrderCalcMargin((i_param.Trend == eT_Bull) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                Symbol(),
                                i_param.Size,
                                (i_param.Trend == eT_Bull) ? l_Tick.ask : l_Tick.bid,
                                l_MarginNeeded);

    // Contrôle la marge restante et le compte
    //----------------------------------------
    if ((l_MarginNeeded >= l_FreeMargin) || !l_Result)
    {
        LOG.WARNING(l_Header + " : Marge libre trop faible(" + DoubleToString(l_FreeMargin, 2) + " pour " + DoubleToString(l_MarginNeeded, 2) + " nécessaire). Détection annulée !", __FUNCTION__);
        return(false);
    }                                

//##################
//###### MQL4 ######
//##################
#else
    // Local data
    //-----------
    double l_RemainMargin;

    // Calcule de la marge restante après l'ordre prévu
    //-------------------------------------------------
    ResetLastError();
    l_RemainMargin = AccountFreeMarginCheck(Symbol(),
                                            i_param.Trend == eT_Bull ? OP_BUY : OP_SELL,
                                            i_param.Size);

    // Contrôle la marge restante et le compte
    //----------------------------------------
    if ((l_RemainMargin <= 0.0) || (GetLastError() == ERR_NOT_ENOUGH_MONEY))
    {
        LOG.WARNING(l_Header + 
                    " : Marge libre trop faible(" +
                    DoubleToString(l_FreeMargin, 2) + " pour " +
                    DoubleToString(l_FreeMargin - l_RemainMargin, 2) + " nécessaire). Détection annulée !",
                    __FUNCTION__);
        return(false);                    
    }

#endif
//##################
//##################

    // Assez de marge pour ouvrir l'ordre
    //-----------------------------------
    return(true);
}
//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////
/*
VerifyDayResult
Calcule l'évolution du compte dans la journée
INPUT:
None
OUTPUT:
None
*/
void CMoney::VerifyDayResult(void)
{
    // Données locales
    //----------------
    double         l_Limit;
    datetime       l_TimeMin;
    MqlDateTime    l_TimeStruct;

    // Contrôle uniquement si une limite de perte est définie
    //--------------------------------------------------------
    if (m_MaxDayLoss <= 0.0) return;

    // Initialisation
    //---------------
    TimeToStruct(TimeCurrent(), l_TimeStruct);

    // Calcule les dates
    //-----------------
    l_TimeStruct.hour = 0;
    l_TimeStruct.min  = 0;
    l_TimeStruct.sec  = 0;
    l_TimeMin = StructToTime(l_TimeStruct);

    // Extrait les infos
    //-----------------
    m_DayResult = GetResult(l_TimeMin);

    // Gère le dépassement des seuils
    //-------------------------------
    l_Limit = (m_DayResultOk) ? -m_MaxDayLoss : -m_MaxDayLoss * 0.9;

    // Information en cas de changement de seuil
    //------------------------------------------
    if (m_DayResultOk && (m_DayResult < l_Limit))
    {
        LOG.WARNING("Niveau de perte journalière dépassée !!!", __FUNCTION__);
        m_DayResultOk = false;
    }
    else if (!m_DayResultOk && (m_DayResult > l_Limit))
    {
        LOG.INFO("Niveau de perte journalière redevenu acceptable.", __FUNCTION__);
        m_DayResultOk = true;
    }
}    

/*
VerifyWeekResult
Calcule l'évolution du compte dans la semaine
INPUT:
None
OUTPUT:
None
*/
void CMoney::VerifyWeekResult(void)
{
    // Données locales
    //----------------
    double         l_Limit;
    datetime       l_TimeMin;
    MqlDateTime    l_TimeStruct;

    // Contrôle uniquement si une limite de perte est définie
    //--------------------------------------------------------
    if (m_MaxWeekLoss <= 0.0) return;

    // Initialisation
    //---------------
    TimeToStruct(TimeCurrent(), l_TimeStruct);

    // Calcule les dates
    //-----------------
    l_TimeStruct.hour = 0;
    l_TimeStruct.min  = 0;
    l_TimeStruct.sec  = 0;
    l_TimeMin  = StructToTime(l_TimeStruct);
    l_TimeMin -= l_TimeStruct.day_of_week * PeriodSeconds(PERIOD_D1);

    // Extrait les infos
    //-----------------
    m_WeekResult = GetResult(l_TimeMin);

    // Gère le dépassement des seuils
    //-------------------------------
    l_Limit = (m_WeekResultOk) ? -m_MaxWeekLoss : -m_MaxWeekLoss * 0.9;

    // Information en cas de changement de seuil
    //------------------------------------------
    if (m_WeekResultOk && (m_WeekResult < l_Limit))
    {
        LOG.WARNING("Niveau de perte hebdomadaire dépassée !!!", __FUNCTION__);
        m_WeekResultOk = false;
    }
    else if (!m_WeekResultOk && (m_WeekResult > l_Limit))
    {
        LOG.INFO("Niveau de perte hebdomadaire redevenu acceptable.", __FUNCTION__);
        m_WeekResultOk = true;
    }
}

/*
GetResult
Calcule le résultat dans une période + time range
INPUT:
Dates de l'intervalle à tester
OUTPUT:
Resultats en pourcentage
*/
double CMoney::GetResult(const datetime i_TimeMin)
{
    // Données locales
    //----------------
    double     l_Result;
    double     l_Balance;
    double     l_WinLoss;
    double     l_ResulOp;
    int        l_Total;
    int        l_Loop;

    // Initialisation
    //---------------
    l_Balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    l_Result    = 0.0;
    l_WinLoss   = 0.0;

    // Si le capital est illisible, on sort
    //--------------------------------------
    if (l_Balance == 0.0) return(0.0);

    // Compte les gains et pertes dans la période
    //------------------------------------------

//##################
//###### MQL5 ######
//##################
#ifdef __MQL5__
    // Données locales
    //----------------
    datetime          l_Time;
    ENUM_DEAL_ENTRY   l_Deal;
    ENUM_DEAL_TYPE    l_Type;
    int               l_Ticket;

    l_Total = PositionsTotal();
    for (l_Loop = l_Total - 1; l_Loop >= 0; l_Loop--)
    {
        // Get order data
        //---------------
        l_Ticket   = (int)PositionGetTicket(l_Loop);
        l_ResulOp  = (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
        l_Balance -= l_ResulOp;
        l_WinLoss += l_ResulOp;
    }

    // Calcule le résultat en pourcentage
    //-----------------------------------
    l_Result = (l_WinLoss / l_Balance) * 100.0;

    // Select the deal of the day
    //---------------------------
    if (HistorySelect(i_TimeMin, TimeCurrent()))
    {
        // Get the current profit result
        //------------------------------
        l_Total = HistoryDealsTotal();
        for (l_Loop = l_Total - 1; l_Loop >= 0; l_Loop--)
        {
            l_Ticket  = (int)HistoryDealGetTicket(l_Loop);
            l_ResulOp = HistoryDealGetDouble(l_Ticket, DEAL_PROFIT) + HistoryDealGetDouble(l_Ticket, DEAL_SWAP) + HistoryDealGetDouble(l_Ticket, DEAL_COMMISSION);
            l_Balance -= l_ResulOp;
            l_Time    = (datetime)HistoryDealGetInteger(l_Ticket, DEAL_TIME);
            l_Deal    = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(l_Ticket, DEAL_ENTRY);
            l_Type    = (ENUM_DEAL_TYPE)HistoryDealGetInteger(l_Ticket, DEAL_TYPE);
            if (l_Deal != DEAL_ENTRY_IN)
            {
                if ((l_Type == DEAL_TYPE_BUY) || (l_Type == DEAL_TYPE_SELL))
                {
                    if (l_Time >= i_TimeMin)
                    {
                        l_WinLoss += l_ResulOp;
                        l_Result  += (100 * l_ResulOp / l_Balance);
                    }
                }
            }
        }
    }
    

//##################
//###### MQL4 ######
//##################
#else
    // Données locales
    //----------------
    bool   l_Ok;

    l_Total = OrdersTotal();
    for (l_Loop = l_Total - 1; l_Loop >= 0; l_Loop--)
    {
        if (OrderSelect(l_Loop, SELECT_BY_POS))
        {
            l_ResulOp  = NormalizeDouble(OrderProfit() + OrderCommission() + OrderSwap(), 2);
            l_Balance -= l_ResulOp;
            l_WinLoss += l_ResulOp;
        }
    }

    // Calcule le résultat en pourcentage
    //-----------------------------------
    l_Result = (l_WinLoss / l_Balance) * 100.0;

    // Chercher le profit flottant
    //----------------------------
    l_Total = OrdersHistoryTotal();
    for (l_Loop = l_Total - 1; l_Loop >= 0)
    {
        if (OrderSelect(l_Loop, SELECT_BY_POS, MODE_HISTORY))
        {
            // Compute balance and result of the day
            //---------------------------------------
            if (OrderCloseTime() >= i_TimeMin)
            {
                l_ResulOp = NormalizeDouble(OrderProfit() + OrderCommission() + OrderSwap(), 2);
                l_Balance -= l_ResulOp;
                l_Ok = ((OrderType() == OP_BUY) || (OrderType() == OP_SELL) || ((OrderType() > OP_SELLSTOP) && (OrderComment() == "Rollover")));
                if (l_Ok)
                {
                    l_WinLoss += l_ResulOp;
                    l_Result  += (l_ResulOp / l_Balance) * 100.0;
                } 
            }
        }
    }

#endif
//##################        
//##################

    // Set the new equity reference
    //-----------------------------
    return(l_Result);
}    