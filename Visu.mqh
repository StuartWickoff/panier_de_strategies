//+------------------------------------------------------
//| Classe pour gérer l'affichage des états sur le graphique
//| (Le code est compatible MT4 et MT5)
//|
//| - Affichage présent ou de différentes tailles
//| - Configuration du nombre d'informations affichées
//| - Adaptation automatique de l'affichage
//|
//+------------------------------------------------------
//| Liste  des fonctions : (A compléter avec IA)
 
//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////

#define     K_CVisu_StateNb      20

#define     K_CVisu_False        0
#define     K_CVisu_True         1
#define     K_CVisu_Indefined    2

#define     K_CVisu_FalseClr     clrRed
#define     K_CVisu_TrueClr      clrBeige
#define     K_CVisu_ClrSide      clrBlack

#define     K_CVisu_Height1      10
#define     K_CVisu_Height2      20
#define     K_CVisu_Height3      30

#define     K_CVisu_ClrOn        clrBeige
#define     K_CVisu_ClrOff       clrRed
#define     K_CVisu_ClrSimu      clrBlue

#define     BOOL_TO_VISU(b)      (b) ? K_CVisu_True : K_CVisu_False

//////////////////////////////////////////////////////////
//                                                      //
//                   C L A S S                          //
//                                                      //
//////////////////////////////////////////////////////////

class CVisu
{
//========================================
//--- PRIVATE
//========================================
private:
    // Données
    //--------
    color   m_SquareClr;                     // Couleur du cadre
    string  m_Prefix;                        // Préfixe des objets graphiques
    int     m_Height;                        // Taille des carrés
    int     m_CoorGraphX;
    int     m_CoorGraphY;
    int     m_State[K_CVisu_StateNb];        // Etat de chaque info à afficher
    int     m_Memo[K_CVisu_StateNb];         // Etat de chaque info qui a été affichée
    string  m_Text[K_CVisu_StateNb];         // Détail de chaque info à afficher

    // Fonctions
    //----------    
    void   Erase(void);
    void   Draw(void);

//========================================
//--- PUBLIC
//========================================
public:
    // Fonctions
    //----------
    void    Config(const string i_prefix, const int i_height);
    void    End(void)                                            { this.Erase(); }
    bool    HeightIsValid(const int i_height);
    void    SetHeight(const int i_height);
    void    SetValue(const int i_index, const int i_value = K_CVisu_Indefined);
    void    Reset(const int i_index);
    void    SetText(const int i_index, const string i_text = "");
    void    UpdateText(const int i_index, const string i_text = " ");
    void    Show(void);                                                                  // Affiche si changement de données
                                                                                         // A appeler cycliquement

    void    ReDraw(void);                                                                // Affiche si changement de données, mémorise les nouvelles
                                                                                         // A appeler dans 'OnChartEvent'
};

//////////////////////////////////////////////////////////
//                                                      //
//              F U N C T I O N S                       //
//                                                      //
//////////////////////////////////////////////////////////
//+----------------------------------------------------------------+
//| Config                                                         |
//| Renseigne les infos de l'objet                                 |
//| INPUT:                                                         |
//|  Préfixe des objets graphiques                                 |
//| Taille des objets entre 1 inclus et 3 inclus                   |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::Config(const string i_prefix, const int i_height)
{   
    // Variable locale
    //---------------
    int   l_Loop;

    // Initialisation
    //---------------
    m_SquareClr  = clrNONE;
    m_CoorGraphX = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    m_CoorGraphY = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

    // Efface le tableau des valeurs
    //------------------------------
    ArrayInitialize(m_State, K_CVisu_Indefined);
    ArrayInitialize(m_Memo, K_CVisu_Indefined);

    // Efface le tableau des textes
    //-----------------------------
    for (l_Loop = 0; l_Loop < K_CVisu_StateNb; l_Loop++) 
    {
        m_Text[l_Loop] = "";
    }

    // Mets à jour les paramètres de l'objet
    //--------------------------------------
    this.SetHeight(i_height);

    // On efface les anciens objets
    //----------------------------
    m_Prefix = i_prefix;
    this.Erase();
}

