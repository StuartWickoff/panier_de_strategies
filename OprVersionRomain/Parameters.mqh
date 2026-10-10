//+------------------------------------------------------------------+
//| Lecture des données du fichier 'PARAM.dta'                       |
//|                                  ---------                       |
//| Gère la récupération des données du ficgier de paramètres :      |
//| - Horaire de trading                                             |
//| - News importantes                                               |
//| - Paramètres de money management                                 |
//|                                                                  |
//| Le fichier peut contenur les lignes suivantes :                  |
//|                                                                  |
//| - Nouvelles économiques                                          |
//|   NEWS;<date>;<heure>;<impact>;<sécurité>                        |
//|  /!\ (Date et heure UTC)                                         |
//|                                                                  |
//| - Activité de la stratégie                                       |
//|   DAY_START;<heure>                                              |
//|   DAY_END;<heure>                                                |
//|   OFF;<date>                                                     |
//|  /!\ (Date et heure du marché)                                   |
//|                                                                  |
//| - Coupure des positions                                          |
//|   ALL_CUT;<date>;<heure>                                         |
//|   DAY_CUT;<heure>                                                |
//|  /!\ (Date et heure du marché)                                   |
//|                                                                  |
//| - Money management                                               |
//|   RISK;<valeur>                                                  |
//|   DAY_MAXLOSS;<valeur>                                           |
//|   WEEK_MAXLOSS;<valeur>                                          |
//|   TRAILING;<sécurité>                                            |
//|                                                                  |
//| - Etat du robot                                                  |
//|   STOP                                                           |
//|   GO                                                             |
//|   SIMU;<état>                                                    |
//|                                                                  |
//| - Attribut des fonctions                                         |
//|   LOG;<niveau>                                                   |
//|   ALERTE;<texte>;<son>;<notif>                                   |
//|   VISU;<taille>                                                  |
//| Possibilité  d'avoir plusieurs NEWS, OFF et ALL_CUT              |
//| Pour les autres paramètres, le dernier lu a raison               |
//|                                                                  |
//| Les LOGs listent les infos et les erreurs de format              |
//|                                                                  |
//| <date>     a le format : jj/mm/aaaa                              |
//| <heure>    a le format : hh:mm                                   |
//| <valeur>   a le format : xx.xxx                                  |
//| <sécurité> a le format : xxxxx                                   |
//|   -> Pour les news, c'est en seconde autour de la news           |
//|   -> Pour le trailing stop, c'est le nombre de point             |
//| <impact>   a le format : 0, 1, 2, 3 ou 4                         |
//|   -> aucun log, erreur, warning, info, debug                     |
//| <taille> a le format : 1, 2 ou 3                                 |
//| <état>, <texte>, <son> et <notif> ont le format :                |
//| 0 ou 1                                                           |
//|   -> 0 : pas sélectionné et 1 : sélectionné                      |
//|                                                                  |
//+------------------------------------------------------------------+
//|                                                                  |
//| TODO Liste des fonctions avec Grok                               |
//|                                                                  |
//+------------------------------------------------------------------+
//|                                                                  
//| Dépendances :
//| - Fichier Paramaters_private.mqx : Contient les infos privées
//| - Fichier Paramaters_public.mqx  : Contient les infos publiques
//| - Fichier BB_ADX_expert.mqx      : Contient la source compilable
//| - Fichier Tools.mqh              : Contient les fonctions de
//|                                    mise en forme
//| - Fichier Log.mqh                : Contient la gestion des logs  |
//+------------------------------------------------------------------+

//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////

#define K_CParameters_FileName          "PARAM.dta"

#define K_CParameters_MinPeriod         1              // En minute

#define K_CParameters_News              "NEWS"
#define K_CParameters_DayStart          "DAY_START"
#define K_CParameters_DayEnd            "DAY_END"
#define K_CParameters_DayCut            "DAY_CUT"
#define K_CParameters_AllCut            "ALL_CUT"
#define K_CParameters_Off               "OFF"
#define K_CParameters_Risk              "RISK"
#define K_CParameters_DayMaxLoss        "DAY_MAXLOSS"
#define K_CParameters_WeekMaxLoss       "WEEK_MAXLOSS"
#define K_CParameters_Trailing          "TRAILING"
#define K_CParameters_Simu              "SIMU"
#define K_CParameters_Stop              "STOP"
#define K_CParameters_Go                "GO"
#define K_CParameters_Log               "LOG"
#define K_CParameters_Alert             "ALERT"
#define K_CParameters_Visu              "VISU"

//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////

class CParameters
{
//========================================
//---  PRIVATE
//========================================
private:
   // Données du fichier de paramètres
   //---------------------------------
   string   m_Filename;
   uint     m_InterCheck;                 // en minute
   datetime m_ModificationDate;
   datetime m_LastCheck;
   
