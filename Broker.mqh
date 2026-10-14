//+
//|
//| Classe de gestion des ordres
//| (Le code est compatible MT4 et MT5)
//|
//| - Envoi d'un ordre d'achat ou de vente 
//| - Bascule dynamique : STOP ou MARCHÉ selon breakout instantané
//| - Envoi d'une demande de clôture de position
//|
//| Tous les paramètres proviennent de la stratégie
//|
//+------------------------------------------------------
//| Liste des fonctions :
//| - SendOrder           : Dispatch principal avec bascule dynamique
//| - ClosePosition       : Fermeture d'une position ouverte
//| - DeletePendingOrders : Annulation des ordres en attente
//| - OrderBUYMARKET      : Ordre au marché BUY  (bascule instant breakout)
//| - OrderSELLMARKET     : Ordre au marché SELL (bascule instant breakout)
//| - OrderBUYSTOP        : Ordre BUY_STOP
//| - OrderSELLSTOP       : Ordre SELL_STOP


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////

class CBroker
{
//==========================================
//--- PRIVATE
//==========================================
private:
    // Fonctions
    //----------
    bool    OrderBUYMARKET(const string      i_StrategyName,
                           const STRUCT_STRATEGY &i_param);
    bool    OrderSELLMARKET(const string     i_StrategyName,
                            const STRUCT_STRATEGY &i_param);
    bool    OrderBUYSTOP(const string        i_StrategyName,
                         const STRUCT_STRATEGY &i_param);
    bool    OrderSELLSTOP(const string       i_StrategyName,
                          const STRUCT_STRATEGY &i_param);                      
    bool    OrderBUYLIMIT(const string        i_StrategyName,
                         const STRUCT_STRATEGY &i_param);
    bool    OrderSELLLIMIT(const string       i_StrategyName,
                          const STRUCT_STRATEGY &i_param); 
//==========================================
//--- PUBLIC
//==========================================
public:
    // Fonctions
    //----------
    bool    SendOrder(const string           i_StrategyName,
                      const STRUCT_STRATEGY &i_param);
    void    ClosePosition(const string           i_StrategyName,
                          const STRUCT_STRATEGY &i_param);
    void    DeletePendingOrders(const string i_StrategyName,
                                const STRUCT_STRATEGY &i_param);                          
};

//////////////////////////////////////////////////////////
//                                                      //
//                  F U N C T I O N S                   //
//                                                      //
//////////////////////////////////////////////////////////

//+------------------------------------------------------------+
//| SendOrder                                                  |
//| Dispatch principal selon IsMarketOrder / K_UseLimitEntry   |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| TRUE si l'ordre a été bien exécuté                         |
//+------------------------------------------------------------+
bool CBroker::SendOrder(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    string  l_Header;
    string  l_OrderTypeLog;

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

    // Si robot en simulation
    //-----------------------
    if (CONTEXT.GetSimuState())
    {
        // Lit les dernières données du marché
        //------------------------------------
        if (!SymbolInfoTick(Symbol(), l_Tick)) return(false);

        // Simule les ordres
        //------------------
        if (i_param.Trend == eT_Bull)
        {
            LOG.INFO(l_Header +
                     " : SIMU ACHAT : Entrée : " + DoubleToString(l_Tick.ask, MONEY.GetDigit()) +
                     " , StopLoss : "   + DoubleToString(i_param.StopLoss   , MONEY.GetDigit()) +
                     " , TakeProfit : " + DoubleToString(i_param.TakeProfit , MONEY.GetDigit()) +
                     " , Lot : "        + DoubleToString(i_param.Size       , MONEY.GetDigitLot()),
                     __FUNCTION__ );
        }
        else
        {
            LOG.INFO(l_Header +
                     " : SIMU VENTE : Entrée : " + DoubleToString(l_Tick.bid, MONEY.GetDigit()) +
                     " , StopLoss : "   + DoubleToString(i_param.StopLoss   , MONEY.GetDigit()) +
                     " , TakeProfit : " + DoubleToString(i_param.TakeProfit , MONEY.GetDigit()) +
                     " , Lot : "        + DoubleToString(i_param.Size       , MONEY.GetDigitLot()),
                     __FUNCTION__ );
        }
        return(true);        
    }

    // Si robot en REEL
    //----------------
    else
    {
        if (MONEY.ControlFreeMargin(i_StrategyName, i_param))
        {
            // ✅ LOG DYNAMIQUE selon type d'ordre réel
            //------------------------------------------
            if (i_param.IsMarketOrder)
                l_OrderTypeLog = "MARCHÉ";
            else
                l_OrderTypeLog = "STOP";

            LOG.INFO(l_Header + " : Placement Ordre " + l_OrderTypeLog +
                     " " + TrendToString(i_param.Trend), __FUNCTION__);

            // ✅ DISPATCH : IsMarketOrder → marché, sinon Stop
            //-----------------------------------------------------
            if (i_param.Trend == eT_Bull)
            {
                if (i_param.IsMarketOrder)
                    return(this.OrderBUYMARKET(i_StrategyName, i_param));
                else
                    return(this.OrderBUYSTOP(i_StrategyName, i_param));
            }
            else if (i_param.Trend == eT_Bear)
            {
                if (i_param.IsMarketOrder)
                    return(this.OrderSELLMARKET(i_StrategyName, i_param));
                else
                    return(this.OrderSELLSTOP(i_StrategyName, i_param));
            }
            else
            {
                LOG.WARNING(l_Header + " : Défaut dans le sens d'ouverture de position !!!" , __FUNCTION__ );
                return(false);
            }
        }
    }

    // Sortie impossible mais on ne sait jamais !!!
    //---------------------------------------------
    return(false);
}

