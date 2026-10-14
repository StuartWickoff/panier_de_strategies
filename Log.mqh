//+---------------------------------------------------------------+
//| Gère les logs pour une appli                                  |
//|                                                               |
//| - Création d'un fichier de log pour une journée               |
//| - Gestion de l'écriture dans le fichier de log                |
//|                                                               |
//+---------------------------------------------------------------+
//| Format des LOGS :                                             |
//|   <type> <sép.> <heure> <sép.> <fonction> <sép.> <texte>      |
//|                                                               |
//+---------------------------------------------------------------+
//|                                                               |
//| L'application doit définir :                                  |
//| - Le niveau de détail des logs                                |
//| - Le nom du répertoire                                        |
//|                                                               |
//| Pour enregistrer des logs, voici les fonctions :              |
//| - ERROR  : Erreur dans un traitement                          |
//| - WARNING : Alerte ou avertissement                           |
//| - INFO    : Simplement une information d'une opération        |
//| - DEBUG   : Tout message pour le debogage                     |
//|                                                               |
//| - ERROR_CODE   : Erreur avec un code d'erreur MetaTrader      |
//| - WARNING_CODE : Alerte avec un code d'erreur MetaTrader      |
//|                                                               |
//+---------------------------------------------------------------+
//|
//| TODO avec Grok : Liste des fonctions et leur rôle
//|
//+-----------------------------------------------------------------
//| Dépendances :
//| - Fichier BB_ADX_expert.mqx  : Contient la source compilable
//| - Fichier Tools.mqh          : Contient les fonctions de mise en forme
//| - Fichier Type.mqh           : Contient l'énuméré des niveaux |
//|                                                         |
//|
//|
//|
//|
//+---------------------------------------------------------------+

//////////////////////////////////////////////////////////
//                                                      //
//                C O N S T A N T S                     //
//                                                      //
//////////////////////////////////////////////////////////

#define K_CLog_Tag_Error         "ERR"
#define K_CLog_Tag_Warning       "WRN"
#define K_CLog_Tag_Info          "INF"
#define K_CLog_Tag_Debug         "DBG"
#define K_CLog_Separator        "|"
#define K_CLog_Level_Nothing     0
#define K_CLog_Level_Error       1
#define K_CLog_Level_Warning     2
#define K_CLog_Level_Info        3
#define K_CLog_Level_Debug       4

//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////

class CLog
{
//================================
//---  PRIVATE
//================================
private:
   // Données
   //--------
   bool     m_Error;             // Evite les erreurs à répétition pour les accès au fichier
   int      m_Handle;            // Identification du fichier de log
   datetime m_Date;              // Date courante du fichier de log
   uchar    m_Level;             // Niveau des logs
   string   m_Folder;            // Répertoire où se trouve les fichiers de log

   // Fonctions
   //----------
   void RazData(void);
      
   void LevelNothing    (void);
   void LevelError      (void);
   void LevelWarning    (void);
   void LevelInfo       (void);
   void LevelAll        (void);
  
   void Writing(const string i_type, const string i_text, const string i_function);
   void Opening(void);
   void Closing(void);
      
   
//================================
//---  PUBLIC
//================================
public:                   
   // Fonctions
   //----------   
   bool   Config        (const string i_folder);
   
   bool   ConfigOk      (void) { return(m_Folder != ""); }
   
   string GetFolder     (void);
   
   void   End           (void) { this.Closing(); }   

   string InfosLogOperation(const string i_Strategy, const int i_detection, const string i_market);
   
   // Gestion des niveaux
   //--------------------
   bool IsValidLevel    (const int i_level);
   
   void SetLevel        (const int i_level);
   
   string LevelToString (const int i_level);
   
   // Envoi des logs
   //---------------
   void ERROR   (const string i_text, const string i_function = "");
   void WARNING (const string i_text, const string i_function = "");
   void INFO    (const string i_text, const string i_function = "");
   void DEBUG   (const string i_text, const string i_function = "");
    
