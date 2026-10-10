//+-----------------------------------------------------------+
//| Classe pour gérer les données en lien avec une stratégie  |
//| (Le code est compatible MT4 et MT5)                       |
//|                                                           |
//| - Création d'un groupe de paramètres pour une détection   |
//| - Affection des paramètres pour une détection             |
//| - Gestion des positions avec les détections               |
//|                                                           |
//+-----------------------------------------------------------+
//| Liste  des fonctions : (A compléter avec IA)


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CDatas
{
//===============================
//--- PRIVATE
//===============================
private:
    // Données
    //--------
    string             m_StrategyName;
    STRUCT_STRATEGY    m_Detection[];
    int                m_DetectionIdx;
    ENUM_TIMEFRAMES    m_Period;
    string             m_Filename;

    // Fonctions
    //----------
    void  ReadFile(void);
    void  WriteFile(void);
    int   IdxWithDetection(const int i_detection);

//===============================
//--- PUBLIC
//===============================
public:
    // Fonctions
    //----------
    bool   Config(const string              i_strategy_name,
                  const ENUM_TIMEFRAMES     i_period,
                  const string              i_folder);

    bool   ConfigOk(void) { return(m_Filename != ""); }
    
    void   End(void)      { this.WriteFile(); }

    // Enregistrement des données 
    //----------------------------
    bool    SetData(const int                   i_detection,
                    const STRUCT_STRATEGY      &i_param);
                       
    bool    SetTicket(const int                   i_detection,
                      const int                   i_Ticket);
                      
    // Lecture des données
    //--------------------
    int         GetPositionNb(void);

    string      GetStrategyName(void) { return(m_StrategyName); }
    
    int         GetNewDetection(void);
    
    bool        GetData(const int                   i_detection,
                      STRUCT_STRATEGY              &i_param);

    // Gestion des données
    //--------------------
    void        CloseOfPositions(void);                      

    void        DeleteDetection(void);

    void        CancelPendingOrder(void);
};

//+-----------------------------------------------------------+
//| Config                                                    |
//|  Initialise l'objet avec la création des indicateurs      |
//| INPUT:                                                    |
//|  Nom de la stratégie                                      |
//| Nom du répertoire                                         |
//| OUTPUT:                                                   |
//|  None                                                     |
//+-----------------------------------------------------------+
bool CDatas::Config(const string           i_strategy_name, 
                    const ENUM_TIMEFRAMES  i_period,
                    const string           i_folder)
{
    // Variable locale
    //----------------
    string l_folder;
    string l_strategy_name;

    // Initialisation
    //---------------
    m_DetectionIdx = 0;
    m_Period       = i_period;
    m_StrategyName = "";   
    m_Filename     = "";   
    ArrayFree(m_Detection);

    // Nettoie le nom du répertoire
    //-----------------------------
    l_folder = i_folder;
    CleanString(l_folder);

    // Vérification du nom
    //--------------------
    if (!FolderNameControl(l_folder, true))
    {
        LOG.ERROR("Nom de répertoire '" + l_folder + "' incorrect !!!", __FUNCTION__);
        return(false);
    }

    // Nettoie le nom de la stratégie
    //-------------------------------
    l_strategy_name = i_strategy_name;
    CleanString(l_strategy_name);
    l_strategy_name += Symbol() + "(" + PeriodToString(m_Period) + ")";

    // Vérification du nom
    //--------------------
    if (!FileNameControl(l_strategy_name))
    {
        LOG.ERROR("Nom de fichier '" + l_strategy_name + "' incorrect !!!", __FUNCTION__);
        return(false);
    }

    // Initialise les paramètres de la stratégie
    //------------------------------------------
    m_Filename = l_folder + IntegerToString(I_Robot_ID) + "\\" + l_strategy_name+ ".dat";
    m_StrategyName = l_strategy_name + " - ";

    // Lecture des données de la stratégie
    //------------------------------------
    this.ReadFile();

    // Fin de la configuration
    //-------------------------
    return(true);
    
}                    

//+-----------------------------------------------------------+
//| SetData                                                   |
//| Enregistre les données avec les infos du paramètre        |
//| INPUT:                                                    |
//|  Identifiant de la détection                              |
//| OUTPUT:                                                   |
//|  TRUE si la détection a été trouvée                       |
//+-----------------------------------------------------------+
bool CDatas::SetData(const int                   i_detection,
                     const STRUCT_STRATEGY      &i_param)
{
    // Variable locale
    //----------------
    int   l_Index;

    // Cherche dans le tableau de la détection
    //-----------------------------------------
    l_Index = IdxWithDetection(i_detection);
    if (l_Index >= 0)
    {
        m_Detection[l_Index] = i_param;
        return(true);
    }

    // Détection introuvable
    //----------------------
    LOG.WARNING(m_StrategyName + "Détection #" + IntegerToString(i_detection) + " introuvable !!!", __FUNCTION__);
    return(false);
}                     

