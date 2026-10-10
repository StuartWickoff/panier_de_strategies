//+-------------------
/*
Gère le contexte du logiciel dans les environnements
MetaTrader, le marché et le courtier
(Le code est compatible MT4 et MT5)

- Avertissement des changements d'états
- Détection d'une nouvelle bougie
*/
//+----------------
/*
Liste des fonctions :
- Config         : Configurer la classe
- Cyclic         : Surveillence cyclique des changements

- SetRun         : Enregistre l'état de mmarche du robot
- SetSimulation  : Enregistre le mode du robot

- GetRunState       : Lit l'état de larche du robot
- GetSimuState      : Lit le mode du robot
- GetMarketState    : Lit l'état du marché
- GetMarketOpen     : Indique si le marché est ouvert ou pas
- GetNetworkState   : Indique l'état du réseau avec le courtier
- GetBrokerState    : Indique la disponibilité du courtier
- GetTerminalState  : Lit le configuration du terminal
- GetSoftState      : Lit l'état du logiciel
- GetGeneralState   : Lit la synthèse des états pour trader
- NewCandle         : Détection d'une nouvelle bougie
*/

//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////

class CContext
{
//================================
//---  PRIVATE
//================================
private:

    // Données pour les sessions du marché
    //------------------------------------
    uint        m_CheckTick;          // Pour le contrôle d'un marché figé
    datetime    m_ServerTime;         // Pour vérifier si le marché est figé

    // Données pour les états
    //-----------------------
    bool      m_Run;           // Le robot est en mode RUN
    bool      m_Simulation;    // Le robot est en mode SIMULATION
    bool      m_MarketOpen;    // Le marché est ouvert
    bool      m_MarketOk;      // Le marché fourni des données
    bool      m_NetworkOk;     // Le réseau est opérationnel
    bool      m_BrokerOk;      // La conf du broker permet le trading
    bool      m_TerminalOk;    // La conf du terminal permet le trading automatique
    bool      m_SoftOk;        // La conf du logiciel permet le trading automatique

    // Fonctions
    //---
    void CheckMarketOpen(void);
    void CheckMarketData(void);
    void CheckNetworkState(void);
    void CheckBrokerState(void);
    void CheckTerminalState(void);
    void CheckSoftwareState(void);

//================================
//---  PUBLIC
//================================
public:
    // Données pour détecter une nouvelle bougie
    //------------------------------------------
    datetime    m_LastZeroBarTime;            // Dernière bougie de #0

    // Fonctions
    //----------
    void Config(void);
    void Cyclic(void);

    // Infos venants de l'extérieur
    //-----------------------------
    void SetRun             (const bool i_state)           {m_Run        = i_state;  }
    void SetSimulation      (const bool i_state)           {m_Simulation = i_state;  }

    // Fonctions pour lire les états
    //------------------------------
    bool GetRunState        (void)         { return(m_Run);        }
    bool GetSimuState       (void)         { return(m_Simulation); }
    bool GetMarketState     (void)         { return(m_MarketOk);   }
    bool GetMarketOpen      (void)         { return(m_MarketOpen); }
    bool GetNetworkState    (void)         { return(m_NetworkOk);  }
    bool GetBrokerState     (void)         { return(m_BrokerOk);   }
    bool GetTerminalState   (void)         { return(m_TerminalOk); }
    bool GetSoftState       (void)         { return(m_SoftOk);     }
    bool GetGeneralState    (void);
    bool NewCandle          (void);
};

//////////////////////////////////////////////////////////
//                                                      //
//              F U N C T I O N S                       //
//                                                      //
//////////////////////////////////////////////////////////
//+----------------------------------------------------------------+
//| Config                                                         |
//| Initialise les paramètres de l'objet                           |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CContext::Config(void)
{
   // Initialise les états
   //---------------------
   m_LastZeroBarTime = 0;

   m_CheckTick   = GetTickCount();
   m_ServerTime  = TimeCurrent();

   m_Run         = true;
   m_Simulation  = false;
   m_MarketOpen  = false;
   m_MarketOk    = false;
   m_NetworkOk   = false;
   m_BrokerOk    = false;
   m_TerminalOk  = false;
   m_SoftOk      = false;
}

