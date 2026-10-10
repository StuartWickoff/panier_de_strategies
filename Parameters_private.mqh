//+-----------------------------------------------
//+---------------------------------------
//| Ensemble des fonctions privées de l'objet 'CParameters'
//|                                                      
//|   (Le code est compatible MT4/MT5)
//|
//+------------------------------------------------
//+-------------------------------------------------

/*
RazParam
 Efface les données 
INPUT :
 None
 OUTPUT :
  None  
*/
void CParameters::RazParam(void)
{
   ArrayFree(m_News);
   ArrayFree(m_PositionClosure);
   ArrayFree(m_OffDay);
   m_TradingStartDay.valid = false;
   m_TradingEndDay.valid   = false;
   m_EndPositionDay.valid  = false;
   m_Risk.valid            = false;
   m_MaxDayLoss.valid      = false;
   m_MaxWeekLoss.valid     = false;
   m_TrailingStop.valid    = false;
   m_Simulation            = false;
   m_RobotRunning          = true;
   m_LogData.valid         = false;
   m_AlertData.valid       = false;
   m_VisuData.valid        = false;
}  

//+--------------------------------------------------------------------+
//| ExtractData                                                        |
//| Lecture du fichier de paramètres et extraction des données         |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CParameters::ExtractData(void)
{
   // Variables locales
   //------------------
   int      l_Handle;
   string   l_Line;
   ushort   l_Sep;            // Code ASCII du séparateur
   int      l_FieldNb;
   string   l_FieldsName;
   string   l_Fields[];        // Tableau des champs
   
   // Ouvre le fichier de données
   //----------------------------
   ResetLastError();
   l_Handle = FileOpen(m_Filename,                                      // Nom du fichier
                       FILE_COMMON|FILE_READ|FILE_TXT|FILE_ANSI);       // Attributs d'ouverture
                       
   // En cas d'erreur d'ouverture du fichier
   //---------------------------------------
   if (l_Handle == INVALID_HANDLE)
   {   
      LOG.ERROR("Ouverture du fichier des paramètres '" + m_Filename + "' impossible", __FUNCTION__);
      return;
   }
   
   // Prépare la lecture des données
   //-------------------------------
   this.RazParam();
   l_Sep = StringGetCharacter(";" , 0);
   
   // Lecture de toutes les lignes du fichier de paramètres
   //------------------------------------------------------
   while (!FileIsEnding(l_Handle))
   {   
      l_Line      = FileReadString(l_Handle);
      l_FieldNb   = StringSplit(l_Line, l_Sep, l_Fields);

      // Extraction d'un paramètre
      //--------------------------
      if (l_FieldNb > 0)
      {
         l_FieldsName = l_Fields[0];
         CleanString(l_FieldsName);
         StringToUpper(l_FieldsName);
         if      (l_FieldsName == K_CParameters_News)         { this.ReadNews        (l_Fields); }
         else if (l_FieldsName == K_CParameters_DayStart)     { this.ReadDayStart    (l_Fields); }
         else if (l_FieldsName == K_CParameters_DayEnd)       { this.ReadDayEnd      (l_Fields); }
         else if (l_FieldsName == K_CParameters_DayCut)       { this.ReadDayCut      (l_Fields); }
         else if (l_FieldsName == K_CParameters_AllCut)       { this.ReadAllCut      (l_Fields); }
         else if (l_FieldsName == K_CParameters_Off)          { this.ReadOff         (l_Fields); }
         else if (l_FieldsName == K_CParameters_Risk)         { this.ReadRisk        (l_Fields); }
         else if (l_FieldsName == K_CParameters_DayMaxLoss)   { this.ReadDayMaxLoss  (l_Fields); }
         else if (l_FieldsName == K_CParameters_WeekMaxLoss)  { this.ReadWeekMaxLoss (l_Fields); }
         else if (l_FieldsName == K_CParameters_Trailing)     { this.ReadTrailing    (l_Fields); }
         else if (l_FieldsName == K_CParameters_Simu)         { this.ReadSimuState   (l_Fields); }
         else if (l_FieldsName == K_CParameters_Stop)         { this.RobotStopped(); }
         else if (l_FieldsName == K_CParameters_Go)           { this.RobotAlive(); }
         else if (l_FieldsName == K_CParameters_Log)          { this.ReadLog         (l_Fields); }
         else if (l_FieldsName == K_CParameters_Alert)        { this.ReadAlert       (l_Fields); }
         else if (l_FieldsName == K_CParameters_Visu)         { this.ReadVisu        (l_Fields); }
         
         // Champ inconnu
         //--------------
         else
         {
            LOG.WARNING("Paramètre '" + l_FieldsName + "' inconnu", __FUNCTION__);
         }
      }
   }
   
   // Clôture du fichier après extraction des données
   //------------------------------------------------
   FileClose(l_Handle);
}