//+-----------------------------------------------------------+
//| SetTicket                                                 |
//| Enregistre le ticket avec la détection                    |
//| INPUT:                                                    |
//|  Identifiant de la détection                              |
//|  Numéro de ticket                                         |
//| OUTPUT:                                                   |
//|  TRUE si la détection a bien trouvée                      |
//+-----------------------------------------------------------+
bool CDatas::SetTicket(const int i_detection, const int i_Ticket)
{
    // Variable locale
    //----------------
    int   l_Index;

    // Cherche dans le tableau de la détection
    //-----------------------------------------
    l_Index = IdxWithDetection(i_detection);
    if (l_Index >= 0)
    {
        m_Detection[l_Index].No_ticket = i_Ticket;
        return(true);
    }

    // Détection introuvable
    //----------------------
    LOG.WARNING(m_StrategyName + "Détection #" + IntegerToString(i_detection) + " introuvable !!!", __FUNCTION__);
    return(false);
}

//+-----------------------------------------------------------+
//| GetNewDetection                                           |
//| Cherche et crée un espace pour une nouvelle détection     |
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  Numéro de la nouvelle détection                          |
//+-----------------------------------------------------------+
int CDatas::GetNewDetection(void)
{
    // Variable locale
    //----------------
    int   l_Index;

    // Détecte les détections libres
    //------------------------------
    for (l_Index = 0; l_Index < ArraySize(m_Detection); l_Index++)
    {
        // Si un emplacement vide, on prend la place
        //------------------------------------------
        if (m_Detection[l_Index].No_detection == 0)
        {
            break;
        }
    }

    // Création d'un nouvel enregistrement si pas trouvé d'emplacement libre
    //----------------------------------------------------------------------
    if (l_Index == ArraySize(m_Detection))
    {
        ArrayResize(m_Detection, l_Index + 1);
    }

    // Création de la nouvelle détection avec son idx
    //-----------------------------------------------
    ZeroMemory(m_Detection[l_Index]);
    m_DetectionIdx++;
    m_Detection[l_Index].No_detection = m_DetectionIdx;
    return(m_DetectionIdx);
}
 

//+-----------------------------------------------------------+
//| GetData                                                   |
//| Cherche et renvoie les données d'une détection            |
//| INPUT:                                                    |
//|  Identifiant de la détection                              |
//| OUTPUT:                                                   |
//|  TRUE si la détection a bien trouvée                      |
//|  Données luese                                            |
//+-----------------------------------------------------------+
bool CDatas::GetData(const int i_detection, STRUCT_STRATEGY &i_param)
{
    // Variable locale
    //----------------
    int   l_Index;

    // Cherche dans le tableau de la détection
    //-----------------------------------------
    l_Index = IdxWithDetection(i_detection);
    if (l_Index >= 0)
    {
        i_param = m_Detection[l_Index];
        return(true);
    }

    // Détection introuvable
    //----------------------
    LOG.WARNING(m_StrategyName + "Détection #" + IntegerToString(i_detection) + " introuvable !!!", __FUNCTION__);
    return(false);
}
 
//+-----------------------------------------------------------+
//| GetPositionNb                                             |
//| Cherche et renvoie le nombre de positions enregistrées    |
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  Nombre de positions enregistrées                         |
//+-----------------------------------------------------------+
int CDatas::GetPositionNb(void)
{
    // Variable locale
    //----------------
    int   l_Index;
    int   l_Count;

    // Cherche dans le tableau de la détection
    //-----------------------------------------
    l_Count = 0;
    for (l_Index = 0; l_Index < ArraySize(m_Detection); l_Index++)
    {
        if (m_Detection[l_Index].No_ticket != 0) l_Count++;
    }

    // Retourne le résultat
    //---------------------
    return(l_Count);
}

//+-----------------------------------------------------------+
//| CloseOfPositions                                          |
//| Analyse toutes les détections et ferme les tickets ouverts|
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  None                                                     |
//+-----------------------------------------------------------+
void CDatas::CloseOfPositions(void)
{
    // Variable locale
    //----------------
    int   l_Index;

    // Cherche dans le tableau de la détection
    //-----------------------------------------
    for (l_Index = 0; l_Index < ArraySize(m_Detection); l_Index++)
    {
        if (m_Detection[l_Index].No_ticket != 0)
        {
            BROKER.ClosePosition(m_StrategyName, m_Detection[l_Index]);
        }
    }
}