//+----------------------------------------------------------------+
//| Cyclic                                                         |
//| Analyse les données contextuelles pour définir les états       |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CContext::Cyclic(void)
{
    // Vérification globale du contexte
    //---------------------------------
    this.CheckMarketOpen();
    this.CheckMarketData();
    this.CheckNetworkState();
    this.CheckBrokerState();    
    this.CheckTerminalState();
    this.CheckSoftwareState();
}

//+----------------------------------------------------------------+
//| GetGeneralState                                                |
//| Retourne l'état pour savoir si le logiciel est bien configuré  |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  TRUE si le logiciel est bien configuré                        |
//+----------------------------------------------------------------+
bool CContext::GetGeneralState(void)
{
    // Variable locale
    //---------------
    bool l_ConfigOk;

    // Défini l'état du logiciel pour trader
    //--------------------------------------
    l_ConfigOk  = MQLInfoInteger(MQL_TESTER);
    l_ConfigOk |= (m_MarketOk && m_NetworkOk && m_BrokerOk && m_TerminalOk && m_SoftOk);
    return(l_ConfigOk);
}

//+----------------------------------------------------------------+
//| NewCandle                                                      |
//| Détecte une nouvelle bougie et nettoie les détections obslètes |
//| INPUT:                                                         |
//|  None                                                          |    
//| OUTPUT:                                                        |
//|  TRUE si une nouvelle bougie est détectée                      | 
//+----------------------------------------------------------------+
bool CContext::NewCandle(void)
{
    // Variable locale
    //----------------
    datetime   l_Times[];
    bool       l_NewCandle;

    // Lit les temps des bougies
    //--------------------------
    if (CopyTime(Symbol(), PERIOD_CURRENT, 0, 2, l_Times) != 2)
    {
        return(false);
    }
    ArraySetAsSeries(l_Times, true);

    // Contrôle si la bougie 0 est passée en seconde position
    // Donc, nouvelle bougie
    //-------------------------------------------------------
    l_NewCandle = (m_LastZeroBarTime == l_Times[1]);

    // Mémorisation
    //-------------
    m_LastZeroBarTime = l_Times[0];
    return(l_NewCandle);

    
}

//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////
/*
CheckMarketOpen
Vérification pour savoir si le marché est ouvert ou non
INPUT:
None
OUTPUT:
None
*/
void CContext::CheckMarketOpen(void)
{
    // Local data
    //-----------
    datetime    l_CurrentTime;
    bool        l_PrevState;       // Vérification de l'évolution de l'état

    // Initialisation
    //---------------
    l_PrevState  = m_MarketOpen;
    m_MarketOpen = true;

    // Vérification si le temps du marché est bloqué depuis plus d'une minute
    //-----------------------------------------------------------------------
    l_CurrentTime = TimeCurrent();
    if (l_CurrentTime == m_ServerTime)
    {
        if ((GetTickCount() - m_CheckTick) >= 60000)
        {
            m_MarketOpen = false;
        }
    }
    else
    {
        m_ServerTime = l_CurrentTime;
        m_CheckTick  = GetTickCount();
    }

    // Information en cas de changement d'état
    //----------------------------------------
    if (!l_PrevState && m_MarketOpen)
    {
        LOG.INFO("Le marché " + Symbol() +" est ouvert" , __FUNCTION__);
    }
    if (l_PrevState && !m_MarketOpen)
    {
        LOG.WARNING("Le marché " + Symbol() +" est figé depuis une minute" , __FUNCTION__);   
    }
}
/*
CheckMarketData
Vérification pour savoir si le marché a des données disponibles
INPUT:
None
OUTPUT:
None
*/
void CContext::CheckMarketData(void)
{
    // Variables locales
    //------------------
    double       l_MinLot;          // Taille de lot minimum
    double       l_MaxLot;          // Taille de lot maximum
    double       l_StepLot;         // Pas pour un lot
    bool         l_PrevState;       // Vérification de l'évolution de l'état

    // Initialisation
    //---------------
    l_PrevState  = m_MarketOk;
    l_MinLot     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    l_MaxLot     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    l_StepLot    = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

    // Extrait l'état
    //---------------
    m_MarketOk = ((l_MinLot != 0) && (l_MaxLot != 0) && (l_StepLot != 0));

    // Information en cas de changement d'état
    //----------------------------------------
    if (l_PrevState && !m_MarketOk)
    {
        LOG.WARNING("Le marché " + Symbol() + " n'est pas utilisable", __FUNCTION__);
    }
    if (!l_PrevState && m_MarketOk)
    {
        LOG.INFO("Le marché " + Symbol() + " est utilisable", __FUNCTION__);
    }
}