/*
RobotAlive
Fixe l'état du robot en route (prêt à bosser !)
INPUT:
None
OUTPUT:
None
*/
void CParameters::RobotAlive(void)
{
   m_RobotRunning = true;
   LOG.INFO("Robot en activité", __FUNCTION__);
}

/*
RobotStopped
Fixe l'état du robot en arrêt (repos bien mérité !)
INPUT:
None
OUTPUT:
None
*/
void CParameters::RobotStopped(void)
{
   m_RobotRunning = false;
   LOG.INFO("Robot arrêté", __FUNCTION__);
}
//+--------------------------------------------------------------------+
//| ReadNews                                                           |
//| Interprétation des données pour une nouvelle NEWS                  |
//| INPUT:                                                             |
//|  Informations lues dans le fichier                                 |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CParameters::ReadNews(const string &i_Param[])
{
   // Variables locales
   //---
   datetime          l_Date;
   int               l_Value;
   ENUM_IMPACT_LEVEL l_Impact;
   int               l_Security;
   int               l_Index;
   bool              l_Find;
   bool              l_Correct;
   
   
   // Vérification du bon nombre de données 
   //---
   if (ArraySize(i_Param) < 5)
   {
      LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
      return;
   }
   
   // Extrait la date et heure de coupure des positions
   //---
   l_Correct   = this.ExtractDate     (i_Param[1], true, l_Date);
   l_Correct  &= this.ExtractHour     (i_Param[2], false, l_Date);
   l_Value     = this.ExtractInteger  (i_Param[3]);
   l_Security  = this.ExtractInteger  (i_Param[4]);
   
   // Vérification des valeurs numériques
   //---
   if ((l_Value < eI_Nothing) || (l_Value > eI_Major) || (l_Security < 0))
   {
      l_Correct = false;
   }
   
   // Si déformatage correct
   //---
   if (l_Correct)
   {
      // Converti la valeur lue en valeur d'énuméré
      //---
      l_Impact = (ENUM_IMPACT_LEVEL)l_Value;
      
      // Chercher si la date existe déjà
      //---
      l_Find = false;
      for (l_Index = 0; l_Index < ArraySize(m_News); l_Index++)
      {
         // Traitement d'une news déjà connue
         //---         
         if (l_Date == m_News[l_Index].date)
         {
            l_Find = true;
            if ((l_Impact  != m_News[l_Index].impact) || (l_Security != m_News[l_Index].security))
            {
               LOG.WARNING("News de " + TimeToString(l_Date) + " modifiée", __FUNCTION__);
               m_News[l_Index].impact   = l_Impact;
               m_News[l_Index].security = l_Security;
            }
         }
      }
      
      // Mémorise la nouvelle date
      //---
      if (l_Find == false)
      {
         ArrayResize(m_News, ArraySize(m_News) +1);
         m_News[ArraySize(m_News) - 1].date     = l_Date;
         m_News[ArraySize(m_News) - 1].impact   = l_Impact;
         m_News[ArraySize(m_News) - 1].security = l_Security;
         LOG.INFO("Nouvelle news le " + TimeToString(l_Date) + " avec impact " + ImpactToString(l_Impact) + ". Zone de sécurité de " + IntegerToString(l_Security) + " sec", __FUNCTION__);
      }
   }
   
   // Si erreur de déformatage
   //---
   else
   {
      LOG.WARNING("Erreur déformatage 'News' : '"+ i_Param[1] + "' '" + i_Param[2] +  "' '" + i_Param[3] +  "' '" + i_Param[4] + "'", __FUNCTION__);
   }   
}