//+-----------------------------------------------------------+
//| CancelPendingOrder                                        |
//| Annule toutes les ordres en attente                       |
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  None                                                     |
//+-----------------------------------------------------------+
void CDatas::CancelPendingOrder(void)
{
    // Variable locale
    //----------------
    int  l_Index;
    int  l_Ticket;
    MqlTradeRequest    l_Request;
    MqlTradeResult     l_Result;
    int  l_OrdersCancelled;

    // Initialisation
    //---------------
    l_OrdersCancelled = 0;

    // ✅ NOUVELLE APPROCHE : Parcourir directement OrdersTotal()
    //-----------------------------------------------------------
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        l_Ticket = (int)OrderGetTicket(i);
        
        // Vérifie que c'est notre symbole et magic
        //------------------------------------------
        if (OrderGetString(ORDER_SYMBOL) != Symbol()) continue;
        if (OrderGetInteger(ORDER_MAGIC) != (K_Magic + I_Robot_ID)) continue;

        // On a trouvé un ordre à annuler
        //-------------------------------
        LOG.INFO(m_StrategyName + "Annulation ordre pending #" + IntegerToString(l_Ticket), __FUNCTION__);

        // Prépare l'annulation
        //---------------------
        ZeroMemory(l_Request);
        ZeroMemory(l_Result);

        l_Request.action = TRADE_ACTION_REMOVE;
        l_Request.order  = l_Ticket;

        // Envoi de la requête
        //--------------------
        ResetLastError();
        if (!OrderSend(l_Request, l_Result))
        {
            LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
        }
        else
        {
            // Vérification du retcode
            //------------------------
            if (l_Result.retcode == TRADE_RETCODE_DONE || 
                l_Result.retcode == TRADE_RETCODE_PLACED)
            {
                LOG.INFO(m_StrategyName + "Ordre #" + IntegerToString(l_Ticket) + " annulé avec succès", __FUNCTION__);
                l_OrdersCancelled++;

                // ✅ Cherche la détection correspondante et réinitialise le ticket
                //----------------------------------------------------------------
                for (l_Index = 0; l_Index < ArraySize(m_Detection); l_Index++)
                {
                    if (m_Detection[l_Index].No_ticket == l_Ticket)
                    {
                        m_Detection[l_Index].No_ticket = 0;
                        LOG.INFO(m_StrategyName + "Détection #" + IntegerToString(m_Detection[l_Index].No_detection) + " : Ticket réinitialisé", __FUNCTION__);
                        break;
                    }
                }
            }
            else
            {
                LOG.ERROR_CODE(l_Result.retcode, __FUNCTION__);
            }
        }
    }

    // Message récapitulatif
    //----------------------
    if (l_OrdersCancelled == 0)
    {
        LOG.WARNING(m_StrategyName + "Aucun ordre en attente trouvé à annuler", __FUNCTION__);
    }
    else
    {
        LOG.INFO(m_StrategyName + IntegerToString(l_OrdersCancelled) + " ordre(s) annulé(s)", __FUNCTION__);
    }
}
//+-----------------------------------------------------------+
//| DeleteDetection                                           |
//| Supprime une détection pour garder ce qui est utile       |
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  None                                                     |
//+-----------------------------------------------------------+
void CDatas::DeleteDetection(void)
{
    // Variable locale
    //----------------
    int   l_Index;

    // Cherche dans le tableau de la détection
    //-----------------------------------------
    for (l_Index = 0; l_Index < ArraySize(m_Detection); l_Index++)
    {
        // Si détection sans ticket, on supprime
        //--------------------------------------
        if ((m_Detection[l_Index].No_detection) > 0 && (m_Detection[l_Index].No_ticket == 0))
        {
            ZeroMemory(m_Detection[l_Index]);
        }

        // Si ticket sans vie sur le marché, on annule la détection
        // mais on affiche les résultats quand même !!!
        //---------------------------------------------------------
        if (m_Detection[l_Index].No_ticket != 0)
        {
            if (!MONEY.TicketInProgress(m_Detection[l_Index].No_ticket))
            {
                MONEY.ResultTicketClosed(m_StrategyName, m_Detection[l_Index]);
                ZeroMemory(m_Detection[l_Index]);
            }
        }
    }
}
    

//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////

//+-----------------------------------------------------------+
//| IdxWithDetection                                          |
//| Cherche dans le tableau de la détection                   |
//| INPUT:                                                    |
//|  Identifiant de la détection                              |
//| OUTPUT:                                                   |
//|  - 1 si introuvable, sinon c'est l'index                  |
//+-----------------------------------------------------------+
int CDatas::IdxWithDetection(const int i_detection)
{
    // Variable locale
    //----------------
    int   l_Index;

    // Cherche dans tout le tableau de détection
    //-------------------------------------------
    for (l_Index = 0; l_Index < ArraySize(m_Detection); l_Index++)
    {
        if (m_Detection[l_Index].No_detection == i_detection)
        {
            return(l_Index);
        }
    }

    // Fin de la recherche
    //--------------------
    return(-1);
}    


