//+---------------------------------------------------------------+
//| Corps du robot avec centralisation des opérations             |
//|                                                               |
//| (Le code est compatible MT4/MT5)                              |
//|                                                               |
//+---------------------------------------------------------------+
//|                                                               |
//| 
//|                                                               |
//+---------------------------------------------------------------+
//|                                                               |
//| TODO avec Grok : Liste des fonctions et leur rôle             |
//|
//+---------------------------------------------------------------+
//| Dépendances :
//| - Fichier Tools.mqh         : Contient les fonctions de mise
//|                               en forme
//| - Fichier Type.mqh          : Contient les constantes et les 
//|                               types généraux
//| - Fichier Log.mqh           : Contient la gestion des logs
//|
//| - Fichier Alert.mqh         : Contient la gestion des alertes
//|
//| - Fichier Parameters.mqh    : Contient la gestion des paramètres
//|
//|
//|
//+---------------------------------------------------------------+

//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////
#define K_Magic               1000000               // Magic number :  avec N° du bot
#define K_Repertory           "Koenigin\\"
#define K_SoftName            "Koenigin"
#define K_AlertSoundName      "alert.wav"
#define K_Cyclic              1                     // Traitement cyclique toutes les secondes


//////////////////////////////////////////////////////////
//                                                      //
//              I N C L U D E S                         //
//                                                      //
//////////////////////////////////////////////////////////
// 1. Type.mqh en premier : fournit les ENUM_* utilisés par les input
//    (ENUM_LOG_LEVEL, ENUM_VISU, ENUM_TIMEFRAMES, ENUM_APPLIED_PRICE,
//     ENUM_TREND, STRUCT_STRATEGY, etc.)
#include <Koenigin/Type.mqh>

//////////////////////////////////////////////////////////
//                                                      //
//              E N U M S   L O C A U X                 //
//                                                      //
//////////////////////////////////////////////////////////
// Déclarés AVANT les input qui les utilisent.
enum ENUM_BALANCE_MODE
{
    eBM_Fixed    ,  // Balance fixe (intérêts simples)
    eBM_Compound ,  // Balance réelle du compte (intérêts composés)
};

//////////////////////////////////////////////////////////
//                                                      //
//              I N P U T S                             //
//                                                      //
//////////////////////////////////////////////////////////
// ✅ FIX ChatGPT : les input GLOBAUX sont déclarés AVANT tout #include
// qui les utilise. Convention "panier de stratégies" : chaque scanner
// déclare SES inputs dans SON propre fichier (auto-contenu) — cf.
// Scanner_ema50.mqh (K_EMA50_TF, K_EMA50_Period, K_EMA50_SL_Bars,
// K_EMA50_TP_R).
//========================================================
input uint                I_TAILLE_DU_COMPTE     = 25000;          // Taille du compte de trading (balance initiale)
input ENUM_BALANCE_MODE   K_BalanceMode            = eBM_Compound;  // Mode de calcul du risque
input uint                I_Robot_ID             = 0;             // ID unique du robot sur MetaTrader
input bool                I_Text_Alert           = true;          // Alerte texte écran
input bool                I_Sound_Alert          = true;          // Alerte sonore
input bool                I_Notif_Alert          = true;          // Alerte notification
input ENUM_LOG_LEVEL      I_Log_Level            = eL_All;        // Niveau des logs
input ENUM_VISU           I_Visu_Height          = eV_Nothing;    // Taille affichage états
input uint                I_Deviation            = 10;            // Slippage autorisé
input double              K_Max_Risk_Auth        = 2.5;           // Risque max autorisé pour fallback MinLot (%)