//+--------------------------------------------------------------------+
//| ReadDayStart                                                       |
//| Interprétation des données pour l'heure de début de trading        |
//| INPUT:                                                             |
//|  Informations lues dans le fichier                                 |
//| OUTPUT:                                                            |
//|  None                                                              |
//+--------------------------------------------------------------------+
void CParameters::ReadDayStart(const string &i_Param[])
{
   // Variables locales
   //---
   datetime l_Value;
   
   // Vérification du bon nombre de données 
   //---
   if (ArraySize(i_Param) < 2)
   {
      LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
      return;
   }
   
   // Extrait l'heure du début de trading
   //---
   if (this.ExtractHour(i_Param[1], true, l_Value))
   {
      m_TradingStartDay.value = l_Value;
      m_TradingStartDay.valid = true;
      LOG.INFO("Nouvelle heure début de trading : " + TimeToString(l_Value, TIME_MINUTES), __FUNCTION__);
   }
   
   // Si erreur de déformatage
   //---
   else
   {
      LOG.WARNING("Erreur déformatage 'Début trading' : '" + i_Param[1] + "'", __FUNCTION__);
   }
}

/*
ReadDayEnd
 Interprétation des données pour l'heure de fin de trading
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadDayEnd(const string &i_Param[])
{
   // Variables locales
   //-------------------
   datetime l_Value;
   
   // Vérification du bon nombre de données 
   //--------------------------------------
   if (ArraySize(i_Param) < 2)
   {
      LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
      return;
   }
   
   // Extrait l'heure du fin de trading
   //---
   if (this.ExtractHour(i_Param[1], true, l_Value))
   {
      m_TradingEndDay.value = l_Value;
      m_TradingEndDay.valid = true;
      LOG.INFO("Nouvelle heure fin de trading : " + TimeToString(l_Value, TIME_MINUTES), __FUNCTION__);
   }
   
   // Si erreur de déformatage
   //---
   else
   {
      LOG.WARNING("Erreur déformatage 'Fin trading' : '" + i_Param[1] + "'", __FUNCTION__);
   }
}


/*
ReadOff
 Interprétation des données pour définir une journée vide
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadOff(const string &i_Param[])
{
   // Variables locales
   //---
   datetime l_Date;
   int      l_Index;
   bool     l_Find;
   
   // Vérification du bon nombre de données 
   //---
   if (ArraySize(i_Param) < 2)
   {
      LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
      return;
   }
   
   // Extrait la date d'une journée sans trading
   //---
   if (this.ExtractDate(i_Param[1], true, l_Date))
   {
      // Chercher si la date existe déjà
      //---
      l_Find = false;
      for (l_Index = 0; l_Index < ArraySize(m_OffDay); l_Index++)
      {
         if (l_Date == m_OffDay[l_Index])
         {
            LOG.WARNING("Date 'Journée OFF' en double : " + TimeToString(l_Date, TIME_DATE), __FUNCTION__);
            l_Find = true;
         }
      }
      
      // Mémorise la nouvelle date
      //---
      if (l_Find == false)
      {
         ArrayResize(m_OffDay, ArraySize(m_OffDay) + 1); 
         m_OffDay[ArraySize(m_OffDay) - 1] = l_Date;
         LOG.INFO("Nouvelle 'Journée OFF' : " + TimeToString(l_Date, TIME_DATE), __FUNCTION__);
      }
   }
   
   // Si erreur de déformatage
   //---
   else
   {
      LOG.WARNING("Erreur déformatage 'Journée OFF' : '" + i_Param[1] + "'", __FUNCTION__);
   }
}

/*
ReadDayCut
 Interprétation des données pour l'heure de coupure des positions
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadDayCut(const string &i_Param[])
{
   // Variables locales
   //------------------
   datetime l_Value;
   
   // Vérification du bon nombre de données 
   //---
   if (ArraySize(i_Param) < 2)
   {
      LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
      return;
   }
   
   // Extrait l'heure de coupure des positions
   //---
   if (this.ExtractHour(i_Param[1], true, l_Value))
   {
      m_EndPositionDay.value = l_Value;
      m_EndPositionDay.valid = true;
      LOG.INFO("Nouvelle heure coupure des positions : " + TimeToString(l_Value, TIME_MINUTES), __FUNCTION__);
   }
         
   // Si erreur de déformatage
   //---
   else
   {
      LOG.WARNING("Erreur déformatage 'Coupure jour' : '" + i_Param[1] + "'", __FUNCTION__);
   }
}

/*
ReadAllCut
 Interprétation des données pour couper les positions
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadAllCut(const string &i_Param[])
{
   // Variables locales
   //------------------
   datetime l_Date;
   int      l_Index;
   bool     l_Find;
   bool     l_Correct;
   
   // Vérification du bon nombre de données 
   //---
   if (ArraySize(i_Param) < 3)
   {
      LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
      return;
   }
   
   // Extrait la date et heure de coupure des positions
   //---
   l_Correct  = this.ExtractDate(i_Param[1], true, l_Date);
   l_Correct &= this.ExtractHour(i_Param[2], false, l_Date);
   
   // Si déformatage correct
   //---
   if (l_Correct)
   {
      // Chercher si la date existe déjà
      //---
      l_Find = false;
      for (l_Index = 0; l_Index < ArraySize(m_PositionClosure); l_Index++)
      {
         if (l_Date == m_PositionClosure[l_Index])
         {
            LOG.WARNING("Date 'Coupure complète' en double : " + TimeToString(l_Date), __FUNCTION__);
            l_Find = true;
         }
      }
      
      // Mémorise la nouvelle date
      //---
      if (l_Find == false)
      {
         ArrayResize(m_PositionClosure, ArraySize(m_PositionClosure) + 1); 
         m_PositionClosure[ArraySize(m_PositionClosure) - 1] = l_Date;
         LOG.INFO("Nouvelle date de coupure complète : " + TimeToString(l_Date), __FUNCTION__);
      }
   }
   
   // Si erreur de déformatage
   //---
   else
   {
      LOG.WARNING("Erreur déformatage 'Coupure complète' : '" + i_Param[1] + "' '" + i_Param[2] + "'", __FUNCTION__);
   }

}

/*
ReadRisk
 Interprétation des données pour couper les positions
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadRisk(const string &i_Param[])
{
      // Variable locale
      //---
      double      l_Value;
      
      // Vérification du bon nombre de données
      //---
      if (ArraySize(i_Param) < 2)
      {
         LOG.WARNING("Ligne de paramètre incomplète" , __FUNCTION__);
         return;
      }
      
      // Extrait la valeur du risque
      //---
      l_Value = this.ExtractDouble(i_Param[1]);
      
      // Contrôle la valeur reçue
      //---
      if (l_Value > 0.0)
      {
         m_Risk.value = l_Value;
         m_Risk.valid = true;
         LOG.INFO("Nouveau niveau de risque : " + DoubleToString(l_Value, 4) + "%", __FUNCTION__);
      }
      
      // Si erreur de valeur
      //---
      else
      {
         LOG.WARNING("Erreur de taille de risque : '" + i_Param[1] + "'", __FUNCTION__);
      }
}

/*
ReadDayMaxLoss
 Interprétation des données pour le niveau de perte max jour
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadDayMaxLoss(const string &i_Param[])
{
      // Variable locale
      //---
      double      l_Value;
      
      // Vérification du bon nombre de données
      //---
      if (ArraySize(i_Param) < 2)
      {
         LOG.WARNING("Ligne de paramètre incomplète" , __FUNCTION__);
         return;
      }
      
      // Extrait la valeur des pertes max journalières
      //---
      l_Value = this.ExtractDouble(i_Param[1]);
      
      // Contrôle la valeur reçue
      //---
      if (l_Value > 0.0)
      {
         m_MaxDayLoss.value = l_Value;
         m_MaxDayLoss.valid = true;
         LOG.INFO("Nouveau niveau de perte max journalière : " + DoubleToString(l_Value, 4) + "%", __FUNCTION__);
      }
      
      // Si erreur de valeur
      //---
      else
      {
         LOG.WARNING("Erreur de niveau de perte max journalière : '" + i_Param[1] + "'", __FUNCTION__);
      }
}

/*
ReadWeekMaxLoss
 Interprétation des données pour le niveau de perte max semaine
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadWeekMaxLoss(const string &i_Param[])
{
      // Variable locale
      //---
      double      l_Value;
      
      // Vérification du bon nombre de données
      //---
      if (ArraySize(i_Param) < 2)
      {
         LOG.WARNING("Ligne de paramètre incomplète" , __FUNCTION__);
         return;
      }
      
      // Extrait la valeur des pertes max hebdomadaire
      //---
      l_Value = this.ExtractDouble(i_Param[1]);
      
      // Contrôle la valeur reçue
      //---
      if (l_Value > 0.0)
      {
         m_MaxWeekLoss.value = l_Value;
         m_MaxWeekLoss.valid = true;
         LOG.INFO("Nouveau niveau de perte max hebdomadaire : " + DoubleToString(l_Value, 4) + "%", __FUNCTION__);
      }
      
      // Si erreur de valeur
      //---
      else
      {
         LOG.WARNING("Erreur de niveau de perte max hebdomadaire : '" + i_Param[1] + "'", __FUNCTION__);
      }

}

/*
ReadTrailing
 Interprétation des données pour le niveau de trailing stop
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadTrailing(const string &i_Param[])
{
      // Variable locale
      //---
      double      l_Value;
      
      // Vérification du bon nombre de données
      //---
      if (ArraySize(i_Param) < 2)
      {
         LOG.WARNING("Ligne de paramètre incomplète" , __FUNCTION__);
         return;
      }
      
      // Extrait la valeur du trailing stop souhaité
      //---
      l_Value = this.ExtractDouble(i_Param[1]);
      
      // Contrôle la valeur reçue
      //---
      if (l_Value > 0.0)
      {
         m_TrailingStop.value = l_Value;
         m_TrailingStop.valid = true;
         LOG.INFO("Nouvelle taille du trailing stop : " + DoubleToString(l_Value, 4) + "%", __FUNCTION__);
      }
      
      // Si erreur de valeur
      //---
      else
      {
         LOG.WARNING("Erreur de taille du trailing stop : '" + i_Param[1] + "'", __FUNCTION__);
      }

}

/*
ReadLog
 Interprétation des données pour le niveau des logs
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadLog(const string &i_Param[])
{
      // Variable locale
      //---
      int      l_Value;
      
      // Vérification du bon nombre de données
      //---
      if (ArraySize(i_Param) < 2)
      {
         LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
         return;
      }
      
      // Extrait le valeur du niveau de logs
      //---
      l_Value = this.ExtractInteger(i_Param[1]);
      if (LOG.IsValidLevel(l_Value))
      {
         m_LogData.level   = l_Value;
         m_LogData.valid   = true;
         LOG.INFO("Nouveau niveau de log : " + LOG.LevelToString(l_Value), __FUNCTION__);
         LOG.SetLevel(l_Value);
      }
      
      // Si erreur de niveau
      //---
      else
      {
         LOG.WARNING("Niveau de log inconnu : '" + IntegerToString(l_Value) + "'", __FUNCTION__);
      }
}

/*
ReadAlert
 Interprétation des données pour le choix des modes d'alerte
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadAlert(const string &i_Param[])
{
   // Variable locale
   //----------------
   int   l_TextValue;
   int   l_SoundValue;
   int   l_NotifValue;
   
   // Vérification du bon nombre de données
   //--------------------------------------
   if (ArraySize(i_Param) < 3)
   {
      LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
      return;
   }
   
      // Extrait les états de chaque alerte
      //-----------------------------------
      l_TextValue         = this.ExtractInteger(i_Param[1]);
      l_SoundValue        = this.ExtractInteger(i_Param[2]);
      l_NotifValue        = this.ExtractInteger(i_Param[3]);
      
      m_AlertData.text    = (l_TextValue  != 0);
      m_AlertData.sound   = (l_SoundValue != 0);
      m_AlertData.notif   = (l_NotifValue != 0);
      m_AlertData.valid   = true;
      LOG.INFO("Alertes texte : " + BoolToString(m_AlertData.text)   +
               " , son : "        + BoolToString(m_AlertData.sound)  +
               " , notif : "      + BoolToString(m_AlertData.notif)  ,
               __FUNCTION__);
      ALERT.AlertType(m_AlertData.text, m_AlertData.sound, m_AlertData.notif);               
}

//+----------------------------------------------------------------+
//| ReadVisu                                                       |
//| Interprétation des données pour les attributs d'affichage      |
//|  INPUT :                                                       |
//| Informations lues dans le fichier                              |
//|  OUTPUT :                                                      |
//| None                                                           |
//+----------------------------------------------------------------+
void CParameters::ReadVisu(const string &i_Param[])
{
      // Variable locale
      //----------------
      int      l_ValueHeight;
      
      // Vérification du bon nombre de données
      //--------------------------------------
      if (ArraySize(i_Param) < 2)
      {
         LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
         return;
      }
      
      // Extrait les états de chaque alerte
      //-----------------------------------
      l_ValueHeight      = this.ExtractInteger(i_Param[1]);
      
      m_VisuData.height  = l_ValueHeight;
      m_VisuData.valid   = VISU.HeightIsValid(m_VisuData.height);
      if (m_VisuData.valid)
      {
         LOG.INFO("Affiche avec la taille : " + IntegerToString(l_ValueHeight), __FUNCTION__);
      }
      
      // Si erreur de taille d'affichage
      //--------------------------------
      else
      {
         LOG.WARNING("Taille d'affichage incorrecte : '" + IntegerToString(l_ValueHeight) + "'", __FUNCTION__);
      }
}

/*
ReadSimuState
 Interprétation des données pour les attributs d'affichage
  INPUT :
   Informations lues dans le fichier
  OUTPUT :
   None
*/
void CParameters::ReadSimuState(const string &i_Param[])
{
      // Variable locale
      //----------------
      int      l_SimuState;
      
      // Vérification du bon nombre de données
      //--------------------------------------
      if (ArraySize(i_Param) < 2)
      {
         LOG.WARNING("Ligne de paramètre incomplète", __FUNCTION__);
         return;
      }
      
      // Extrait les états de chaque alerte
      //-----------------------------------
      l_SimuState   = this.ExtractInteger(i_Param[1]);
      m_Simulation  = (l_SimuState != 0);
      LOG.INFO("Simulation : " + BoolToString(m_Simulation), __FUNCTION__);
}