//+------------------------------------------------------------+
//| ClosePosition                                              |
//| Envoi d'une demande de clôture de position                 |
//| INPUT:                                                     |
//| None                                                       |
//| OUTPUT:                                                    |
//| None                                                       |
//+------------------------------------------------------------+
void CBroker::ClosePosition(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick)) return;

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

    // Tentative de clôture
    //---------------------
    LOG.INFO(l_Header + " : Tentative de fermeture de la position #" + IntegerToString(i_param.No_ticket), __FUNCTION__ );

    // Fermeture de la position
    //-------------------------

//##################
//###### MQL5 ######   
//##################
#ifdef __MQL5__
    // Variable locale
    //----------------
    MqlTradeRequest    l_Request;
    MqlTradeResult     l_Result;

    // Prépare l'envoi des ordres
    //---------------------------
    ZeroMemory(l_Request);
    ZeroMemory(l_Result);
    
    // Envoi de l'ordre
    //-----------------
    l_Request.action     = TRADE_ACTION_DEAL;        // type de l'opération de trading    
    l_Request.position   = i_param.No_ticket;        // ticket de la position
    l_Request.symbol     = Symbol();                 // symbole 
    l_Request.volume     = i_param.Size;             // volume de la position
    l_Request.deviation  = I_Deviation;              // déviation du prix autorisée
    l_Request.magic      = K_Magic + I_Robot_ID;     // MagicNumber de la position
    l_Request.type       = (i_param.Trend == eT_Bull) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY; // type de l'ordre
    l_Request.price      = (i_param.Trend == eT_Bull) ? l_Tick.bid : l_Tick.ask;          // prix de l'ordre

    // Gestion des erreurs
    //--------------------
    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
       LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
    }
    else
    {
        if (l_Result.deal != 0)
        {
            MONEY.ResultTicketClosed(i_StrategyName, i_param);
            STRAT.SetTicket(i_param.No_detection, 0);
        }
        else
        {
            LOG.ERROR_CODE(l_Result.retcode, __FUNCTION__);   
        }
    }                    

//##################
//###### MQL4 ######   
//##################
#else
    // Variable locale
    //----------------
    bool   l_Result;
    int    l_Error;

    ResetLastError();
    l_Result = OrderClose(i_param.No_ticket,
                          i_param.Size,
                          (i_param.Trend == eT_Bull) ? l_Tick.bid : l_Tick.ask,
                          I_Deviation);

    // Gestion de l'erreur
    //--------------------
    if (l_Result)
    {
        MONEY.ResultTicketClosed(i_StrategyName, i_param);        
        STRAT.SetTicket(i_param.No_detection, 0);
    }
    else
    {
        l_Error = GetLastError();
        LOG.ERROR_CODE(l_Error, __FUNCTION__);
    }                          
#endif
//##################
//##################
} 