//+----------------------------------------------------------------+
//| HeightIsValid                                                  |
//| Test la taille en paramètre pour définir si valide ou non      |
//| INPUT:                                                         |
//|  Taille à tester                                               |
//| OUTPUT:                                                        |
//| TRUE si la taille est valide                                   |
//+----------------------------------------------------------------+
bool CVisu::HeightIsValid(const int i_height)
{
    return ((i_height >= eV_Nothing) && (i_height <= eV_Large));
}
//+----------------------------------------------------------------+
//| SetHeight                                                      |
//| Renseigne les paramètres de l'objet                            |
//| INPUT:                                                         |
//|  Taille des objets entre 1 inclus et 3 inclus                  |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::SetHeight(const int i_height)
{
    // Définition de la taille des objets graphiques
    //---------------------------------------------
    switch (i_height)
    {
        case eV_Nothing    : m_Height = 0; break;
        case eV_Small      : m_Height = K_CVisu_Height1; break;
        case eV_Medium     : m_Height = K_CVisu_Height2; break;
        case eV_Large      : m_Height = K_CVisu_Height3; break;
        default : 
            LOG.WARNING("Taille incorrecte, Pas d'affichage.", __FUNCTION__);
            m_Height = 0;
    }

    // Au cas où l'affichage est déjà en place
    //----------------------------------------
    this.Draw();
}

//+----------------------------------------------------------------+
//| SetValue                                                       |
//| Ajout d'un état pour l'affichage                               |
//| INPUT:                                                         |
//|  Index de l'info à afficher                                    |
//|  Valeur à afficher                                             |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::SetValue(const int i_index, int i_value = K_CVisu_Indefined)
{
    // Vérification de l'index
    //------------------------
    if (i_index < 0 || i_index >= K_CVisu_StateNb)
    {
        LOG.WARNING("Index '" + IntegerToString(i_index) + "' hors limite !!!" , __FUNCTION__);
        return;
    }

    // Vérification de la valeur de l'état
    //------------------------------------
    if ((i_value != K_CVisu_False) && (i_value != K_CVisu_True))
    {
        i_value = K_CVisu_Indefined;
    }

    // Mise à jour de l'information
    //-----------------------------
    m_State[i_index] = i_value;
}

//+----------------------------------------------------------------+
//| Reset                                                          |
//| Retrait d'un état pour l'affichage                             |
//| INPUT:                                                         |
//|  Index d'une valeur à supprimer                                |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::Reset(const int i_index)
{
    this.SetValue(i_index, K_CVisu_Indefined);
}

//+----------------------------------------------------------------+
//| SetText                                                        |
//| Ajout d'un texte pour le survol de la souris                   |
//| INPUT:                                                         |
//|  Index d'une valeur à afficher                                 |
//|  Texte à afficher                                              |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::SetText(const int i_index, const string i_text = "")
{
    // Vérification de l'index
    //------------------------
    if ((i_index < 0) || (i_index >= K_CVisu_StateNb))
    {
        LOG.WARNING("Index '" + IntegerToString(i_index) + "' hors limite !!!" , __FUNCTION__);
        return;
    }

    // Mise à jour de l'information
    //-----------------------------
    m_Text[i_index] = i_text;
}

//+----------------------------------------------------------------+
//| UpdateText                                                     |
//| Change le texte pour le survol de la souris                    |
//| INPUT:                                                         |
//|  Index d'une valeur à afficher                                 |
//|  Texte à afficher                                              |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::UpdateText(const int i_index, const string i_text = " ")
{
    // Données locales
    //----------------
    string    l_Name;

    // Vérification de l'index
    //------------------------
    if ((i_index < 0) || (i_index >= K_CVisu_StateNb))
    {
        LOG.WARNING("Index '" + IntegerToString(i_index) + "' hors limite !!!" , __FUNCTION__);
        return;
    }

    // Mise à jour de l'information
    //-----------------------------
    m_Text[i_index] = i_text;

    // Mise à jour de l'affichage
    //---------------------------
    if ((m_Height == 0) || (m_Prefix == "")) return;

    l_Name = m_Prefix + IntegerToString(i_index);
    ObjectSetString(0, l_Name, OBJPROP_TOOLTIP, i_text);

}

