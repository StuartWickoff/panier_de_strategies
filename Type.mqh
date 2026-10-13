//+------------------------------------------------------------------+
//| Contenaire de toutes les fonctions générales, tous les types
//| énumérés communs aux logiciels et toutes les structures    
//| générales pouvant être utilisées         
//| (Le code est compatible MT4/MT5)                                 
//+------------------------------------------------------------------+
//|
//| Historique de Type.mqh
//|
//|   V1 : Création du fichier
//|
//|   V2 : Ajout des types pour les paramètres
//|
//|   V3 : Ajout de l'énuméré pour le niveau des logs
//|
//|   V4 : Retrait du marché pour les news
//|
//|
//|
//|
//|
//|


//////////////////////////////////////////////////////////
//                                                      //
//                C O N S T A N T S                     //
//                                                      //
//////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////
//                                                      //
//                   E N M E R E S                      //
//                                                      //
//////////////////////////////////////////////////////////

// Tendance
//---------
enum ENUM_TREND
{
   eT_Unknown = 0 ,
   eT_Bear        ,
   eT_Bull        ,
};

// Niveau d'importance
//--------------------
enum ENUM_IMPACT_LEVEL
{
   eI_Nothing = 0 ,  // Aucun impact
   eI_Minor       ,  // Mineur
   eI_Medium      ,  // Moyen
   eI_Major       ,  // Majeur
};

// Niveaux de logs
//----------------
enum ENUM_LOG_LEVEL
{
   eL_Nothing = 0 ,  // Aucun log
   eL_Error       ,  // Erreur
   eL_Warning     ,  // Warning et erreur
   eL_Info        ,  // Info, warning et erreur
   eL_All         ,  // Tout
};

// Taille de l'affichage
//----------------------
enum ENUM_VISU
{
   eV_Nothing = 0 ,  // Aucun affichage
   eV_Small       ,  // Petit affichage
   eV_Medium      ,  // Moyen affichage
   eV_Large       ,  // Grand affichage
};

//////////////////////////////////////////////////////////
//                                                      //
//                S T R U C T U R E                     //
//                                                      //
//////////////////////////////////////////////////////////

// Datatime avec validité
//-----------------------
struct STRUCT_DATETIME_VAL
{
   bool     valid;
   datetime value;
};

// Integer avec validité
//----------------------
struct STRUCT_INT_VAL
{
   bool     valid;
   int      value;
};

// Double avec validité
//---------------------
struct STRUCT_DOUBLE_VAL
{
   bool     valid;
   double   value;
};

// Données de la fonction LOG avec validité
//------------------------------------------
struct STRUCT_LOG_VAL
{
   bool     valid;
   int      level;
};

// Données de la fonction ALERTE avec validité
//---------------------------------------------
struct STRUCT_ALERT_VAL
{
   bool     valid;
   bool     text;
   bool     sound;
   bool     notif;
};


// Données de la fonction VISU avec validité
//------------------------------------------
struct STRUCT_VISU_VAL
{
   bool     valid;
   int      height;
};


// Données pour une news
//----------------------
struct STRUCT_NEWS
{
   datetime            date;       // Date (Heure locale)
   ENUM_IMPACT_LEVEL   impact;     // Niveau d'impact
   int                 security;   // Nombre de minute sans detection autour
};

// Informations sur une détection d'opportunité
//---------------------------------------------
struct STRUCT_STRATEGY
{
   int           No_detection;
   int           No_ticket;
   ENUM_TREND    Trend;
   double        Size;
   double        Entry;
   double        StopLoss;
   double        TakeProfit;
   bool          IsMarketOrder;   // Bascule dynamique : true = ordre au marché, false = ordre stop
};