//////////////////////////////////////////////////////////
//                                                      //
//    I N C L U D E S   (après input)                   //
//                                                      //
//////////////////////////////////////////////////////////
// Maintenant on peut inclure le reste du framework + Strategy.mqh
// qui utilise les input ci-dessus.
#include <Koenigin/Tools.mqh>
#include <Koenigin/Log.mqh>
#include <Koenigin/Alert.mqh>
#include <Koenigin/Parameters.mqh>
#include <Koenigin/Context.mqh>
#include <Koenigin/Money.mqh>
#include <Koenigin/Visu.mqh>
#include <Koenigin/Monitoring.mqh>
#include <Koenigin/Broker.mqh>
// =====================================================================
// Architecture Koenigin :
//   - Strategy.mqh     : la LIAISON (orchestre les scanners, envoie les ordres)
//   - Scanner.mqh      : TEMPLATE de base (classe CScanner concrète)
//   - Scanner_ema50.mqh : scanner concret CScannerEma50 (EMA50 crossUp
//     long + crossDown short optionnel K_EMA50_Short / SL N extrêmes /
//     TP 2R) — BRANCHÉ, trade soumis à sélection panier (K_EMA50_Trade, false par défaut)
//   - Scanner_rsi7.mqh : scanner concret CScannerRsi7 (RSI7 divergence
//     cachée haussière sur pivots 7 barres stricts / gap 5-60 / SL
//     lowest N / TP 3R / long + short optionnel K_RSI7_Short (div.
//     cachée baissière, machine à pivots hauts indépendante),
//     scanner À ÉTAT avec UpdateState avant filtres (contrat bool :
//     retry au tick suivant tant que la bougie n'est pas traitée,
//     rattrapage chronologique, pas d'entrée rétroactive au
//     démarrage) + backfill historique) — BRANCHÉ, trade
//     soumis à sélection panier (K_RSI7_Trade, false par défaut)
//   - Scanner_bb10.mqh : scanner concret CScannerBb10 (Bollinger 10/2σ
//     réintégration : LONG = 1re clôture de retour au-dessus de la
//     bande basse (Pine 05_BOLLINGER, SL5 TP3R) + short optionnel
//     K_BB10_Short (miroir bande haute — touche personnelle Koenigin) ;
//     bande calculée à la demande (SMA + stdev population manuelles) ;
//     SANS ÉTAT glissant mais décision FIGÉE par bougie : EvaluateBar()
//     avant filtres (contrat bool — retry au tick suivant si lecture
//     impossible, signal préservé) + armement au démarrage (aucune
//     entrée rétroactive) + validation fail-fast des inputs ; sizing =
//     module MONEY — capital virtuel du Pine non reproduit (décision
//     utilisateur)) — BRANCHÉ, trade soumis à sélection panier
//     (K_BB10_Trade, false par défaut)
//   - Scanner_fibo.mqh  : scanner concret CScannerFibo (MODÈLE — non branché)
//   - Plus tard : Scanner_xxx.mqh, ...
// =====================================================================
#include <Koenigin/Strategy.mqh>


//////////////////////////////////////////////////////////
//                                                      //
//                   D A T A S                          //
//                                                      //
//////////////////////////////////////////////////////////

 

//============================================
//---   Variables globales
//============================================
int   G_DeInit = -1;

//============================================
//---   objects
//============================================
CLog              LOG;
CAlert            ALERT;
CParameters       PARAM;
CContext          CONTEXT;
CMoney            MONEY;
CVisu             VISU;
CMonitoring       MONITORING;
CBroker           BROKER;
CStrategy         STRAT;