//+----------------------------------------------------------------+
//| Show                                                           |
//| Affiche les objets graphiques en fonction des états            |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::Show(void)
{
    // Variables locales
    //------------------
    int    l_Loop;
    bool   l_Show;

    // Pas d'affichage ou pas configuré
    //---------------------------------
    if ((m_Height == 0) || (m_Prefix == "")) return;

    // Analyse si un changement est intervenu
    //---------------------------------------
    l_Show = false;
    for (l_Loop = 0; l_Loop < K_CVisu_StateNb; l_Loop++)
    {
        if (m_State[l_Loop] != m_Memo[l_Loop])
        {
            l_Show = true;
            break;
        }
    }

    // Mise à jour de l'affichage
    //---------------------------
    if (l_Show)
    {
        this.Draw();
    }
}

//+----------------------------------------------------------------+
//| ReDraw                                                         |
//| Redessine les objets graphiques si la taille change            |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::ReDraw(void)
{
    // Pas d'affichage ou pas configuré
    //---------------------------------
    if ((m_Height == 0) || (m_Prefix == "")) return;

    // Teste si la taille a changé
    //----------------------------
    if ((m_CoorGraphX != ChartGetInteger(0, CHART_WIDTH_IN_PIXELS)) || (m_CoorGraphY != ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS)))
    {
        // Nouvelle taille et dessine les objets
        //--------------------------------------
        m_CoorGraphX = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
        m_CoorGraphY = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
        this.Draw();
    }
}
//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////

//+----------------------------------------------------------------+
//| Erase                                                          |
//| Efface les objets graphiques                                   |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::Erase(void)
{
    // Supprime tous les graphiques si le préfixe est défini
    //-------------------------------------------------------
    if (m_Prefix != "")
    {
        ObjectsDeleteAll(0, m_Prefix);
        ChartRedraw(0);
    }
}