   void ERROR_CODE   (const int i_error = 0, const string i_function = "");
   void WARNING_CODE (const int i_error = 0, const string i_function = "");
   
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
//|  Nom du répertoire                                             |
//| OUTPUT:                                                        |
//|  TRUE si configuration sans erreur                             |
//+----------------------------------------------------------------+
bool CLog::Config(string i_folder)
{
   // Variables locales
   //------------------
   string   l_folder;
   
   // Initialise toutes les données internes
   //---------------------------------------
   this.RazData();
   
   // Nettoie le nom du répertoire
   //-----------------------------
   l_folder = i_folder;
   CleanString(i_folder); 
   
   // Vérification du nom
   //--------------------
   if (!FolderNameControl(l_folder, true))
   {
      Print(K_CLog_Tag_Warning + K_CLog_Separator + __FUNCTION__ + K_CLog_Separator + "Nom du répertoire '" + l_folder + "' incorrect !!!");
      m_Folder = "";
      return(false);
   }
     
   // Sauvegarde le nom du répertoire
   //--------------------------------
   m_Folder = l_folder + IntegerToString(I_Robot_ID) + "\\";

   // Fin de la configuration
   //------------------------
   return(true);
   
}

//+----------------------------------------------------------------+
//| GetFolder                                                      |
//| Extrait le nom du répertoire des logs ou un message d'erreur   |
//| s'il est incorrect ou non renseigné                            |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  Le texte avec le nom du répertoire ou un message              |
//+----------------------------------------------------------------+
string CLog::GetFolder(void)
{
   if (m_Folder == "")
   {
      return("Répertoire des logs non initialisé !!!");
   }
   else
   {
      return("Répertoire des logs : " + TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + m_Folder);
   }
}

//+----------------------------------------------------------------+
//| InfosLogOperation                                              |
//| Construit la base des logs pour une opération                  |
//| INPUT:                                                         |
//|  Nom de la stratégie                                           |
//|  Numéro de la détection                                        |
//|  Nom du marché                                                 |
//| OUTPUT:                                                        |
//|  Texte pour habiller les logs                                  |
//+----------------------------------------------------------------+
string CLog::InfosLogOperation(const string i_Strategy, const int i_detection, const string i_market)
{
   // Variable locale
   //----------------
   MqlTick     l_TickData;

   // Lit les infos récentes du marché
   //---------------------------------
   if (SymbolInfoTick(i_market, l_TickData))
   {
      return(i_Strategy + "#" + IntegerToString(i_detection) + " [" + TimeToString(l_TickData.time, TIME_DATE|TIME_SECONDS) + "] " );
   }
   else
   {
      return(i_Strategy + "#" + IntegerToString(i_detection) + " [???] ");
   }

}

/*
LevelToString
Converti un niveau en texte clair
INPUT:
Valeur d'un niveau de log
OUTPUT:
Nom de niveau
*/
string CLog::LevelToString(const int i_level)
{
   // Converti la valeur du niveau en nom
   //------------------------------------
   switch (i_level)
   {
      case K_CLog_Level_Nothing     : return("Aucun log");
      case K_CLog_Level_Error       : return("Log d'erreur");
      case K_CLog_Level_Warning     : return("Log d'erreur et warning");
      case K_CLog_Level_Info        : return("Log opérationnels");
      case K_CLog_Level_Debug       : return("Tous les log");
      default                       : return("???");
   }
}

/*
IsValidLevel
Test le niveau en paramètre pour définir s'il est valide ou non
INPUT:
Niveau de logs à tester
OUTPUT:
TRUE si le niveau passé en paramètre est correct.
nota : Pas de changement de niveau des logs dans cette fonction
*/
bool CLog::IsValidLevel(const int i_level)
{
   return((i_level >= K_CLog_Level_Nothing) && (i_level <= K_CLog_Level_Debug));
}

/*
SetLevel
Initialise le niveau de log
INPUT:
Niveau de logs à initier
OUTPUT:
None*/
void CLog::SetLevel(const int i_level)
{
   // Traitement seulement si le niveau change
   //-----------------------------------------
   if (i_level != m_Level)
   {
      switch(i_level)
      {
         case K_CLog_Level_Nothing     : LevelNothing();    break;
         case K_CLog_Level_Error       : LevelError();      break;
         case K_CLog_Level_Warning     : LevelWarning();    break;
         case K_CLog_Level_Info        : LevelInfo();       break;
         case K_CLog_Level_Debug       : LevelAll();        break;
         default                       : break;
      }
   }
}
//+--------------------------------------------------------------------+
//| ERREUR                                                             |
//| Envoi un log d'erreur sous conditions dans le fichier de log       |
//| INPUT:                                                             |
//|  Texte du log                                                      |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::ERROR(const string i_text, const string i_function = "")
{
   if (m_Level >= K_CLog_Level_Error)
   {
      this.Writing(K_CLog_Tag_Error, i_text, i_function);
   }
}

//+--------------------------------------------------------------------+
//| WARNING                                                            |
//| Envoi un log d'alerte sous conditions dans le fichier de log       |
//| INPUT:                                                             |
//|  Texte du log                                                      |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::WARNING(const string i_text, const string i_function = "")
{
   if (m_Level >= K_CLog_Level_Warning)
   {
      this.Writing(K_CLog_Tag_Warning, i_text, i_function);
   }
}

//+--------------------------------------------------------------------+
//| INFO                                                               |
//| Envoi un log d'info sous conditions dans le fichier de log         |
//| INPUT:                                                             |
//|  Texte du log                                                      |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::INFO(const string i_text, const string i_function = "")
{
   if (m_Level >= K_CLog_Level_Info)
   {
      this.Writing(K_CLog_Tag_Info, i_text, i_function);
   }
}

//+--------------------------------------------------------------------+
//| DEBUG                                                              |
//| Envoi un log de debug sous conditions dans le fichier de log       |
//| INPUT:                                                             |
//|  Texte du log                                                      |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::DEBUG(const string i_text, const string i_function = "")
{
   if (m_Level >= K_CLog_Level_Debug)
   {
      this.Writing(K_CLog_Tag_Debug, i_text, i_function);
   }
}


//+-------------------------------------------------------------------+
//| ERROR_CODE                                                        |
//| Envoi une ERREUR avec le nom de la fonction et le code d'erreur   |
//| INPUT:                                                            |
//|  Nom de la fonction qui contient l'erreur                         |
//|  Code MetaTrader de l'erreur                                      |
//| OUTPUT:                                                           |
//|  None                                                             |
//+-------------------------------------------------------------------+
void CLog::ERROR_CODE(const int i_error=0,const string i_function="")
{
   this.ERROR( "Erreur " + ErrorToString(i_error), i_function);
}

//+-------------------------------------------------------------------+
//| WARNING_CODE                                                      |
//| Envoi une WARNING avec le nom de la fonction et le code d'erreur  |
//| INPUT:                                                            |
//|  Nom de la fonction qui contient l'erreur                         |
//|  Code MetaTrader de l'erreur                                      |
//| OUTPUT:                                                           |
//|  None                                                             |
//+-------------------------------------------------------------------+
void CLog::WARNING_CODE(const int i_error=0,const string i_function="")
{
   this.WARNING( "Erreur " + ErrorToString(i_error), i_function);
}


//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////
//+--------------------------------------------------------------------+
//| RazData
//|   Initialise toutes les données internes
//| INPUT:
//|   None
//| OUTPUT:
//|   None
//+--------------------------------------------------------------------+
void CLog::RazData(void)
{
   m_Error  = false;
   m_Handle = INVALID_HANDLE;
   m_Date   = 0;
   m_Level  = 0;
   m_Folder = "";
}

//+--------------------------------------------------------------------+
//| LevelNothing                                                       |
//| Création d'une limite pour n'envoyer aucun logs                    |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::LevelNothing(void)
{
   m_Level = K_CLog_Level_Nothing;
   Print("Aucun log ne sera généré");
}

//+--------------------------------------------------------------------+
//| LevelError                                                         |
//| Création d'une limite pour n'envoyer que les logs d'erreur         |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::LevelError(void)
{
   m_Level = K_CLog_Level_Error;
   Print("Uniquement les logs d'erreur seront générés");
}

//+--------------------------------------------------------------------+
//| LevelWarning                                                       |
//| Création d'une limite pour n'envoyer que les logs d'erreur et      |
//| de warning                                                         |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::LevelWarning(void)
{
   m_Level = K_CLog_Level_Warning;
   Print("Uniquement les logs d'erreur et de warning seront générés");
}

//+--------------------------------------------------------------------+
//| LevelInfo                                                          |
//| Création d'une limite pour envoyer tous les logs opérationnels     |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::LevelInfo(void)
{
   m_Level = K_CLog_Level_Info;
   Print("Uniquement les logs opérationnels seront générés");
}

//+--------------------------------------------------------------------+
//| LevelAll                                                           |
//| Aucune limite pour les logs                                        |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::LevelAll(void)
{
   m_Level = K_CLog_Level_Debug;
   Print("Tous les types de logs seront générés");
}

//+--------------------------------------------------------------------+
//| Writing                                                            |
//| Enregistre un log dans le fichier de log                           |
//| INPUT:                                                             |
//|  Type de log au format texte                                       |
//|  Texte du log                                                      |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::Writing(const string i_type, const string i_text, const string i_function)
{
   // Variables locales
   //------------------
   MqlDateTime l_StructureDateLocal;
   MqlDateTime l_StructureDate;
   string      l_text;  
   
   // Contrôle le fichier de log s'il est en cours de remplissage
   //------------------------------------------------------------
   if (m_Handle != INVALID_HANDLE)
   {
      // Extraire les infos de la date
      //------------------------------
      TimeToStruct(TimeLocal(), l_StructureDateLocal);
      TimeToStruct(m_Date     , l_StructureDate);
      
      // Vérifie si la date a changé
      //----------------------------
      if ( (l_StructureDateLocal.day != l_StructureDate.day) || (l_StructureDateLocal.mon != l_StructureDate.mon) )
      {
          // Clôture du fichier de log
          //--------------------------
          this.Closing(); 
      }      
   }
   
   
   // Ouvre un fichier de log s'il n'est pas encore ouvert
   //-----------------------------------------------------
   this.Opening();
   
   
   // Ecriture si le fichier est bien ouvert
   //---------------------------------------
   if (m_Handle > INVALID_HANDLE)
   {
      // Construit le texte à envoyer dans les logs
      //-------------------------------------------
      l_text      = i_type;
      l_text     += K_CLog_Separator + TimeToString(TimeLocal(), TIME_SECONDS);
      l_text     += K_CLog_Separator + i_function;
      l_text     += K_CLog_Separator + i_text;
      
      // Ecrit le texte
      //---------------
      FileWrite(m_Handle, l_text);
      FileFlush(m_Handle);
   }
}

//+--------------------------------------------------------------------+
//| Closing                                                            |
//| Ferme le fichier de log et efface ses références                   |
//| INPUT:                                                             |
//|  None                                                              |
//|  Texte du log                                                      |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::Closing(void)
{
   // Variables locales
   //------------------
   string   l_text;

   // Ferme le fichier de log s'il est en cours de remplissage
   //---------------------------------------------------------
   if (m_Handle != INVALID_HANDLE)
   {
      // Ecriture du bilan de la journée
      //--------------------------------
      l_text = K_CLog_Tag_Info + K_CLog_Separator + 
               "23:59:59" + K_CLog_Separator +
               "BILAN JOURNALIER" + K_CLog_Separator +
               DoubleToString(MONEY.GetDaily_Result(), 3) + "%";
      FileWrite(m_Handle, l_text);
      
      // Clôture du fichier de log
      //--------------------------
      FileClose(m_Handle);
   }
   
   // Efface les références au fichier de log
   //----------------------------------------
   m_Handle = INVALID_HANDLE;
   m_Date = 0;
}

//+--------------------------------------------------------------------+
//| Opening                                                            |
//| Ouvre un nouveau fichier de log s'il n'est pas encore ouvert       |
//| INPUT:                                                             |
//|  None                                                              |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CLog::Opening(void)
{
   // Variable locale
   //----------------   
   string l_Filename;
   
   // Test si le fichier n'est pas ouvert
   //------------------------------------
   if (m_Handle == INVALID_HANDLE)
   {
      // Ouverture du fichier
      //---------------------
      m_Date     = TimeLocal();
      l_Filename = m_Folder + TimeToString(m_Date, TIME_DATE) + Symbol() + ".log";
      ResetLastError();
      m_Handle   = FileOpen(l_Filename,                                                             // Nom du fichier 
                            FILE_COMMON|FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);   // Attributs d'ouverture
                            
      // En cas d'erreur d'ouverture de fichier
      //---------------------------------------
      if (m_Handle == INVALID_HANDLE)
      {
         if (m_Error == false)
         {
            Print("ERREUR ouverture fichier LOG : ", ErrorToString(GetLastError()));
            m_Error = true;
         }
      }
      // Si fichier ouvert, on va directement à la fin pour le compléter
      //----------------------------------------------------------------
      else
      {
         FileSeek(m_Handle,       // Handle du fichier
                  0,              // Offset de déplacement
                  SEEK_END);      // Référence de déplacement
         m_Error = false;
      }
   }
}