//+--------------------------------------------------------------------+
//|                                                                    |
//| Classe pour afficher et surveiller les divers états du logiciel    |
//| (Le code est compatible MT4 et MT5)                                |
//|                                                                    |
//| - Configuration de l'affichage des états                           |
//| - Affichage cyclique des états                                     |
//| - Contrôle des possibilités de trading                             |
//|                                                                    |
//+--------------------------------------------------------------------+
//| Liste  des fonctions : A compléter avec IA

////////////////////////////////////////////////////////////
//                                                        //
//                  C L A S S                             //
//                                                        //
////////////////////////////////////////////////////////////

class CMonitoring
{
//=====================================
//--- PRIVATE
//=====================================
private:
    bool    m_CloseOfPositions;              // Indique que le processus de clôture de position est en route
    bool    m_AroundNews;                    // Indique la proximité d'une news


//=====================================
//--- PUBLIC
//=====================================
public:
    // Fonctions
    //----------
    void  Config(void);
    void  Cyclic(void);
    bool  ReadyForStrategy(void);
};

////////////////////////////////////////////////////////////
//                                                        //
//                  F U N C T I O N S                     //
//                                                        //
////////////////////////////////////////////////////////////

//+--------------------------------------------------------------------+
//| Config                                                             |
//| Initialise le système d'affichage des états                        |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CMonitoring::Config(void)
{
    // Initialisation des données internes
    //------------------------------------
    m_CloseOfPositions = false;
    m_AroundNews       = false;

    // Prépare les informations à afficher
    //------------------------------------
    VISU.SetText(0, "Système de log");
    VISU.SetText(1, "Système de paramètres");

    VISU.SetText(3, "Connection réseau");
    VISU.SetText(4, "Configuration du compte");
    VISU.SetText(5, "Terminal prêt pour le trading");
    VISU.SetText(6, "Logiciel prêt pour le trading");
    VISU.SetText(7, "Données du marché");
    VISU.SetText(8, "Ouverture du marché");

    VISU.SetText(10, "Config de la stratégie");
    VISU.SetText(11, "Journée pour le trading");
    VISU.SetText(12, "Horaire de trading");
    VISU.SetText(13, "Hors zone de coupure");
    VISU.SetText(14, "Hors zone de news");

    VISU.SetText(16, "Résultat du jour");
    VISU.SetText(17, "Résultat hebdomadaire");
}

//+--------------------------------------------------------------------+
//| Cyclic                                                             |
//| Surveille les changements des états du logiciel                    |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CMonitoring::Cyclic(void)
{
    // Affichage des états du logiciel
    //--------------------------------
    VISU.SetValue(0, BOOL_TO_VISU(LOG.ConfigOk()));
    VISU.SetValue(1, BOOL_TO_VISU(PARAM.ConfigOk()));

    VISU.SetValue(3, BOOL_TO_VISU(CONTEXT.GetNetworkState()));
    VISU.SetValue(4, BOOL_TO_VISU(CONTEXT.GetBrokerState()));
    VISU.SetValue(5, BOOL_TO_VISU(CONTEXT.GetTerminalState()));
    VISU.SetValue(6, BOOL_TO_VISU(CONTEXT.GetSoftState()));
    VISU.SetValue(7, BOOL_TO_VISU(CONTEXT.GetMarketState()));
    VISU.SetValue(8, BOOL_TO_VISU(CONTEXT.GetMarketOpen()));

    VISU.SetValue(10, BOOL_TO_VISU(STRAT.ConfigOk()));
    VISU.SetValue(11, BOOL_TO_VISU(PARAM.DayOfTrading()));
    VISU.SetValue(12, BOOL_TO_VISU(PARAM.HourOfTrading()));
    VISU.SetValue(13, BOOL_TO_VISU(PARAM.OutsideCutZone()));
    VISU.SetValue(14, BOOL_TO_VISU(PARAM.OutsideSecurityZone()));

    VISU.SetValue(16, BOOL_TO_VISU(MONEY.GetStateDayResult()));
    VISU.SetValue(17, BOOL_TO_VISU(MONEY.GetStateWeekResult()));
    VISU.Show();

    // Mise à jour des tooltips
    //-------------------------
    VISU.UpdateText(16, "Résultat du jour : " + DoubleToString(MONEY.GetDayResult(), 2) + "%");
    VISU.UpdateText(17, "Résultat hebdomadaire : " + DoubleToString(MONEY.GetWeekResult(), 2) + "%");

    // Contrôle si dans une zone de coupure
    //-------------------------------------
    if (!PARAM.OutsideCutZone() && CONTEXT.GetMarketOpen())
    {
        // Avertissement du processus de coupure des positions
        //----------------------------------------------------
        if (!m_CloseOfPositions && STRAT.GetPositionNb() > 0)
        {
            LOG.INFO("Début de la coupure générale des positions", __FUNCTION__);
        }
        m_CloseOfPositions = true;
        STRAT.CloseOfPositions();
    }
    else
    {
        m_CloseOfPositions = false;
    }

    // Contrôle si à proximité d'une news économique
    //----------------------------------------------
    if (!PARAM.OutsideSecurityZone())
    {
        // Avertissement de la proximité d'une news
        //-----------------------------------------
        if (!m_AroundNews)
        {
            LOG.INFO("[" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
                     "] !!! Proximité de news économique !!!", __FUNCTION__);
        }
        m_AroundNews = true;
    }
    else
    {
        // Sortie de la zone de proximité d'une news économique
        //-----------------------------------------------------
        if (m_AroundNews)
        {
            LOG.INFO("[" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
                     "] Fin de la news économique", __FUNCTION__);
        }
        m_AroundNews = false;
    }

    // Contrôle des positions sans stop
    //---------------------------------
    // TODO   
}

//+--------------------------------------------------------------------+
//| ReadyForStrategy                                                   |
//| Fait le bilan de tous les contextes (technique, finance,           |           
//| et horaire)                                                        |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  TRUE si ok pour le trading                                        |
//+--------------------------------------------------------------------+
bool CMonitoring::ReadyForStrategy(void)
{
    // Variable locale
    //---------------
    bool l_GeneralState;

    // Regroupe tous les états
    //-----------------------
    l_GeneralState  = CONTEXT.GetGeneralState();
    l_GeneralState &= CONTEXT.GetRunState();
    l_GeneralState &= PARAM.HourOfTrading();
    l_GeneralState &= PARAM.DayOfTrading();
    l_GeneralState &= PARAM.OutsideCutZone();
    l_GeneralState &= PARAM.OutsideSecurityZone();
    l_GeneralState &= MONEY.GetFinanceState();

    // Résultat
    //---------
    return(l_GeneralState);

}