/*
ExtractInteger
Extraction d'une valeur numérique au format xxx
INPUT:
Chaîne de caractères
OUTPUT:
La valeur si tout s'est bien passé ou 0 dans le cas contraire
*/
int CParameters::ExtractInteger(const string i_Text)
{
   // Variable locale
   //----------------
   string l_Text;
   
   // Nettoyage de la chaîne de caractères
   //-------------------------------------
   l_Text = i_Text;
   CleanString(l_Text);
   
   // Conversion en valeur entière
   //-----------------------------
   return((int)StringToInteger(l_Text));
}

/*
ExtractDouble
Extraction d'une valeur numérique au format xxx.xx
INPUT:
Chaîne de caractères
OUTPUT:
La valeur si tout s'est bien passé ou 0.0 dans le cas contraire
*/
double CParameters::ExtractDouble(const string i_Text)
{
   // Variable locale
   //----------------
   string l_Text;
   
   // Nettoyage de la chaîne de caractères
   //-------------------------------------
   l_Text = i_Text;
   CleanString(l_Text);
   
   // Conversion en valeur entière
   //-----------------------------
   return((double)StringToDouble(l_Text));
}

/*
ExtractHour
Extraction d'une heure au format hh:mm
INPUT:
Chaîne de caractères
OUTPUT:
TRUE si le déformatage s'est bien passé
l'heure si tout s'est bien passé
*/
bool CParameters::ExtractHour(const string i_Text, const bool i_clear, datetime &i_hour)
{
   // Variables locales
   //------------------
   ushort         l_Sep;            // Code ASCII du séparateur
   string         l_Brute;
   MqlDateTime    l_Time;
   MqlDateTime    l_TimeParam;
   string         l_Fields[];       // Tableau des champs
   int            l_FieldNb;
   
   // Initialise toutes les informations
   //-----------------------------------
   l_Sep    = StringGetCharacter(":", 0);
   l_Brute  = i_Text;
   CleanString(l_Brute);
   
   // Initialise les données de la date
   //----------------------------------
   if (i_clear)
   {
      l_Time.year        = 1970;
      l_Time.mon         = 1;
      l_Time.day         = 1;
      l_Time.sec         = 0;
      l_Time.day_of_week = 0;
      l_Time.day_of_year = 0;
   }
   
   // Récupère les infos dans le paramètre
   //-------------------------------------
   else
   {
      if (!TimeToStruct(i_hour, l_TimeParam))
      {
         return(false);
      }
      l_Time.year        = l_TimeParam.year;
      l_Time.mon         = l_TimeParam.mon;
      l_Time.day         = l_TimeParam.day;
      l_Time.sec         = 0;
      l_Time.day_of_week = l_TimeParam.day_of_week;
      l_Time.day_of_year = l_TimeParam.day_of_year;      
   }
   
   // Sépare les heures des minutes
   //------------------------------
   l_FieldNb = StringSplit(l_Brute, l_Sep, l_Fields);
   
   // Erreur si le nombre de champs est incorrect
   //--------------------------------------------
   if (l_FieldNb != 2) return(false);
   
   // Extrait l'heure et les minutes
   //-------------------------------
   l_Time.hour = (int)StringToInteger(l_Fields[0]);
   l_Time.min  = (int)StringToInteger(l_Fields[1]);
   
   // Teste la validité des valeurs
   //------------------------------
   if ((l_Time.hour < 0 ) || (l_Time.hour > 23)) return(false);
   if ((l_Time.min  < 0 ) || (l_Time.min  > 59)) return(false);
   
   // Enregistre l'heure
   //-------------------
   i_hour = StructToTime(l_Time);
   return(true);
   
}