//+-----------------------------------------------------------+
//| ReadFile                                                  |
//| Lecture des données de la stratégie depuis un fichier     |
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  None                                                     |
//+-----------------------------------------------------------+
void CDatas::ReadFile(void)
{
    // Variables locales
    //------------------
    bool l_Error;
    int  l_Index;
    int  l_Handle;
    STRUCT_STRATEGY l_Datas;

    // Initialise l'indice de la dernière détection
    //---------------------------------------------
    m_DetectionIdx = 0;
    ArrayFree(m_Detection);

    // Lit seulement si seulement la stratégie est connue
    //--------------------------------------------------
    if (m_StrategyName == "") return;
    if (MQLInfoInteger(MQL_TESTER)) return;

    // Teste si le fichier existe
    //---------------------------
    if (FileIsExist(m_Filename, FILE_COMMON) == false)
    {
        LOG.INFO(m_StrategyName + "Fichier absent pour la stratégie", __FUNCTION__);
        return;
    }

    // Ouvre le fichier en lien avec la stratégie
    //--------------------------------------------
    ResetLastError();
    l_Handle = FileOpen(m_Filename, FILE_COMMON|FILE_READ|FILE_BIN);

    // En cas d'erreur d'ouvrir de fichier
    //------------------------------------
    if (l_Handle == INVALID_HANDLE)
    {
        LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
        return;
    }

    // Boucle sur les données à lire
    //------------------------------
    l_Error = false;
    l_Index = 0;
    while (!FileIsEnding(l_Handle))
    {
        // Lit la ligne
        //-------------
        ResetLastError();
        if (FileReadStruct(l_Handle, l_Datas) != sizeof(STRUCT_STRATEGY))
        {
            if (!l_Error)
            {
                LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
                l_Error = true;
            }
        }

        // Passage à la donnée suivante
        //-----------------------------
        else
        {
            // Crée le nouveau groupe de données
            //----------------------------------
            ArrayResize(m_Detection, l_Index + 1);
            m_Detection[l_Index] = l_Datas;

            // Met à jour l'indice le plus élévé de la prochaine détection
            //------------------------------------------------------------
            if (m_Detection[l_Index].No_detection > m_DetectionIdx)
            {
                m_DetectionIdx = m_Detection[l_Index].No_detection;
            }
            l_Index++;            
        }
    }
    
    // Infos sur le traitement
    //------------------------
    if (l_Index > 0) LOG.INFO(m_StrategyName + IntegerToString(l_Index) + " données lues", __FUNCTION__);

    // Fermeture du fichier
    //---------------------
    FileClose(l_Handle);

    // Nettoie les positions obsolètes
    //--------------------------------
    this.DeleteDetection();
}

//+-----------------------------------------------------------+
//| WriteFile                                                 |
//| Ecriture des données de la stratégie dans un fichier      |
//| INPUT:                                                    |
//|  None                                                     |
//| OUTPUT:                                                   |
//|  None                                                     |
//+-----------------------------------------------------------+
void CDatas::WriteFile(void)
{
    // Variables locales
    //------------------
    bool l_Error;
    int  l_Index;
    int  l_Handle;
    int  l_Count;

    // Sauve si seulement la stratégie est connue
    //--------------------------------------------
    if (m_StrategyName == "") return;
    if (MQLInfoInteger(MQL_TESTER)) return;

    // Ouvre le fichier en lien avec la stratégie
    //--------------------------------------------
    ResetLastError();
    l_Handle = FileOpen(m_Filename, FILE_COMMON|FILE_WRITE|FILE_BIN);

    // En cas d'erreur d'ouvrir de fichier
    //------------------------------------
    if (l_Handle == INVALID_HANDLE)
    {
        LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
        return;
    }

    // Boucle sur les données à sauver
    //--------------------------------
    l_Error = false;
    l_Count = 0;
    for (l_Index = 0; l_Index < ArraySize(m_Detection); l_Index++)
    {
        // Sauve les données si elles sont valides
        //----------------------------------------
        if (m_Detection[l_Index].No_detection > 0)
        {
            ResetLastError();
            if (FileWriteStruct(l_Handle, m_Detection[l_Index]) != sizeof(m_Detection[l_Index]))
            {
                if (!l_Error)
                {
                    LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
                    l_Error = true;
                }
            }

            // Compte le nombre de données sauvées
            //------------------------------------
            else
            {
                l_Count++;
            }
        }
    }

    // Information sur la traitement
    //------------------------------
    if (l_Count > 0) LOG.INFO(m_StrategyName + IntegerToString(l_Count) + " données sauvegargées", __FUNCTION__);
    
    // Ferme le fichier
    //----------------
    FileClose(l_Handle);                
}
