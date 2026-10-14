//+----------------------------------------------------------------------+
//|                                                                      |
//|      Collection de fonctions pour les traitements                    | 
//|                                                                      |
//+----------------------------------------------------------------------+
//|                                                                      |
//| Liste des fonctions                                                  |
//|                                                                      |
//| - ErrorToString     : Conversion d'un code d'erreur en texte clair   |
//|                                                                      |
//| - CleanString       : Nettoyage d'un texte en supprimant les espaces |
//|                      avant et après                                  |
//| - FolderNameControl : Contrôle un nom de répertoire d'après les      |
//|                       règles Windows                                 |
//| - SoundNameControl  : Contrôle l'existence et le fonctionnement'     |
//|                       d'un son                                       | 
//| - GetRepertoryFiles : Extrait le chemin complet du répertoire        |
//|                       MetaTrader                                     | 
//| - BoolToString      : Converti un booléen en texte clair             |
//|                                                                      |
//| - ImpactToString    : Converti un impact en texte clair              |
//|                                                                      |
//+----------------------------------------------------------------------+
//|
//|   Dépendances :
//|
//|   - Fichier Type.mqh : Contient la constante pour le répertoire
//|
//|




//+-------------------------------------------------------------------+
//| ErrorToString                                                     |
//| Retourne la description d'une erreur MetaTrader                   |
//| INPUT:                                                            |
//|  Nom de la fonction qui contient l'erreur                         |
//|  Code MetaTrader de l'erreur                                      |
//| OUTPUT:                                                           |
//|  Texte avec la description de l'erreur                            |
//+-------------------------------------------------------------------+
string ErrorToString(const int error)
{
#ifdef __MQL4__
   switch(error)
   {
      case ERR_NOTIFICATION_ERROR               : return("ERR_NOTIFICATION_ERROR");
      case ERR_NOTIFICATION_TOO_FREQUENT        : return("ERR_NOTIFICATION_TOO_FREQUENT");
      case ERR_NOTIFICATION_PARAMETER           : return("ERR_NOTIFICATION_PARAMETER");
      case ERR_NOTIFICATION_SETTINGS            : return("ERR_NOTIFICATION_SETTINGS");
      default                                   : return("Erreur non référencée :( !!!");
   }
#endif 

#ifdef __MQL5__
   switch(error)
   {
      case ERR_NOTIFICATION_SEND_FAILED         : return("ERR_NOTIFICATION_SEND_FAILED");
      case ERR_NOTIFICATION_TOO_FREQUENT        : return("ERR_NOTIFICATION_TOO_FREQUENT");
      case ERR_NOTIFICATION_WRONG_PARAMETER     : return("ERR_NOTIFICATION_WRONG_PARAMETER");
      case ERR_NOTIFICATION_WRONG_SETTINGS      : return("ERR_NOTIFICATION_WRONG_SETTINGS");
      default                                   : return("Erreur non référencée :( !!!");
   }
#endif 

}

//+--------------------------------------------------------------------+
//| CleanString                                                        |
//| Supprime les espaces au début et à la fin d'une string             |
//| INPUT:                                                             |
//|  Chaîne de caractères                                              |
//| OUTPUT:                                                            |
//|  Chaîne de caractères nettoyée                                     |
//+--------------------------------------------------------------------+

void CleanString(string& i_string)
{
#ifdef __MQL4__
   i_string = StringTrimLeft(i_string);
   i_string = StringTrimRight(i_string);
#endif 

#ifdef __MQL5__
   StringTrimRight (i_string);
   StringTrimLeft  (i_string);
#endif    
}


//+--------------------------------------------------------------------+
//| FolderNameControl                                                  |
//| Vérification de la validité d'un nom de répertoire                 |
//| INPUT:                                                             |
//|  Nom du répertoire                                                 |
//|  Tag pour imposer le '\' en fin de nom                             |
//| OUTPUT:                                                            |
//|  TRUE si le nom du répertoire est correct                          |
//+--------------------------------------------------------------------+
bool FolderNameControl(const string i_folder, const bool i_backslashVerif = false)
{
   // Variables locales
   //------------------
   string   l_folder;
   ushort   l_charactere;
   int      l_loop;

   // Nettoie le nom du répertoire
   //-----------------------------
   l_folder = i_folder;
   CleanString(l_folder);

   // Vérification d'un nom vide
   //---------------------------
   if (l_folder == "")
   {
      return(false);
   }

   // Vérification des caractères interdits
   //--------------------------------------
   for (l_loop = 0; l_loop < StringLen(l_folder); l_loop++)
   {
      l_charactere = StringGetCharacter(l_folder, l_loop);
      if (l_charactere < ' ') return(false);
      if (l_charactere ==  '/' ) return(false);
      if (l_charactere ==  ':' ) return(false);
      if (l_charactere ==  '*' ) return(false);
      if (l_charactere ==  '?' ) return(false);
      if (l_charactere ==  '<' ) return(false);
      if (l_charactere ==  '>' ) return(false);
      if (l_charactere ==  '|' ) return(false);
      if (l_charactere == '"' ) return(false);
   }
   
   // Vérification du backslash en fin de nom
   //----------------------------------------
   if (i_backslashVerif)
   {
      if (StringSubstr(l_folder, StringLen(l_folder) - 1 , 1) != "\\")
      {
         return(false);
      }      
   }
   
   // Aucune erreur dans le nom
   //--------------------------
   return(true);   
}