/*
ExtractDate
Extraction d'une date au format jj//mm/aaaa
INPUT:
Chaîne de caractères
OUTPUT:
TRUE si le déformatage s'est bien passé
la date si tout s'est bien passé
*/

bool CParameters::ExtractDate(const string i_Text, const bool i_clear, datetime &i_date)
{
   // Variables locales
   //------------------
   ushort         l_Sep;            // Code ASCII du séparateur
   string         l_Brute;
   MqlDateTime    l_Time;
   MqlDateTime    l_TimeParam;
   string         l_Fields[];       // Tableau des champs
   int            l_FieldNb;   
   
   // Initialise toutes les informations
   //-----------------------------------
   l_Sep    = StringGetCharacter("/", 0);
   l_Brute  = i_Text;
   CleanString(l_Brute);
   
   // Initialise les données de la date
   //----------------------------------
   if (i_clear)
   {
      l_Time.hour        = 0;
      l_Time.min         = 0;
      l_Time.sec         = 0;
      l_Time.day_of_week = 0;
      l_Time.day_of_year = 0;
   }
   
   // Récupère les infos dans le paramètre
   //-------------------------------------
   else
   {
      if (!TimeToStruct(i_date, l_TimeParam))
      {
         return(false);
      }
      l_Time.hour        = l_TimeParam.hour;
      l_Time.min         = l_TimeParam.min;
      l_Time.sec         = l_TimeParam.sec;
      l_Time.day_of_week = 0;
      l_Time.day_of_year = 0;
   }
   
   // Sépare les champs
   //------------------
   l_FieldNb = StringSplit(l_Brute, l_Sep, l_Fields);
   
   // Erreur si le nombre de champs est incorrect
   //--------------------------------------------
   if (l_FieldNb != 3) return(false);
   
   // Extrait l'heure et les minutes
   //-------------------------------
   l_Time.day    = (int)StringToInteger(l_Fields[0]);
   l_Time.mon    = (int)StringToInteger(l_Fields[1]);
   l_Time.year   = (int)StringToInteger(l_Fields[2]);
   
   // Converti la date
   //-----------------
   i_date = StructToTime(l_Time);
   return(true);
   
   // Test la validité des valeurs
   // (Année bissextile calculée simplement)
   //---------------------------------------
   if ((l_Time.year < 1970) || (l_Time.year > 3000)) return(false);
   if ((l_Time.mon  < 1)    || (l_Time.mon  > 12))   return(false);
   if (l_Time.day < 1) return(false);
   if (((l_Time.mon == 1) || (l_Time.mon == 3) || (l_Time.mon == 5) || (l_Time.mon == 7) || (l_Time.mon == 8) || (l_Time.mon == 10) || (l_Time.mon == 12)) && (l_Time.day > 31)) return(false);
   if (((l_Time.mon == 4) || (l_Time.mon == 6) || (l_Time.mon == 9) || (l_Time.mon == 11)) && (l_Time.day > 30)) return(false);
   if (((l_Time.year % 4) == 0) && (l_Time.mon == 2) && (l_Time.day > 29)) return(false);
   if (((l_Time.year % 4) != 0) && (l_Time.mon == 2) && (l_Time.day > 28)) return(false);
   
   // Converti la date
   //-----------------
   i_date = StructToTime(l_Time);
   return(true);
   
}