//+------------------------------------------------------------+
//| DeletePendingOrders                                        |
//| Annule tous les ordres en attente pour ce symbole/magic    |
//| INPUT:                                                     |
//| None                                                       |
//| OUTPUT:                                                    |
//| None                                                       |
//+------------------------------------------------------------+
void CBroker::DeletePendingOrders(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick)) return;

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

    // Tentative d'annulation de l'ordre
    //----------------------------------
    LOG.INFO(l_Header + " : Tentative d'annulation de l'ordre #" + IntegerToString(i_param.No_ticket), __FUNCTION__ );

    // Annule l'ordre
    //---------------
    
    // Variable locale
    //----------------
    MqlTradeRequest    l_Request;
    MqlTradeResult     l_Result;
    int                l_Ticket;
    int                l_OrdersDeleted;

    // Compteur d'ordres supprimés
    //----------------------------
    l_OrdersDeleted = 0;

    // Annulation de l'ordre
    //----------------------
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        l_Ticket = (int)OrderGetTicket(i);
        
        // Vérifie que c'est bien notre ordre
        //-----------------------------------
        if (OrderGetString(ORDER_SYMBOL) == Symbol() && 
            OrderGetInteger(ORDER_MAGIC) == (K_Magic + I_Robot_ID))
        {
            // Si on cherche un ticket spécifique, on vérifie
            //-----------------------------------------------
            if (i_param.No_ticket != 0 && l_Ticket != i_param.No_ticket)
            {
                continue;  // Ce n'est pas le bon ticket
            }

            // Prépare l'annulation de l'ordre
            //--------------------------------
            ZeroMemory(l_Request);
            ZeroMemory(l_Result);

            l_Request.action = TRADE_ACTION_REMOVE;
            l_Request.order  = l_Ticket;

            // Gestion des erreurs
            //--------------------
            ResetLastError();
            if (!OrderSend(l_Request, l_Result))
            {
                LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
            }
            else
            {
                if (l_Result.retcode == TRADE_RETCODE_DONE || 
                    l_Result.retcode == TRADE_RETCODE_PLACED)
                {
                    LOG.INFO("Ordre pending #" + IntegerToString(l_Ticket) + " annulé avec succès", __FUNCTION__);
                    
                    // Réinitialise le ticket dans DATAS
                    //----------------------------------
                    STRAT.SetTicket(i_param.No_detection, 0);
                    l_OrdersDeleted++;
                }
                else
                {
                    LOG.ERROR_CODE(l_Result.retcode, __FUNCTION__);   
                }
            }
            
            // Si on cherchait un ticket spécifique et qu'on l'a trouvé, on sort
            //-----------------------------------------------------------------
            if (i_param.No_ticket != 0)
            {
                break;
            }
        }            
    }
    
    // Affiche un message si aucun ordre n'a été trouvé
    //-------------------------------------------------
    if (l_OrdersDeleted == 0)
    {
        LOG.INFO("Aucun ordre en attente à annuler pour cette détection", __FUNCTION__);
    }
}

//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////

//+------------------------------------------------------------+
//| OrderBUY                                                   |
//| Envoi d'un ordre d'achat au MARCHÉ                         |
//| Utilisé pour la bascule instant breakout (IsMarketOrder)   |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| TRUE si l'ordre a été bien exécuté                         |
//+------------------------------------------------------------+
bool CBroker::OrderBUYMARKET(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    int     l_Ticket;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("Impossible de lire les données du marché ! Detection annulée !", __FUNCTION__);
        return(false);
    }    

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

//##################
//###### MQL5 ######   
//##################
#ifdef __MQL5__
    // Variable locale
    //----------------
    MqlTradeRequest       l_Request;
    MqlTradeCheckResult   l_Check;
    MqlTradeResult        l_Result;

    // Prépare l'envoi des ordres
    //---------------------------
    ZeroMemory(l_Request);
    ZeroMemory(l_Check);
    ZeroMemory(l_Result);
    
    // Envoi de l'ordre
    //-----------------
    l_Request.action     = TRADE_ACTION_DEAL;        // type de l'opération de trading    
    l_Request.symbol     = Symbol();                 // symbole 
    l_Request.volume     = i_param.Size;             // volume de la position
    l_Request.type       = ORDER_TYPE_BUY;           // type de l'ordre
    l_Request.price      = l_Tick.ask;               // prix marché au moment de l'envoi
    l_Request.sl         = i_param.StopLoss;         // StopLoss
    l_Request.tp         = i_param.TakeProfit;       // TakeProfit
    l_Request.deviation  = I_Deviation;              // déviation du prix autorisée
    l_Request.comment    = i_StrategyName + " BUY-MARKET";             // commentaire
    l_Request.magic      = K_Magic + I_Robot_ID;     // MagicNumber de la position

    // Gestion des erreurs
    //--------------------
    ResetLastError();
    if (!OrderCheck(l_Request, l_Check))
    {
        LOG.ERROR("OrdreCheck : " + ErrorToString(GetLastError()) + " - " + ErrorToString(l_Check.retcode) + "'" + l_Check.comment + "'", __FUNCTION__);
        return(false);
    }

    // Envoi l'ordre
    //--------------
    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
       LOG.ERROR("OrderSend : " + ErrorToString(GetLastError()), __FUNCTION__);
       return(false);
    }

    if (l_Result.deal == 0)
    {
        LOG.ERROR("Ordre non accepté : " + ErrorToString(l_Result.retcode), __FUNCTION__);
        return(false);
    }
    
    // Enregistre le ticket
    //---------------------
    l_Ticket = (int)l_Result.order;
    STRAT.SetTicket(i_param.No_detection, l_Ticket);