   // Tableaux
   //---------
   STRUCT_NEWS   m_News[];                // "NEWS"       : Date et impact des news
   datetime      m_PositionClosure[];     // "ALL_CUT"    : Date pour couper toutes les positions ouvertes
   datetime      m_OffDay[];              // "OFF"        : Journée où le robot ne doit rien faire
   
   // Données avec validité
   //----------------------
   STRUCT_DATETIME_VAL     m_TradingStartDay;    // "DAY_START"    : Heure de début des détections
   STRUCT_DATETIME_VAL     m_TradingEndDay;      // "DAY_END"      : Heure de fin des détections
   STRUCT_DATETIME_VAL     m_EndPositionDay;     // "DAY_CUT"      : Heure de clôture des positions ouvertes pour la journée
   STRUCT_DOUBLE_VAL       m_Risk;               // "RISK"         : Niveau de risque pour les positions
   STRUCT_DOUBLE_VAL       m_MaxDayLoss;         // "DAY_MAXLOSS"  : Niveau de perte max pour la journée
   STRUCT_DOUBLE_VAL       m_MaxWeekLoss;        // "WEEK_MAXLOSS" : Niveau de perte max pour la semaine
   STRUCT_DOUBLE_VAL       m_TrailingStop;       // "TRAILING"     : Taille du trailing stop en nombre de points
   bool                    m_Simulation;         // "SIMU"         : Etat du robot en mode 'simulation'
   bool                    m_RobotRunning;       // "STOP" , "GO"  : Etat de fonctionnement du robot
   STRUCT_LOG_VAL          m_LogData;            // "LOG"          : Paramètres de la fonction LOG
   STRUCT_ALERT_VAL        m_AlertData;          // "ALERT"        : Paramètres de la fonction ALERT
   STRUCT_VISU_VAL         m_VisuData;           // "VISU"         : Paramètres de la fonction VISU
   
   // Fonctions
   //----------
   void RazParam       (void);
   void ExtractData    (void);
   
   void RobotAlive     (void);
   void RobotStopped   (void);
   void ReadNews          (const string &i_Param[]);
   void ReadDayStart      (const string &i_Param[]);
   void ReadDayEnd        (const string &i_Param[]);
   void ReadOff           (const string &i_Param[]);
   void ReadDayCut        (const string &i_Param[]);
   void ReadAllCut        (const string &i_Param[]);
   void ReadRisk          (const string &i_Param[]);
   void ReadDayMaxLoss    (const string &i_Param[]);
   void ReadWeekMaxLoss   (const string &i_Param[]);
   void ReadTrailing      (const string &i_Param[]);
   void ReadLog           (const string &i_Param[]);
   void ReadAlert         (const string &i_Param[]);
   void ReadVisu          (const string &i_Param[]);
   void ReadSimuState     (const string &i_Param[]);
   
   double  ExtractDouble     (const string i_Text);
   int     ExtractInteger    (const string i_Text);
   bool    ExtractHour       (const string i_Text, const bool i_clear, datetime &i_hour);
   bool    ExtractDate       (const string i_Text, const bool i_clear, datetime &i_date);

//========================================
//---  PUBLIC
//========================================
public:
   // Fonctions
   //----------
   bool Config(const string i_folder, const uint i_interCheck = K_CParameters_MinPeriod);
   
   bool ConfigOk(void);
   
   string GetFileName(void);
   
   bool CyclicFileAnalysis(void);

   bool ParametersRead(void)       { return(m_ModificationDate != 0); }
   
   // Fonctions pour lire les paramètres
   //-----------------------------------
   bool GetNextNews                 (STRUCT_NEWS &i_news);
   bool GetHourStartTrading         (datetime    &i_date);
   bool GetHourEndTrading           (datetime    &i_date);
   bool GetHourCutPosition          (datetime    &i_date);
   bool GetDateHardCut              (datetime    &i_date);
   bool GetRiskLevel                (double      &i_risk);          
   bool GetMaxDayLoss               (double      &i_dayMaxLoss);
   bool GetMaxWeekLoss              (double      &i_weekMaxLoss);
   bool GetTrailingStop             (double      &i_trailingStopSize);
   bool GetVisuHeight               (int         &i_VisuHeight);
   
   // Fonctions pour récupérer et analyser le contexte
   //-------------------------------------------------
   bool HourOfTrading        (void);
   bool DayOfTrading         (void);
   bool OutsideCutZone       (void);
   bool OutsideSecurityZone  (void);
   bool RobotIsRun           (void)   { return(m_RobotRunning);}
   bool RobotInSimulation    (void)   { return(m_Simulation)  ;}
};


//////////////////////////////////////////////////////////
//                                                      //
//              F U N C T I O N S                       //
//                                                      //
//////////////////////////////////////////////////////////

#include <OPR_Bot/Parameters_public.mqh>

#include <OPR_Bot/Parameters_private.mqh>