//+----------------------------------------------------------------+
//| Draw                                                           |
//| Affiche les objets graphiques en fonction des états            |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CVisu::Draw(void)
{
    // Variables locales
    //------------------
    int    l_Loop;
    int    l_StateNb;
    int    l_PosX;
    string l_Name;
    color  l_Color;

    // Efface les objets qui vont être mis à jour
    //-------------------------------------------
    this.Erase();

    // Pas d'affichage si pas demandé
    //-------------------------------
    if (m_Height == 0) return;

    // Cherche le nombre d'états à afficher
    //--------------------------------------
    l_StateNb = 0;
    for (l_Loop = 0; l_Loop < K_CVisu_StateNb; l_Loop++)
    {
        if ((m_State[l_Loop] == K_CVisu_False) || (m_State[l_Loop] == K_CVisu_True))
        {
            l_StateNb = l_Loop + 1;
        }

        // Mémorise l'état de chaque objet
        //--------------------------------
        m_Memo[l_Loop] = m_State[l_Loop];
    }

    // Pas d'affichage si possible
    //----------------------------
    if (l_StateNb == 0) return;
    
    // Teste si les objets tiennent sur la largeur du graphique
    //---------------------------------------------------------
    if ((m_Height * l_StateNb) >= m_CoorGraphX) return;

    // Affichage de la boîte des infos
    //-------------------------------
    l_PosX = ((m_CoorGraphX - (m_Height * l_StateNb)) / 2) - 4;
    l_Name = m_Prefix + "box";
    if (ObjectCreate(0, l_Name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
    {
        // Couleur de la boîte d'état du robot
        //-------------------------------------
        if (!CONTEXT.GetRunState())
        {
            m_SquareClr = K_CVisu_ClrOff;
            ObjectSetString(0, l_Name, OBJPROP_TOOLTIP, "Robot Off");
        }
        else if (CONTEXT.GetSimuState())
        {
            m_SquareClr = K_CVisu_ClrSimu;
            ObjectSetString(0, l_Name, OBJPROP_TOOLTIP, "Robot en simulation");
        }
        else
        {
            m_SquareClr = K_CVisu_ClrOn;
            ObjectSetString(0, l_Name, OBJPROP_TOOLTIP, "Robot en activité");
        }

        ObjectSetInteger(0, l_Name, OBJPROP_XDISTANCE    , l_PosX);
        ObjectSetInteger(0, l_Name, OBJPROP_YDISTANCE    , 0);
        ObjectSetInteger(0, l_Name, OBJPROP_XSIZE        , m_Height * l_StateNb + 8);
        ObjectSetInteger(0, l_Name, OBJPROP_YSIZE        , m_Height + 8);
        ObjectSetInteger(0, l_Name, OBJPROP_BGCOLOR      , clrNONE);
        ObjectSetInteger(0, l_Name, OBJPROP_BORDER_TYPE  , BORDER_FLAT);
        ObjectSetInteger(0, l_Name, OBJPROP_CORNER       , CORNER_LEFT_UPPER);
        ObjectSetInteger(0, l_Name, OBJPROP_COLOR        , m_SquareClr);
        ObjectSetInteger(0, l_Name, OBJPROP_STYLE        , STYLE_SOLID);
        ObjectSetInteger(0, l_Name, OBJPROP_WIDTH        , 2);
        ObjectSetInteger(0, l_Name, OBJPROP_BACK         , false);
        ObjectSetInteger(0, l_Name, OBJPROP_SELECTABLE   , false);
        ObjectSetInteger(0, l_Name, OBJPROP_SELECTED     , false);
        ObjectSetInteger(0, l_Name, OBJPROP_HIDDEN       , true);
        ObjectSetInteger(0, l_Name, OBJPROP_ZORDER       , 0);
    }

    // Dessine tous les objets
    //-----------------------
    l_PosX = ((m_CoorGraphX - (m_Height * l_StateNb)) / 2);
    for (l_Loop = 0; l_Loop < l_StateNb; l_Loop++)
    {
        // Affiche uniquement si un état est valide
        //-----------------------------------------
        if ((m_State[l_Loop] == K_CVisu_False) || (m_State[l_Loop] == K_CVisu_True))
        {
            l_Color = (m_State[l_Loop] == K_CVisu_False) ? K_CVisu_FalseClr : K_CVisu_TrueClr;   
            l_Name = m_Prefix + IntegerToString(l_Loop);
            if (ObjectCreate(0, l_Name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
            {
                ObjectSetInteger(0, l_Name, OBJPROP_XDISTANCE    , l_PosX);
                ObjectSetInteger(0, l_Name, OBJPROP_YDISTANCE    , 4);
                ObjectSetInteger(0, l_Name, OBJPROP_XSIZE        , m_Height);
                ObjectSetInteger(0, l_Name, OBJPROP_YSIZE        , m_Height);
                ObjectSetInteger(0, l_Name, OBJPROP_BGCOLOR      , l_Color);
                ObjectSetInteger(0, l_Name, OBJPROP_BORDER_TYPE  , BORDER_FLAT);
                ObjectSetInteger(0, l_Name, OBJPROP_CORNER       , CORNER_LEFT_UPPER);
                ObjectSetInteger(0, l_Name, OBJPROP_COLOR        , K_CVisu_ClrSide);
                ObjectSetInteger(0, l_Name, OBJPROP_STYLE        , STYLE_SOLID);
                ObjectSetInteger(0, l_Name, OBJPROP_WIDTH        , 1);
                ObjectSetInteger(0, l_Name, OBJPROP_BACK         , false);
                ObjectSetInteger(0, l_Name, OBJPROP_SELECTABLE   , false);
                ObjectSetInteger(0, l_Name, OBJPROP_SELECTED     , false);
                ObjectSetInteger(0, l_Name, OBJPROP_HIDDEN       , true);
                ObjectSetInteger(0, l_Name, OBJPROP_ZORDER       , 0);
                if (m_Text[l_Loop] != "")
                {
                    ObjectSetString(0, l_Name, OBJPROP_TOOLTIP, m_Text[l_Loop]);
                }
            }
        }

        // Passage au suivant
        //-------------------
        l_PosX += m_Height;
    }
    ChartRedraw();
}