////////////////////////////////////////////////////////////////////
///                                                              ///
///             ###  #   #    ### #   # ### #####                ///
///            #   # ##  #     #  ##  #  #    #                  ///
///            #   # # # #     #  # # #  #    #                  ///
///            #   # #  ##     #  #  ##  #    #                  ///
///             ###  #   #    ### #   # ###   #                  ///
///                                                              ///
////////////////////////////////////////////////////////////////////
int OnInit(void)
{   
   // Variable locale
   //----------------
   bool l_CorrectInit;

   // ✅ FIX #11 (RÉVISÉ — multi-symboles) : symbole lu automatiquement
   // L'input I_Symbol_Name et son guard ont été retirés : ils bloquaient
   // les optimisations multi-symboles (chaque passe sur un nouveau
   // symbole échouait au guard → INIT_FAILED → backtest stoppé, et il
   // fallait modifier l'input à la main à chaque fois).
   // Le symbole est maintenant lu via Symbol(), équivalent exact de la
   // variable prédéfinie _Symbol = nom du symbole du chart courant
   // (doc officielle mql5.com/en/docs/predefined/_symbol). Dans le
   // testeur, le "chart courant" est le symbole de la passe en cours
   // → chaque passe d'optimisation récupère automatiquement le bon
   // symbole. Tout le code (scanners, broker, management) utilise
   // déjà Symbol() : l'EA trade TOUJOURS le symbole du chart/testeur.
   // Compromis assumé : plus de garde contre un attach sur le mauvais
   // chart en live → le symbole est journalisé ICI (Experts) et dans
   // le fichier de log (après LOG.Config) pour traçabilité complète.
   //----------------------------------------------------------------
   Print("Koenigin : symbole tradé = ", Symbol(), " (lu automatiquement du chart/testeur)");

   // Initialise le système de log
   //-----------------------------
   l_CorrectInit = LOG.Config(K_Repertory);
   LOG.SetLevel(I_Log_Level);

   // Journalise le symbole dans le fichier de log (traçabilité
   // multi-symboles — cf. FIX #11 révisé ci-dessus)
   //--------------------------------------------------------------
   LOG.INFO("Symbole tradé = " + Symbol() + " (lu automatiquement du chart/testeur)", __FUNCTION__);

   // Initialise le système d'alerte
   //-------------------------------
   ALERT.Config(K_SoftName, K_AlertSoundName);
   ALERT.AlertType(I_Text_Alert, I_Sound_Alert, I_Notif_Alert);

   // Initialise les données pour le contrôle budgétaire
   //---------------------------------------------------
   MONEY.Config();
   MONEY.SetMaxRiskAuth(K_Max_Risk_Auth);

   // Initialise le contrôle du contexte
   //-----------------------------------
   CONTEXT.Config();
   
   // Initialise le système de paramètres
   //------------------------------------
   l_CorrectInit &= PARAM.Config(K_Repertory);  //--- Similaire à i += 1

   // Initialise le système d'affichage
   //----------------------------------
   VISU.Config(IntegerToString(K_Magic), I_Visu_Height);

   // Initialise le système de surveillance
   //--------------------------------------
   MONITORING.Config();

   // Initialisation de la stratégie
   //-------------------------------
   l_CorrectInit &= STRAT.Config("Koenigin", PERIOD_CURRENT, K_Repertory);
   
   // Validation du contexte
   //-----------------------
   if (!l_CorrectInit || (G_DeInit != REASON_CHARTCHANGE))
   {
      if (!ContextValidation(l_CorrectInit))
      {
         return(INIT_FAILED);
      }
   }

   // Tentative d'initialisation des traitements cycliques
   //-----------------------------------------------------
   if (!MQLInfoInteger(MQL_TESTER))
   {
      ResetLastError();
      if (!EventSetTimer(K_Cyclic))
      {
         LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
         return(INIT_FAILED);
      }
   }

   // Lancement du premier traitement général pour vérifier que tout est correct
   //---------------------------------------------------------------------------
   if (!RegularTreatments())
   {
      Alert("Absence de fichier 'Param.dta', exécution impossible !");
      LOG.ERROR("Absence de fichier 'Param.dta', exécution impossible !", __FUNCTION__);
      return(INIT_FAILED);
   }
   
   // Retour sans erreur
   //-------------------
   return(INIT_SUCCEEDED);
}