//+--------------------------------------------------------------------+
//| FileNameControl                                                    |
//| Vérification de la validité d'un nom de fichier                    |
//| INPUT:                                                             |
//|  Nom du fichier                                                    |
//| OUTPUT:                                                            |
//|  TRUE si le nom du fichier est correct                             |
//+--------------------------------------------------------------------+
bool FileNameControl(const string i_folder)
{
   return(FolderNameControl(i_folder));
}


/*
SoundNameControl
Vérification de la validité d'un nom de fichier son
INPUT:
Nom d'un fichier son
Nom de la fonction d'origine
OUTPUT:
Nom du fichier son après test
*/
void SoundNameControl(string& i_sound, const string i_function = "")
{
   // Ne teste pas si on est en backtest
   //-----------------------------------
   if (MQLInfoInteger(MQL_TESTER))
   {
      LOG.INFO("Mode test, Pas de son", __FUNCTION__);
      return;
   }
   // Test si le fichier son est accessible
   //--------------------------------------
   if (PlaySound(i_sound) == false)
   {
      LOG.WARNING("Fichier son '" + i_sound + "' impossible à jouer. Utilisation d'un fichier son par défaut.", i_function);
      i_sound = "alert2.wav";
      
      // Tentative de jouer le fichier par défaut
      //-----------------------------------------
      if (PlaySound(i_sound) == false)
      {
         LOG.WARNING("Fichier son par défaut '" + i_sound + "' impossible à jouer. Aucun son !!!", i_function);
         i_sound = "";
      }
   }
   
   // Coupe le son de l'initialisation
   //---------------------------------
   PlaySound(NULL);
}

/*
BoolToString
Converti un booléen en texte clair
INPUT:
Valeur booléenne
OUTPUT:
Nom de la valeur
*/
string BoolToString(bool value)
{
   if (value)
   {
      return("Vrai");
   }
   else
   {
      return("Faux");
   }
}

/*
ImpactToString
Converti un impact de news en texte clair
INPUT:
Valeur d'un impact de news
OUTPUT:
Nom de l'impact
*/
string ImpactToString(ENUM_IMPACT_LEVEL value)
{
   // Converti la valeur de la période en nom
   //--------------------
   switch (value)
   {
      case eI_Nothing : return("Aucun");
      case eI_Minor   : return("Mineur");
      case eI_Medium  : return("Moyen");
      case eI_Major   : return("Majeur");
      default         : return("???");
   }
}

//+--------------------------------------------------------------------+
//| TrendToString                                                      |
//| Converti un trend en texte clair                                   |
//| INPUT:                                                             |
//|  Trend (enumarate value)                                           |
//| OUTPUT:                                                            |
//|  Nom du trend                                                      |
//+--------------------------------------------------------------------+
string TrendToString(ENUM_TREND trend)
{
   switch(trend)
   {
      case eT_Bull : return("Bull");
      case eT_Bear : return("Bear");
      default      : return("???");
   }
}

//+--------------------------------------------------------------------+
//| PeriodToString                                                     |
//| Converti une periode en texte clair                                |
//| INPUT:                                                             |
//|  Periode                                                           |
//| OUTPUT:                                                            |
//|  Nom de la periode                                                 |
//+--------------------------------------------------------------------+
string PeriodToString(const ENUM_TIMEFRAMES TF)
{
   // Variables locales
   //------------------
   ENUM_TIMEFRAMES    l_TF;

   // Converti la période courante
   //-----------------------------
   l_TF = (TF == PERIOD_CURRENT) ? ENUM_TIMEFRAMES(Period()) : TF;

   // Converti le valeur de la période en nom
   //----------------------------------------
   switch (l_TF)
   {
      case PERIOD_M1  : return("M1");
      case PERIOD_M2  : return("M2");
      case PERIOD_M3  : return("M3");
      case PERIOD_M4  : return("M4");
      case PERIOD_M5  : return("M5");
      case PERIOD_M6  : return("M6");
      case PERIOD_M10 : return("M10");
      case PERIOD_M12 : return("M12");
      case PERIOD_M15 : return("M15");
      case PERIOD_M20 : return("M20");
      case PERIOD_M30 : return("M30");
      case PERIOD_H1  : return("H1");
      case PERIOD_H2  : return("H2");
      case PERIOD_H3  : return("H3");
      case PERIOD_H4  : return("H4");
      case PERIOD_H6  : return("H6");
      case PERIOD_H8  : return("H8");
      case PERIOD_H12 : return("H12");
      case PERIOD_D1  : return("D1");
      case PERIOD_W1  : return("W1");
      case PERIOD_MN1 : return("MN1");
      default         : return("???");
   }
}   