//##################
//###### MQL4 ######   
//##################
#else
    // Envoi de l'ordre
    //-----------------
    ResetLastError();
    l_Ticket = OrderSend(Symbol(),
                         OP_BUY,
                         i_param.Size,
                         l_Tick.ask,
                         I_Deviation,
                         i_param.StopLoss,
                         i_param.TakeProfit,
                         i_StrategyName + " BUY-MARKET",
                         K_Magic + I_Robot_ID);
    // Gestion des erreurs
    //--------------------
    if (l_Ticket > 0)
    {
        STRAT.SetTicket(i_param.No_detection, l_Ticket);
    }
    else
    {
        LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
        return(false);
    }

#endif
//##################
//##################

    // Indique les infos d'ouverture
    //------------------------------
    LOG.INFO(l_Header + " : 🚀 BUY MARCHÉ #" + IntegerToString(l_Ticket) +
             " | Prix : "  + DoubleToString(l_Tick.ask,       MONEY.GetDigit()) +
             " | SL : "    + DoubleToString(i_param.StopLoss, MONEY.GetDigit()) +
             " | TP : "    + DoubleToString(i_param.TakeProfit, MONEY.GetDigit()), __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------+
//| OrderSELLMARKET                                            |
//| Envoi d'un ordre SELL au marché (bascule instant breakout) |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| TRUE si l'ordre a été bien exécuté                         |
//+------------------------------------------------------------+
bool CBroker::OrderSELLMARKET(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    int     l_Ticket;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("Impossible de lire les données du marché ! Detection annulée !", __FUNCTION__);
        return(false);
    }    

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

//##################
//###### MQL5 ######   
//##################
#ifdef __MQL5__
    // Variable locale
    //----------------
    MqlTradeRequest    l_Request;
    MqlTradeCheckResult l_Check;
    MqlTradeResult     l_Result;

    // Prépare l'envoi des ordres
    //---------------------------
    ZeroMemory(l_Request);
    ZeroMemory(l_Check);
    ZeroMemory(l_Result);
    
    // Envoi de l'ordre
    //-----------------
    l_Request.action     = TRADE_ACTION_DEAL;        // type de l'opération de trading    
    l_Request.symbol     = Symbol();                 // symbole 
    l_Request.volume     = i_param.Size;             // volume de la position
    l_Request.type       = ORDER_TYPE_SELL;          // type de l'ordre
    l_Request.price      = l_Tick.bid;               // prix marché au moment de l'envoi
    l_Request.sl         = i_param.StopLoss;         // StopLoss
    l_Request.tp         = i_param.TakeProfit;       // TakeProfit
    l_Request.deviation  = I_Deviation;              // déviation du prix autorisée
    l_Request.comment    = i_StrategyName + " SELL-MARKET";            // commentaire
    l_Request.magic      = K_Magic + I_Robot_ID;     // MagicNumber de la position

    // Gestion des erreurs
    //--------------------
    ResetLastError();
    if (!OrderCheck(l_Request, l_Check))
    {
        LOG.ERROR("OrdreCheck : " + ErrorToString(GetLastError()) + " - " + ErrorToString(l_Check.retcode) + "'" + l_Check.comment + "'", __FUNCTION__);
        return(false);
    }

    // Envoi l'ordre
    //--------------
    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
       LOG.ERROR("OrderSend : " + ErrorToString(GetLastError()), __FUNCTION__);
       return(false);
    }

    if (l_Result.deal == 0)
    {
        LOG.ERROR("Ordre non accepté : " + ErrorToString(l_Result.retcode), __FUNCTION__);
        return(false);
    }
    
    // Enregistre le ticket
    //---------------------
    l_Ticket = (int)l_Result.order;
    STRAT.SetTicket(i_param.No_detection, l_Ticket);