/*
CheckNetworkState
Vérification pour savoir si le réseau est opérationnel
INPUT:
None
OUTPUT:
None
*/
void CContext::CheckNetworkState(void)
{
    // Variables locales
    //------------------
    bool         l_PrevState;       // Vérification de l'évolution de l'état
    
    // Initialisation
    //---------------
    l_PrevState = m_NetworkOk;

    // Extrait l'état
    //---------------
    m_NetworkOk = TerminalInfoInteger(TERMINAL_CONNECTED);

    // Information en cas de changement d'état
    //----------------------------------------
    if (l_PrevState && !m_NetworkOk)
    {
        LOG.WARNING("Le réseau n'est pas connecté", __FUNCTION__);
    }
    if (!l_PrevState && m_NetworkOk)
    {
        LOG.INFO("Le réseau est connecté", __FUNCTION__);
    }   
}
/*
CheckBrokerState
Vérification pour savoir si le courtier est bien configuré
INPUT:
None
OUTPUT:
None
*/
void CContext::CheckBrokerState(void)
{
    // Variables locales
    //------------------
    bool         l_PrevState;       // Vérification de l'évolution de l'état

    // Initialisation
    //---------------
    l_PrevState = m_BrokerOk;

    // Extrait l'état
    //---------------
    m_BrokerOk = AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT);

    // Information en cas de changement d'état
    //----------------------------------------
    if (l_PrevState && !m_BrokerOk)
    {
        LOG.WARNING("Le compte n'est pas configuré pour le trading", __FUNCTION__);
    }
    if (!l_PrevState && m_BrokerOk)
    {
        LOG.INFO("Le compte est bien configuré pour le trading", __FUNCTION__);
    }   
}

/*
CheckTerminalSate
Vérification pour savoir si le terminal est bien configuré
INPUT:
None
OUTPUT:
None
*/
void CContext::CheckTerminalState(void)
{
    // Variables locales
    //------------------
    bool         l_PrevState;       // Vérification de l'évolution de l'état

    // Initialisation
    //---------------
    l_PrevState = m_TerminalOk;

    // Extrait l'état
    //---------------
    m_TerminalOk = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

    // Information en cas de changement d'état
    //----------------------------------------
    if (l_PrevState && !m_TerminalOk)
    {
        LOG.WARNING("Le trading automatique est désactivé dans le terminal", __FUNCTION__);
    }
    if (!l_PrevState && m_TerminalOk)
    {
        LOG.INFO("Le trading automatique est activé dans le terminal", __FUNCTION__);
    }   
}
/*
CheckSoftwareState
Vérification pour savoir si le logiciel est bien configuré
INPUT:
None
OUTPUT:
None
*/
void CContext::CheckSoftwareState(void)
{
    // Variables locales
    //------------------
    bool         l_PrevState;       // Vérification de l'évolution de l'état

    // Initialisation
    //---------------
    l_PrevState = m_SoftOk;

    // Extrait l'état
    //---------------
    m_SoftOk = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

    // Information en cas de changement d'état
    //----------------------------------------
    if (l_PrevState && !m_SoftOk)
    {
        LOG.WARNING("Le logiciel n'est pas configuré pour le trading automatique", __FUNCTION__);
    }
    if (!l_PrevState && m_SoftOk)
    {
        LOG.INFO("Le logiciel est configuré pour le trading automatique", __FUNCTION__);
    }   
}