////////////////////////////////////////////////////////////////////
///                                                              ///
///          ###  #   #    ####  #### ### #   # ### #####        ///
///         #   # ##  #    #   # #     #  ##  #  #    #          ///
///         #   # # # #    #   # ###   #  # # #  #    #          ///
///         #   # #  ##    #   # #     #  #  ##  #    #          ///
///          ###  #   #    ####  #### ### #   # ###   #          ///
///                                                              ///
////////////////////////////////////////////////////////////////////
void OnDeinit(const int reason)
{
   EventKillTimer();
   LOG.End();
   STRAT.End();
   VISU.End();
   G_DeInit = reason;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
///                                                                                              ///
///          ###  #   #     ###  #   #  ###  ####  #####    ##### #     # ##### #   # #####      ///
///         #   # ##  #    #   # #   # #   # #   #   #      #     #     # #     ##  #   #        ///
///         #   # # # #    #     ##### ##### ####    #      ###    #   #  ###   # # #   #        /// 
///         #   # #  ##    #   # #   # #   # #  #    #      #       # #   #     #  ##   #        ///
///          ###  #   #     ###  #   # #   # #   #   #      #####    #    ##### #   #   #        ///
///                                                                                              ///
////////////////////////////////////////////////////////////////////////////////////////////////////
void OnChartEvent(const int      id,          // Event ID
                  const long&    lparam,      // Parameter of type long event
                  const double&  dparam,      // Parameter of type double event
                  const string&  sparam)      // Parameter of type string event
{
   // Variable locale
   //----------------
   ENUM_CHART_EVENT l_Event;                  // Evénement graphique

   // Traduit en type réel
   //---------------------
   l_Event = (ENUM_CHART_EVENT)id;
   
   // Traitement si l'affichage change
   //---------------------------------
   if (l_Event == CHARTEVENT_CHART_CHANGE)
   {
      // Mise à jour de l'affichage
      //---------------------------
      VISU.ReDraw();
   }
}

////////////////////////////////////////////////////////////////////
///                                                              ///
///             ###  #   #    ##### ### #   # #### ####          ///
///            #   # ##  #      #    #  ## ## #    #   #         ///
///            #   # # # #      #    #  # # # ###  ####          ///
///            #   # #  ##      #    #  #   # #    #  #          ///
///             ###  #   #      #   ### #   # #### #   #         ///
///                                                              ///
////////////////////////////////////////////////////////////////////
void OnTimer()
{
   // Effectue les traitements à faire régulièrement
   //-----------------------------------------------
   RegularTreatments();

   // ✅ Annulation des ordres même sans tick (marché gelé pendant news)
   //-------------------------------------------------------------------
   if (MONITORING.ReadyForStrategy())
   {
       STRAT.ManagePositions();
   }
}

////////////////////////////////////////////////////////////////////
///                                                              ///
///             ###  #   #    ##### ###  ### #   #               ///
///            #   # ##  #      #    #  #    #  #                ///
///            #   # # # #      #    #  #    ###                 ///
///            #   # #  ##      #    #  #    #  #                ///
///             ###  #   #      #   ###  ### #   #               ///
///                                                              ///
////////////////////////////////////////////////////////////////////
void OnTick()
{
   // Effectue les traitements à faire régulièrement
   //-----------------------------------------------
   RegularTreatments();

   // Traite la stratégie si les contextes sont bons
   //-----------------------------------------------
   if (!MONITORING.ReadyForStrategy()) return;
   
   // ✅ GESTION DES POSITIONS À CHAQUE TICK (BE, Trailing Stop, etc.)
   //------------------------------------------------------------------

   STRAT.ManagePositions();

   // ✅ FIX ChatGPT #2 : Detection() à chaque tick.
   // Strategy décide en interne s'il y a une nouvelle bougie sur le
   // TF du scanner (anti-rejeu basé sur iTime(Symbol(), TF, 0),
   // pas sur PERIOD_CURRENT). Comme ça, l'EA peut être attachée
   // sur n'importe quel TF de chart (M15, H1, H4) et le scanner
   // sera quand même appelé à chaque clôture de son TF.
   //------------------------------------------------------------------
   STRAT.Detection();
}

/////////////////////////////////////////////////////////////////////
//                                                                 //
//       ##### #   # #   #  ###  ##### ###  ###  #   #  ####       //
//       #     #   # ##  # #   #   #    #  #   # ##  # #           //
//  ###  ###   #   # # # # #       #    #  #   # # # #  ###    ### //
//       #     #   # #  ## #   #   #    #  #   # #  ##     #       //
//       #      ###  #   #  ###    #   ###  ###  #   # ####        //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//+--------------------------------------------------------------------+
//| ContextValidation                                                  |
//| Récupère les infos des objets LOG et PARAM pour les valider        |
//| INPUT:                                                             |
//|  TRUE si les initialisations ont été faites sans erreur            |
//| OUTPUT:                                                            |
//|  TRUE si le contexte est validé                                    |
//+--------------------------------------------------------------------+
bool ContextValidation(const bool i_initResult)
{
   // Variable locale
   //----------------
   string   l_Text;
   int      l_FlagMessageBox;
   int      l_ResponseMessageBox;

   // Pour mémorisation dans les logs MetaTrader
   //-------------------------------------------
   Print(LOG.GetFolder());
   Print(PARAM.GetFileName());
   
   // Informations sur le contexte
   //-----------------------------
   l_Text               = LOG.GetFolder() + "\n\n";
   l_Text              += PARAM.GetFileName() + "\n\n";
   l_Text              += (STRAT.ConfigOk()) ? " Stratégie correctement initialisée.\n" :
                                               " Stratégie mal configurée.\n";
   l_Text              += (i_initResult) ? "" :
                                           "\nDoit-on continuer ?\n";
   l_FlagMessageBox     = (i_initResult) ? MB_OK | MB_ICONINFORMATION | MB_DEFBUTTON1 :
                                           MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2;
   l_ResponseMessageBox = MessageBox(l_Text, "Infos de démarrage", l_FlagMessageBox);
   
   if (l_ResponseMessageBox == IDNO)
   {
      return(false);
   }
   
   // Contexte valide
   //----------------
   return(true);
                                             
}

/*
ParametersExtraction
Extrait les paramètres et configure les différentes fonctions
(Pour les LOG et ALERTE, c'est directement dans les param.)
(Tous les paramètres temporels sont dans les paramètres)
INPUT
*/
void ParametersExtraction(void)
{
   // Variable locale
   //----------------
   double l_DoubleValue;
   int    l_IntValue;
   
   // Renseigne les paramètres de money management
   //---------------------------------------------
   MONEY.Config();
   MONEY.SetMaxRiskAuth(K_Max_Risk_Auth);   
   if (PARAM.GetRiskLevel(l_DoubleValue))       MONEY.SetRisk(l_DoubleValue);
   if (PARAM.GetMaxDayLoss(l_DoubleValue))      MONEY.SetDailyMaxLoss(l_DoubleValue);
   if (PARAM.GetMaxWeekLoss(l_DoubleValue))     MONEY.SetWeeklyMaxLoss(l_DoubleValue);
   if (PARAM.GetTrailingStop(l_DoubleValue))    MONEY.SetTrailingStop(l_DoubleValue);

   // Renseigne les paramètres de contexte
   //-------------------------------------
   CONTEXT.SetRun(PARAM.RobotIsRun());
   CONTEXT.SetSimulation(PARAM.RobotInSimulation());

   // Renseigne les paramètres d'affichage
   //-------------------------------------
   if (PARAM.GetVisuHeight(l_IntValue))      VISU.SetHeight(l_IntValue);
}
/*
RegularTreatments
Que ce soit en cycle ou à chaque événement sur le marché
INPUT:
None
OUTPUT:
TRUE si le traitement n'a pas d'erreur bloquante
*/
bool RegularTreatments(void)
{
   // Gère la lecture des paramètres
   //-------------------------------
   if (PARAM.CyclicFileAnalysis())
   {
      // Extraction des paramètres
      //--------------------------
      ParametersExtraction();
   }

   // Met à jour les états de contexte
   //---------------------------------
   CONTEXT.Cyclic();

   // Met à jour les données monétaires
   //----------------------------------
   MONEY.Cyclic();

   // Fait une surveillance cyclique
   //-------------------------------
   MONITORING.Cyclic();

   // Gère la fin des positions ouvertes
   //-----------------------------------
   STRAT.DeleteDetection();

   // Retourne l'information des paramètres lus au moins une fois
   // Situation bloquante avec le robot ' à poil' !
   //------------------------------------------------------------
   return(PARAM.ParametersRead());
   
}