//##################
//###### MQL4 ######   
//##################
#else
    // Envoi de l'ordre
    //-----------------
    ResetLastError();
    l_Ticket = OrderSend(Symbol(),
                         OP_SELL,
                         i_param.Size,
                         l_Tick.bid,
                         I_Deviation,
                         i_param.StopLoss,
                         i_param.TakeProfit,
                         i_StrategyName + " SELL-MARKET",
                         K_Magic + I_Robot_ID);
    // Gestion des erreurs
    //--------------------
    if (l_Ticket > 0)
    {
        STRAT.SetTicket(i_param.No_detection, l_Ticket);
    }
    else
    {
        LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
        return(false);
    }

#endif
//##################
//##################

    // Indique les infos d'ouverture
    //------------------------------
    LOG.INFO(l_Header + " : 🚀 SELL MARCHÉ #" + IntegerToString(l_Ticket) +
             " | Prix : "  + DoubleToString(l_Tick.bid,       MONEY.GetDigit()) +
             " | SL : "    + DoubleToString(i_param.StopLoss, MONEY.GetDigit()) +
             " | TP : "    + DoubleToString(i_param.TakeProfit, MONEY.GetDigit()), __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------+
//| OrderBUYSTOP                                               |
//| Envoi d'un ordre BUY_STOP                                  |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| TRUE si l'ordre a été bien exécuté                         |
//+------------------------------------------------------------+
bool CBroker::OrderBUYSTOP(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    int     l_Ticket;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("Impossible de lire les données du marché ! Detection annulée !", __FUNCTION__);
        return(false);
    }    

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

    // Variable locale
    //----------------
    MqlTradeRequest    l_Request;
    MqlTradeCheckResult l_Check;
    MqlTradeResult     l_Result;

    // Prépare l'envoi des ordres
    //---------------------------
    ZeroMemory(l_Request);
    ZeroMemory(l_Check);
    ZeroMemory(l_Result);
    
    // Envoi de l'ordre
    //-----------------
    l_Request.action     = TRADE_ACTION_PENDING;        // type de l'opération de trading    
    l_Request.symbol     = Symbol();                    // symbole 
    l_Request.volume     = i_param.Size;                // volume de la position
    l_Request.type       = ORDER_TYPE_BUY_STOP;         // type de l'ordre
    l_Request.price      = i_param.Entry;               // prix de l'ordre
    l_Request.sl         = i_param.StopLoss;            // StopLoss
    l_Request.tp         = i_param.TakeProfit;          // TakeProfit
    l_Request.deviation  = I_Deviation;                 // déviation du prix autorisée
    l_Request.comment    = i_StrategyName + " BUY-STOP";                  // commentaire 
    l_Request.magic      = K_Magic + I_Robot_ID;        // MagicNumber de la position

    // Gestion des erreurs
    //--------------------
    ResetLastError();
    if (!OrderCheck(l_Request, l_Check))
    {
        LOG.ERROR("OrdreCheck : " + ErrorToString(GetLastError()) + " - " + ErrorToString(l_Check.retcode) + "'" + l_Check.comment + "'", __FUNCTION__);
        return(false);
    }

    // Envoi l'ordre
    //--------------
    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
        LOG.ERROR("Ordre non accepté : " + ErrorToString(l_Result.retcode), __FUNCTION__);
        return(false);
    }
    
    // Enregistre le ticket
    //---------------------
    l_Ticket = (int)l_Result.order;
    STRAT.SetTicket(i_param.No_detection, l_Ticket);

    // Indique les infos d'ouverture
    //------------------------------
    LOG.INFO(l_Header + " : Ouverture ticket BUY STOP #" + IntegerToString(l_Ticket) +
             " | Entry : " + DoubleToString(i_param.Entry,      MONEY.GetDigit()) +
             " | SL : "    + DoubleToString(i_param.StopLoss,   MONEY.GetDigit()) +
             " | TP : "    + DoubleToString(i_param.TakeProfit, MONEY.GetDigit()), __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------+
//| OrderSELLSTOP                                              |
//| Envoi d'un ordre SELL_STOP                                 |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| TRUE si l'ordre a été bien exécuté                         |
//+------------------------------------------------------------+
bool CBroker::OrderSELLSTOP(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    int     l_Ticket;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("Impossible de lire les données du marché ! Detection annulée !", __FUNCTION__);
        return(false);
    }    

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

    // Variable locale
    //----------------
    MqlTradeRequest    l_Request;
    MqlTradeCheckResult l_Check;
    MqlTradeResult     l_Result;

    // Prépare l'envoi des ordres
    //---------------------------
    ZeroMemory(l_Request);
    ZeroMemory(l_Check);
    ZeroMemory(l_Result);
    
    // Envoi de l'ordre
    //-----------------
    l_Request.action     = TRADE_ACTION_PENDING;        // type de l'opération de trading    
    l_Request.symbol     = Symbol();                    // symbole 
    l_Request.volume     = i_param.Size;                // volume de la position
    l_Request.type       = ORDER_TYPE_SELL_STOP;        // type de l'ordre
    l_Request.price      = i_param.Entry;               // prix de l'ordre
    l_Request.sl         = i_param.StopLoss;            // StopLoss
    l_Request.tp         = i_param.TakeProfit;          // TakeProfit
    l_Request.deviation  = I_Deviation;                 // déviation du prix autorisée
    l_Request.comment    = i_StrategyName + " SELL-STOP";                 // commentaire 
    l_Request.magic      = K_Magic + I_Robot_ID;        // MagicNumber de la position

    // Gestion des erreurs
    //--------------------
    ResetLastError();
    if (!OrderCheck(l_Request, l_Check))
    {
        LOG.ERROR("OrdreCheck : " + ErrorToString(GetLastError()) + " - " + ErrorToString(l_Check.retcode) + "'" + l_Check.comment + "'", __FUNCTION__);
        return(false);
    }

    // Envoi l'ordre
    //--------------
    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
        LOG.ERROR("Ordre non accepté : " + ErrorToString(l_Result.retcode), __FUNCTION__);
        return(false);
    }
    
    // Enregistre le ticket
    //---------------------
    l_Ticket = (int)l_Result.order;
    STRAT.SetTicket(i_param.No_detection, l_Ticket);

    // Indique les infos d'ouverture
    //------------------------------
    LOG.INFO(l_Header + " : Ouverture ticket SELL STOP #" + IntegerToString(l_Ticket) +
             " | Entry : " + DoubleToString(i_param.Entry,      MONEY.GetDigit()) +
             " | SL : "    + DoubleToString(i_param.StopLoss,   MONEY.GetDigit()) +
             " | TP : "    + DoubleToString(i_param.TakeProfit, MONEY.GetDigit()), __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------+
//| OrderBUYLIMIT                                              |
//| Envoi d'un ordre BUY_LIMIT                                 |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| TRUE si l'ordre a été bien exécuté                         |
//+------------------------------------------------------------+
bool CBroker::OrderBUYLIMIT(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    int     l_Ticket;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("Impossible de lire les données du marché ! Detection annulée !", __FUNCTION__);
        return(false);
    }    

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

    // Variable locale
    //----------------
    MqlTradeRequest    l_Request;
    MqlTradeCheckResult l_Check;
    MqlTradeResult     l_Result;

    // Prépare l'envoi des ordres
    //---------------------------
    ZeroMemory(l_Request);
    ZeroMemory(l_Check);
    ZeroMemory(l_Result);
    
    // Envoi de l'ordre
    //-----------------
    l_Request.action     = TRADE_ACTION_PENDING;        // type de l'opération de trading    
    l_Request.symbol     = Symbol();                    // symbole 
    l_Request.volume     = i_param.Size;                // volume de la position
    l_Request.type       = ORDER_TYPE_BUY_LIMIT;        // type de l'ordre
    l_Request.price      = i_param.Entry;               // prix de l'ordre
    l_Request.sl         = i_param.StopLoss;            // StopLoss
    l_Request.tp         = i_param.TakeProfit;          // TakeProfit
    l_Request.deviation  = I_Deviation;                 // déviation du prix autorisée
    l_Request.comment    = i_StrategyName + " BUY-LIMIT";                 // commentaire 
    l_Request.magic      = K_Magic + I_Robot_ID;        // MagicNumber de la position

    // Gestion des erreurs
    //--------------------
    ResetLastError();
    if (!OrderCheck(l_Request, l_Check))
    {
        LOG.ERROR("OrdreCheck : " + ErrorToString(GetLastError()) + " - " + ErrorToString(l_Check.retcode) + "'" + l_Check.comment + "'", __FUNCTION__);
        return(false);
    }

    // Envoi l'ordre
    //--------------
    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
        LOG.ERROR("Ordre non accepté : " + ErrorToString(l_Result.retcode), __FUNCTION__);
        return(false);
    }
    
    // Enregistre le ticket
    //---------------------
    l_Ticket = (int)l_Result.order;
    STRAT.SetTicket(i_param.No_detection, l_Ticket);

    // Indique les infos d'ouverture
    //------------------------------
    LOG.INFO(l_Header + " : Ouverture ticket BUY LIMIT #" + IntegerToString(l_Ticket) +
             " | Entry : " + DoubleToString(i_param.Entry,      MONEY.GetDigit()) +
             " | SL : "    + DoubleToString(i_param.StopLoss,   MONEY.GetDigit()) +
             " | TP : "    + DoubleToString(i_param.TakeProfit, MONEY.GetDigit()), __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------+
//| OrderSELLLIMIT                                             |
//| Envoi d'un ordre SELL_LIMIT                                |
//| INPUT:                                                     |
//| Données de la détection                                    |
//| OUTPUT:                                                    |
//| TRUE si l'ordre a été bien exécuté                         |
//+------------------------------------------------------------+
bool CBroker::OrderSELLLIMIT(const string i_StrategyName, const STRUCT_STRATEGY &i_param)
{
    // Variables locales
    //------------------
    MqlTick l_Tick;
    int     l_Ticket;
    string  l_Header;

    // Lit les dernières données du marché
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("Impossible de lire les données du marché ! Detection annulée !", __FUNCTION__);
        return(false);
    }    

    // Construit l'entête des messages
    //--------------------------------
    l_Header = LOG.InfosLogOperation(i_StrategyName, i_param.No_detection, Symbol());

    // Variable locale
    //----------------
    MqlTradeRequest    l_Request;
    MqlTradeCheckResult l_Check;
    MqlTradeResult     l_Result;

    // Prépare l'envoi des ordres
    //---------------------------
    ZeroMemory(l_Request);
    ZeroMemory(l_Check);
    ZeroMemory(l_Result);
    
    // Envoi de l'ordre
    //-----------------
    l_Request.action     = TRADE_ACTION_PENDING;        // type de l'opération de trading    
    l_Request.symbol     = Symbol();                    // symbole 
    l_Request.volume     = i_param.Size;                // volume de la position
    l_Request.type       = ORDER_TYPE_SELL_LIMIT;       // type de l'ordre
    l_Request.price      = i_param.Entry;               // prix de l'ordre
    l_Request.sl         = i_param.StopLoss;            // StopLoss
    l_Request.tp         = i_param.TakeProfit;          // TakeProfit
    l_Request.deviation  = I_Deviation;                 // déviation du prix autorisée
    l_Request.comment    = i_StrategyName + " SELL-LIMIT";                // commentaire 
    l_Request.magic      = K_Magic + I_Robot_ID;        // MagicNumber de la position

    // Gestion des erreurs
    //--------------------
    ResetLastError();
    if (!OrderCheck(l_Request, l_Check))
    {
        LOG.ERROR("OrdreCheck : " + ErrorToString(GetLastError()) + " - " + ErrorToString(l_Check.retcode) + "'" + l_Check.comment + "'", __FUNCTION__);
        return(false);
    }

    // Envoi l'ordre
    //--------------
    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
        LOG.ERROR("Ordre non accepté : " + ErrorToString(l_Result.retcode), __FUNCTION__);
        return(false);
    }
    
    // Enregistre le ticket
    //---------------------
    l_Ticket = (int)l_Result.order;
    STRAT.SetTicket(i_param.No_detection, l_Ticket);

    // Indique les infos d'ouverture
    //------------------------------
    LOG.INFO(l_Header + " : Ouverture ticket SELL LIMIT #" + IntegerToString(l_Ticket) +
             " | Entry : " + DoubleToString(i_param.Entry,      MONEY.GetDigit()) +
             " | SL : "    + DoubleToString(i_param.StopLoss,   MONEY.GetDigit()) +
             " | TP : "    + DoubleToString(i_param.TakeProfit, MONEY.GetDigit()), __FUNCTION__);
    return(true);
}