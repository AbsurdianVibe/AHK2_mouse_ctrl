#Requires AutoHotkey v2.0
;@Ahk2Exe-SetMainIcon mouse_ctrl.ico
;@Ahk2Exe-SetCompanyName AbsurdianVibe
;@Ahk2Exe-SetDescription Mouse Control
;@Ahk2Exe-SetCopyright Copyright (c) 2026 AbsurdianVibe
;@Ahk2Exe-SetVersion 1.1.2
;@Ahk2Exe-SetProductName Mouse Control
;@Ahk2Exe-SetLanguage 0x0409
#SingleInstance Off
A_MaxHotkeysPerInterval := 200 ; Anti-spam scrolla
ProcessSetPriority "High"

; #region --- BARIERA ROZRUCHOWA (CLI INTERCEPTOR) ---
if (A_Args.Length > 0) {
    A_IconHidden := true
    if (A_Args[1] == "WARMUP") {
        myGui := Gui("-Caption +ToolWindow")
        myDict := "💻✂🔍📄🡰🡲🡱🡳◑🔊🔉ψᛒ⊙🎧📞—✓▲▼◄►🞀❘❙❚🞂✲➠🡷🡵✍📸⚠️"
        for myOpt in ["s9 norm", "s10 norm", "s13 w100", "s15 bold", "s20 norm"] {
            myGui.SetFont(myOpt, "Segoe UI")
            myGui.Add("Text",, myDict)
        }
        myGui.Destroy()
        ExitApp()
    }
    if (A_Args[1] == "DAEMON") {
        HardwareDaemon.Boot(A_Args)
        Exit()
    }
}
; #endregion

; --- MANUAL SINGLE INSTANCE FORCE ---
DetectHiddenWindows(true)
for hw in WinGetList("MouseCtrl_Main_Window") {
    if (hw != A_ScriptHwnd)
        try WinClose(hw)
}
WinSetTitle("MouseCtrl_Main_Window", "ahk_id " A_ScriptHwnd)

DllCall("User32\ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", 0x0044, "UInt", 1, "Ptr", 0) ; Przepustka UIPI dla restartu (#SingleInstance)

#Include "..\AHK2_external_code\UIA.ahk"
; #Include "D:\PRACA\skrypryAHK\AHK2_Colorful_GUI\AHK2ColorfulGUI.ahk" 
#Include "..\AHK2_Colorful_GUI\AHK2ColorfulGUI.ahk"
#Include "mouse_ctrl_lib.ahk"
#Include "..\AHK2_My_libs\MojeFunkcje.ahk"
#Include "myHardwareWorker.ahk"

; #region --- IPC PROTOCOL (SSoT) ---
/** Dynamic Win32 message registration to prevent ID collisions.
 * OS returns a unique ID for this string. Both processes use it to talk safely. */
global myIpcChannelName := "MouseCtrl_IPC_Channel_v1"
global myIpcMsgId       := DllCall("User32\RegisterWindowMessage", "Str", myIpcChannelName, "UInt")
global myIpcSignature   := 0x5555
global myIpcSeparator   := "|"
global WM_COPYDATA      := 0x004A
global myWmiNamespace   := "winmgmts:\\.\root\WMI"
; #endregion

; #region --- SPRAWDZANIE UPRAWNIEŃ ---
; TODO: Fix skalowania (refaktor legendy do silnika)

global IniPath := A_ScriptDir . "\mouse_ctrl_settings.ini"
global myCachedStartupPath := ""

; Wczytaj config przed sprawdzeniem uprawnień
global Uprawnienia := Number(IniRead(IniPath, "Settings", "Uprawnienia", 1))

; Wymuszenie Admina (jeśli config pozwala)
if (!A_IsAdmin && Uprawnienia && !RegExMatch(DllCall("GetCommandLine", "str"), " /restart(?!\S)"))
    try Run('*RunAs "' . (A_IsCompiled ? A_ScriptFullPath . '" /restart' : A_AhkPath . '" /restart "' . A_ScriptFullPath . '"')), ExitApp()

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- INICJALIZACJA I PLIK INI ---

if !FileExist(IniPath) { ; Init default INI
    IniWrite(0, IniPath, "Settings", "DefaultProfile")
    IniWrite(3, IniPath, "Settings", "BrightnessStepMouse")
    IniWrite(5, IniPath, "Settings", "BrightnessStepKbd")
    IniWrite(2, IniPath, "Settings", "VolStepMouse")
    IniWrite(true, IniPath, "Settings", "Uprawnienia")
    IniWrite(1, IniPath, "Settings", "AdminStartLvl")
    IniWrite(1, IniPath, "Settings", "PokazPodpowiedzi")
    IniWrite(0.15, IniPath, "Settings", "HoldThreshold") ; Domyślny DoubleClick (s)
    IniWrite(0, IniPath, "Settings", "LastCustomActive")
    IniWrite(10, IniPath, "Settings", "LastBrightness")
    IniWrite(0, IniPath, "Settings", "LowerBrightness")
    IniWrite("HID\VID_4E53&PID_5407", IniPath, "Settings", "TargetMouseID")
}

; Wczytywanie ustawień
class DaneGlobalne {
    static __New() {
        if (A_Args.Length > 0 && (A_Args[1] == "WARMUP" || A_Args[1] == "DAEMON"))
            return
            
        try Sekcja := IniRead(IniPath, "Settings")
        catch 
            Sekcja := ""
            
        myIni := Map()
        Loop Parse, Sekcja, "`n", "`r"
            if RegExMatch(A_LoopField, "^(.*?)=(.*)$", &m)
                myIni[m[1]] := m[2]
                
        myRead(Klucz, Domyslna) {
            if myIni.Has(Klucz)
                return myIni[Klucz]
            IniWrite(Domyslna, IniPath, "Settings", Klucz)
            return Domyslna
        }

        global DefaultProfile      := Number(myRead("DefaultProfile", 0))
        global BrightnessStepMouse := Number(myRead("BrightnessStepMouse", 3))
        global BrightnessStepKbd   := Number(myRead("BrightnessStepKbd", 5))
        global VolStepMouse        := Number(myRead("VolStepMouse", 2))
        global PokazPodpowiedzi    := Number(myRead("PokazPodpowiedzi", 1))
        global myAdminStartLvl     := Number(myRead("AdminStartLvl", 1))
        global HoldThreshold       := Float(myRead("HoldThreshold", 0.15))
        global myLowerBrightness   := Number(myRead("LowerBrightness", 0))
        global ListaProfili        := ["AUTO (Detect)", "Custom Mouse + Keyboard", "Standard Mouse + Keyboard", "Keyboard Only", "OFF Mode"]

        if FileExist(A_ScriptDir . "\mouse_ctrl.ico")
            TraySetIcon(A_ScriptDir . "\mouse_ctrl.ico")
        global AktywneOkna := []
        global CurrentProfile := DefaultProfile 
        global currentBrightness := Number(myRead("LastBrightness", 10))
        global LegendaGui := 0
        global GlUs := 0
        global AktywnyTip := 0
        global GuiControls := {} 
        global szerListy := 200
        global Szerokośćpopupow := 500 
        global SzerkokośćOknaLegendy := 200
        global TargetMouseID := myRead("TargetMouseID", "HID\VID_4E53&PID_5407") 
        global CustomActive := Number(myRead("LastCustomActive", 0))
        global DystansDoZamkniecia := 100 ; Dystans w px do zamknięcia popupu
        global MyszNadIkona := false
        global TipLive := 5000 ; Czas życia tooltipa (ms)
        global EkranWygaszony := false
        
        global myAudioCache := "🔊?   "
        ; --- KONFIGURACJA MOTYWU (Centralne sterowanie z biblioteki) ---
        SilnikGUI.Konfiguruj("363533", 0.2, 0.4, 0.8, "bd4646", 0.1, 0.1) ; 363533, 0.2  - ramka
        SilnikGUI.TipDelayON := 0
        SilnikGUI.TipDelayOFF := 100
        ; Kompatybilność wsteczna (Globalne)
        global KolorMotywu     := SilnikGUI.Motyw.Tlo
        global KolorRamki      := SilnikGUI.Motyw.Ramka
        global KolorNieaktywny := SilnikGUI.Motyw.Nieaktywny
        global KolorTekst      := SilnikGUI.Motyw.Tekst
        global KolorWarn       := SilnikGUI.Motyw.Ostrzezenie
        global KolorPrzycisku  := SilnikGUI.Motyw.Przycisk
        OnExit(ZapiszStanSprzetowy)
    }
}

OnMessage(0x0200, ObslugaTooltipow)
OnMessage(0x211, DetectMenuEntry) ; WM_ENTERMENULOOP
DetectMenuEntry(wParam, lParam, msg, hwnd) => UsunTip()
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- KONFIGURACJA MENU TRAY ---
A_TrayMenu.Delete()
A_TrayMenu.Add("Show shortcuts", PokazListeSkrotow)
A_TrayMenu.Default := "Show shortcuts"
A_TrayMenu.ClickCount := 1
A_TrayMenu.Add()
A_TrayMenu.Add("Settings", PokazUstawienia)
A_TrayMenu.Add()
for i, nazwa in ListaProfili
    A_TrayMenu.Add(nazwa, ((idx, *) => UstawProfil(idx)).Bind(i-1))
A_TrayMenu.Add() 
A_TrayMenu.Add("Unlock Keys (Ctrl+Alt+R)", (*) => AwaryjneOdblokowanie())
A_TrayMenu.Add("Exit", (*) => ExitApp())

OnMessage(WM_COPYDATA, myOnHardwareStateReady)

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- STARTOWE POWIADOMIENIA I DETEKCJA ---
OnMessage(0x404, OnTrayMouseEvent) ; Obsługa najechania myszą na ikonę
global klawiszeZamykajace := ["~LButton", "~MButton", "~RButton Up", "~WheelUP", "~WheelDown", "~XButton1", "~XButton2"]

ZamknijWszystkie(*) {
    global AktywneOkna, ih
    static myAppReady := false
    if (myAppReady)
        return
    myAppReady := true

    (IsSet(ih) && ih is InputHook && ih.Stop())
    for okno in AktywneOkna {
        try okno.Destroy()
    }
    AktywneOkna := []
    
    for klawisz in klawiszeZamykajace
        Hotkey(klawisz, "Off")
    
    myBindLateHotkeys() ; [STRATEGIA 4] LATE BINDING: Absolute zero race conditions
}

stworzPowiadomienieStartowe(tekst, kolor, yPoz) => AktywneOkna.Push(GenerujGuiPowiadomienia(tekst, kolor, yPoz))

SetTimer(AsynchronicznaInicjalizacja, -1) ; Uruchom WMI w tle

AsynchronicznaInicjalizacja() {
    ; --- DAEMON ZOMBIE PREVENTION ---
    DetectHiddenWindows(true)
    for hw in WinGetList("MouseCtrl_Daemon_Window")
        try WinClose(hw)

    ; --- START DAEMON ---
    global TargetMouseID, myWorkerHwnd, myIpcMsgId, myIpcSignature, myIpcSeparator, myWmiNamespace
    try {
        myTargetExe := A_IsCompiled ? '"' A_ScriptFullPath '"' : '"' A_AhkPath '" "' A_ScriptFullPath '"'
        Run(myTargetExe ' "WARMUP"', , "Hide")
        Run(myTargetExe ' "DAEMON" "' A_ScriptHwnd '" "' TargetMouseID '" "' myIpcMsgId '" "' myIpcSignature '" "' myIpcSeparator '" "' myWmiNamespace '"', , "Hide", &WorkerPID)
        myWorkerHwnd := WinWait("MouseCtrl_Daemon_Window ahk_pid " WorkerPID,, 30)
    }

    ; Cache Shell API path
    global myCachedStartupPath := A_Startup . "\mouse_ctrl.lnk"
    
    A_IconTip := "Mouse Control"
    
    stworzPowiadomienieStartowe(PobierzNazweProfilu(), TipColor(), 0)
    stworzPowiadomienieStartowe(A_IsAdmin ? "FULL PERMISSIONS" : "RESTRICTED PERMISSIONS`nShortcuts won't work in system windows like`n Task Manager.", A_IsAdmin ? "9FFB88" : "FA8072", 70)
    
    global ih := InputHook("L1 M", "{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}{BS}{ScrollLock}{Del}{Ins}{Home}{End}{PgUp}{PgDn}{Up}{Down}{Left}{Right}{CapsLock}{F1}{F2}{F3}{F4}{F5}{F6}{F7}{F8}{F9}{F10}{F11}{F12}") 
    ih.KeyOpt("{All}", "+N")
    ih.OnEnd := ZamknijWszystkie
    ih.Start()
    
    for klawisz in klawiszeZamykajace
        Hotkey(klawisz, ZamknijWszystkie, "On")
        
    SetTimer(myDeferredInit, -1)
}

/** Synchronizes INI cache with actual hardware state after fast boot */
myDeferredInit() {
    myFetchHardwareState(7) ; Fetch Mouse(1) + Brightness(2) + Audio(4) on boot
}
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- MODUŁ AUTOWYKRYWANIA MYSZY ---
/** Sends IPC bitmask command to background daemon
 * @param mode 1:Mouse | 2:Brightness | 3:All | 4:Kill */
myFetchHardwareState(mode) {
    global myWorkerHwnd, myIpcMsgId
    if (IsSet(myWorkerHwnd) && myWorkerHwnd)
        try PostMessage(myIpcMsgId, mode, 0,, myWorkerHwnd)
}

/** Extracted logic to update mouse state and GUI */
myUpdateCustom(val) {
    global CustomActive, CurrentProfile
    if (CurrentProfile == 0) {
        myOldState := CustomActive
        CustomActive := val
        if (myOldState != CustomActive) {
            PokazTip((CustomActive ? "DETECTED" : "DISCONNECTED") . " Mouse: Custom", CustomActive ? "9FFB88" : "FA8072")
            LegendaIstnieje() && AktualizujListe()
        }
    }
}

myOnHardwareStateReady(wParam, lParam, msg, hwnd) {
    global myIpcSignature, myIpcSeparator, currentBrightness, myAudioCache
    if (NumGet(lParam, 0, "UPtr") != myIpcSignature) ; dwData (Signature check)
        return
        
    myStringPtr := NumGet(lParam, A_PtrSize * 2, "UPtr")
    myPayload := StrGet(myStringPtr, "UTF-16")
    myParts := StrSplit(myPayload, myIpcSeparator)
    
    myActions := [
        (val) => myUpdateCustom(Number(val)), 
        (val) => currentBrightness := Number(val),
        (val) => myAudioCache := String(val)
    ]
    
    for index, val in myParts {
        if (val != "-1" && myActions.Has(index))
            myActions[index](val)
    }

    return 1 ; Confirm receipt
}
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- FUNKCJE SYSTEMOWE ---

ZapiszStanSprzetowy(ExitReason, ExitCode) {
    IniWrite(CustomActive, IniPath, "Settings", "LastCustomActive")
    IniWrite(currentBrightness, IniPath, "Settings", "LastBrightness")
    myFetchHardwareState(4)
}

TipColor() => ["9FFB88", "fbf988", "fbf988", "fbc088", "FA8072"][CurrentProfile + 1]

LegendaIstnieje() => (IsSet(LegendaGui) && IsObject(LegendaGui) && WinExist("ahk_id " LegendaGui.Hwnd))
UstawieniaIstnieje() {
    try {
        return (IsSet(GlUs) && IsObject(GlUs) && WinExist("ahk_id " GlUs.GuiObj.Hwnd))
    }
    return false
}

OnTrayMouseEvent(wParam, lParam, msg, hwnd) {
    if (lParam != 0x200) 
    return
    global AktywnyTip, MyszNadIkona
    
    static myPhantomPreWarmed := false
    if (!myPhantomPreWarmed) {
        myPhantomPreWarmed := true
        ; Phantom Pre-warm: opóźniona kompilacja JIT przy pierwszym najechaniu
        SetTimer(() => (myPhantomGUI := SilnikGUI("Phantom"), myPhantomGUI.Zakoncz()), -50)
    }
    
    if (MyszNadIkona) 
        return SetTimer(UsunTip, -TipLive)

    MyszNadIkona := true
    
    if !TipIstnieje()
        PokazTip(PobierzNazweProfilu(), TipColor())

    SetTimer(UsunTip, -TipLive)
}

; Pobiera dynamicznie wyliczoną nazwę aktywnego profilu.
PobierzNazweProfilu() => ["AUTO: " . (CustomActive ? "Custom Mouse" : "Standard Mouse"), "MANUAL: Custom Mouse", "MANUAL: Standard Mouse", "Keyboard Only", "OFF Mode (Shortcuts disabled)"][CurrentProfile + 1]

UstawProfil(nr, pokazacTip := false) {
    global CurrentProfile := nr
    if (nr == 0)
        myFetchHardwareState(1) ; Fetch ONLY mouse state

    A_IconTip := "Mouse Control"

    ; Tip tylko gdy Legenda ukryta
    if (pokazacTip && !(LegendaIstnieje() && DllCall("IsWindowVisible", "Ptr", LegendaGui.Hwnd))) {
        PokazTip(PobierzNazweProfilu(), TipColor())
    }

    LegendaIstnieje() && AktualizujListe()
}
; #endregion
; #region teśc popupów
TipText := {
AdminTip : (A_IsAdmin 
                    ? "PERMISSION LEVEL:`nScript HAS ACCESS to system windows.`nYou can use shortcuts anywhere." 
                    : "PERMISSION LEVEL:`nScript HAS NO ACCESS to system windows.`nShortcuts won't work there.")
}
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- GENEROWANIE POPUPÓW ---

TipIstnieje() => (IsSet(AktywnyTip) && IsObject(AktywnyTip) && WinExist(AktywnyTip))

PokazTip(txt1, col1) { 
    global AktywnyTip, Szerokośćpopupow, KumulatywnyDystans, LastTrayX, LastTrayY, MyszNadIkona
    KumulatywnyDystans := 0 ; Reset licznika
    MouseGetPos(&LastTrayX, &LastTrayY) ; Start poz
    ; Blokada gdy Legenda widoczna
    if (LegendaIstnieje() && DllCall("IsWindowVisible", "Ptr", LegendaGui.Hwnd)) {
        MyszNadIkona := false ; Reset flagi (dla startu monitora)
        return
    }
    (AktywnyTip is Gui) && (AktywnyTip.Destroy(), AktywnyTip := 0)
    try (AktywnyTip := GenerujGuiPowiadomienia(txt1, col1, 0), SetTimer(MonitorujMysz, 100), SetTimer(UsunTip, -TipLive))
}
GenerujGuiPowiadomienia(tekst, kolor, yPoz) { ; Też dla powiadomień
    global Szerokośćpopupow
    g := Gui("+AlwaysOnTop -Caption +ToolWindow")
    g.BackColor := kolor
    g.SetFont("s20")
    g.Add("Text", "x0 W" . Szerokośćpopupow . " Center cBlack", tekst)
    g.Show("W" . Szerokośćpopupow . " Center NA y" . yPoz)
    return g
}
UsunTip() {
    global AktywnyTip
    (IsSet(AktywnyTip) && (AktywnyTip is Gui) && AktywnyTip.Destroy()), AktywnyTip := 0
}

MonitorujMysz() {
    global LastTrayX, LastTrayY, AktywnyTip, KumulatywnyDystans, MyszNadIkona
    global DystansDoZamkniecia
    
    ; Stop monitora, gdy brak okna
    if !TipIstnieje()
        return (SetTimer(MonitorujMysz, 0), MyszNadIkona := false)

    Step := SprawdzRuchMyszy(&LastTrayX, &LastTrayY, 0, true)
    
    ; 1. LOGIKA DYSTANSU (działa zawsze)
    if (Step > 0 && (KumulatywnyDystans += Step, KumulatywnyDystans >= DystansDoZamkniecia))
        return UsunTip()

    ; 2. Opuszczenie
    ; Ruch > 5px = wyjazd
    (MyszNadIkona && Step > 5) && MyszNadIkona := false && SetTimer(UsunTip, -TipLive/2) 
    
    (MyszNadIkona && Step == 0) && SetTimer(UsunTip, -TipLive/2) 
}


; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
;   #region --- OKNO USTAWIEŃ ---
PokazUstawienia(*) {
    global DefaultProfile, BrightnessStepMouse, BrightnessStepKbd, VolStepMouse, IniPath, GlUs, Uprawnienia
    global StartProf, Edit_BM, Edit_BK, Edit_VM, Edit_VD
    global StatusTextControl, Check_Autostart, Check_Podpowiedzi, UprawnieniaCheckbox
    SzerOknUst := 220
    SettingsTipDelON := 300
    pad := 10
    ;STATUS AUTOSTARU
    ShortcutPath := myCachedStartupPath
    TaskExists := myCheckAutostartTask()
    ShortcutExists := FileExist(ShortcutPath) ? 1 : 0
    
    GlUs := SilnikGUI("Mouse Control SETTINGS", "", {unikalny: 1, pokazPasek: 1, PadD: pad, PadR: pad, PadL: pad, ResizeMarg: 0})
    
    if (!GlUs.nowaInstancja) {
        GlUs.Pokaz()
        return
    }
    szerDD := 190
    AdminInfoCtrl := GlUs.Add("Text", "vadmininfoU +0x0100  y+10", (A_IsAdmin ? " ADMIN " : " REGULAR "))
    AdminInfoCtrl.SetFont("bold")    
    AdminInfoCtrl.GetPos(,,&Adw)
    AdminInfoCtrl.move(((SzerOknUst+pad)-(Adw/(A_ScreenDPI / 96)))/2)
    AdminInfoCtrl.HoverAction := (*) => SilnikGUI.CustomTooltip((TipText.AdminTip), {delayon:SettingsTipDelON, trybPozycji:AdminInfoCtrl, Align:"up-5", Transparent: 0.1, TransClick: 1}) ;

    Tytul := GlUs.Add("Text", "Center y+15 x" . ((SzerOknUst+pad)-szerDD)/2 . " w" . szerDD, "Default startup profile:")
    Tytul.SetFont("norm")
    
    StartProf := GlUs.DodajDDList(ListaProfili, 0, DefaultProfile + 1, szerDD, "x" . ((SzerOknUst+pad)-szerDD)/2 . " y+5")
    myDetectBtn := GlUs.DodajPrzycisk("Mouse Detect", myDetectMouseNative, "w" . szerDD . " x" . ((SzerOknUst+pad)-szerDD)/2 . " y+5")
    myDetectBtn.HoverAction := (*) => SilnikGUI.CustomTooltip("Detects the hardware ID of your Custom Mouse.`nRecommended: Keep only ONE mouse connected during detection.", {delayon:SettingsTipDelON, trybPozycji: myDetectBtn, Align: "up-5", Transparent: 0.1, TransClick: 1})
    GlUs.Ramka(Tytul, myDetectBtn, 8)
    Edit_BM := GlUs.DodajWierszKonfiguracji("Brightness (Mouse):", BrightnessStepMouse, {trybWalidacji: 0, minVal: 1, maxVal: 100, skok: 1, pozycja: "x20 y+20", SzerText: 140})
    Edit_BK := GlUs.DodajWierszKonfiguracji("Brightness (Kbd):", BrightnessStepKbd, {trybWalidacji: 0, minVal: 1, maxVal: 100, skok: 1, pozycja: "x20 y+10", SzerText: 140})
    Edit_VM := GlUs.DodajWierszKonfiguracji("Volume (Mouse):", VolStepMouse, {trybWalidacji: 0, minVal: 1, maxVal: 100, skok: 1, pozycja: "x20 y+10", SzerText: 140})
    Edit_VD := GlUs.DodajWierszKonfiguracji("Double click (s):", Format("{:.2f}", HoldThreshold), {trybWalidacji: 1, minVal: 0.05, maxVal: 1.0, skok: 0.05, pozycja: "x20 y+10", SzerText: 140})
    GlUs.Ramka(Edit_BM, Edit_VD, 8)

    StatusOpis := TaskExists ? "Status: Task Scheduler (Admin)" : (ShortcutExists ? "Status: Startup Folder (Regular)" : "Status: Disabled")
    IsAutostartActive := TaskExists || ShortcutExists

    Check_Autostart := GlUs.DodajCheckbox("Run at system startup", {czyZaznaczony: IsAutostartActive, pozycja: "xm  y+15"})
    Check_Autostart.OnEvent("Click", WeryfikujKlikniecieAutostartu)
    ; Czcionka statusu
    StatusTextControl := GlUs.Add("Text", "x" . Check_Autostart.LabelX . " y+2", StatusOpis,0)
    StatusTextControl.KolorBazowy := "Gray" ; [FIX] Customowy kolor z obsługą przyciemniania
    ; Reset czcionki
    GlUs.GuiObj.SetFont("s10 " . SilnikGUI.Motyw.Tekst)
    
    UprawnieniaCheckbox := GlUs.DodajCheckbox("Ask for admin permissions`non startup", {czyZaznaczony: Uprawnienia, pozycja: "xm y+10"})

    myPriorityOptions := ["0 - Real-Time", "1 - High", "2 - Above Normal", "3 - Normal", "4 - Default"]
    myLvlTitle := GlUs.Add("Text", "Center y+15 x" . ((SzerOknUst+pad)-szerDD)/2 . " w" . szerDD, "Admin start level:")
    myLvlTitle.SetFont("norm")
    myDDLCallback := (ctrl, *) => (ctrl.SelectedIndex == 1) ? SilnikGUI.CustomTooltip("⚠️ WARNING: Real-Time mode (0) can overload the CPU!`nIt may completely block mouse and keyboard input.", {delayon:SettingsTipDelON, Transparent: 0.1, TransClick: 1, kolorTla:"c420000",czyPogrubione: 1,kolorramki:"cff7f7f", kolorTekstu:"cff7f7f", trybPozycji: ctrl, Align: "+Down+10"}) : SilnikGUI.CustomTooltip()
    myStartLvlDDL := GlUs.DodajDDList(myPriorityOptions, myDDLCallback, myAdminStartLvl + 1, szerDD, "x" . ((SzerOknUst+pad)-szerDD)/2 . " y+5")
    myStartLvlDDL.HoverAction := (*) => myDDLCallback(myStartLvlDDL)
    GlUs.Ramka(myLvlTitle, myStartLvlDDL, 8)

    Check_Podpowiedzi := GlUs.DodajCheckbox("Show tooltips", {czyZaznaczony: PokazPodpowiedzi, pozycja: "xm y+15"})

    GlUs.DodajPrzycisk("Apply", (*) => ZapiszIUstaw(GlUs.GuiObj, StartProf, Edit_BM, Edit_BK, Edit_VM, Edit_VD, Check_Podpowiedzi, myStartLvlDDL, false), "y+20 w80 h30")
    GlUs.DodajPrzycisk("Save", (*) => ZapiszIUstaw(GlUs.GuiObj, StartProf, Edit_BM, Edit_BK, Edit_VM, Edit_VD, Check_Podpowiedzi, myStartLvlDDL, true), "x" . (SzerOknUst-80) . " yp w80 h30")
    GlUs.Pokaz()
    WinActivate("ahk_id " GlUs.GuiObj.Hwnd)
    Edit_BM.Focus()
}
WeryfikujKlikniecieAutostartu(ctrl, *) {
    ; czy istnieje zadanie Admina
    TaskExists := myCheckAutostartTask()
    
    ; Blokada zmiany adania bez uprawnień
    if (TaskExists && !A_IsAdmin) {
        ctrl.Value := !ctrl.Value ; Cofnij zmianę wizualną (odbij haczyk)
        SilnikGUI.OknoBledu("⚠️ ACCESS DENIED", "Cannot change admin startup settings without permissions.", "Run program as Administrator.", GlUs.GuiObj.Hwnd)
    }
}
ZastosujZmianyAutostartu() {
    global StatusTextControl, Check_Autostart, GlUs
    
    czyWlaczone := Check_Autostart.Value
    ManageAutostart(czyWlaczone)
    
    ; 2. Weryfikacja stanu (0/1)
    ShortcutPath := myCachedStartupPath
    
    ; Check zadania (0=sukces)
    TaskExists := myCheckAutostartTask()
    ShortcutExists := FileExist(ShortcutPath) ? 1 : 0
    
    StanFaktyczny := (TaskExists || ShortcutExists) ? 1 : 0
    
    ; 3. Cofnij zmianę przy braku uprawnień
    if (czyWlaczone != StanFaktyczny) {
        Check_Autostart.Value := StanFaktyczny 
        SilnikGUI.OknoBledu("⚠️ ACCESS DENIED", "Cannot change admin startup settings without permissions.", "Run program as Administrator.", GlUs.GuiObj.Hwnd)
    }

    ; 4. Aktualizacja terści
    NowyStatus := TaskExists ? "Status: Task Scheduler (Admin)" : (ShortcutExists ? "Status: Startup Folder (Regular)" : "Status: Disabled")
    StatusTextControl.Value := NowyStatus
}
ZapiszIUstaw(G, D, BM, BK, VM, VD, CP, SL, ZamknijOkno := true) {
    global DefaultProfile, BrightnessStepMouse, BrightnessStepKbd, VolStepMouse, HoldThreshold, PokazPodpowiedzi, IniPath, Uprawnienia, UprawnieniaCheckbox, Check_Autostart, myAdminStartLvl
    
    ; 1. Pobranie wartości (SilnikGUI gwarantuje typ i zakres)
    DefaultProfile      := D.SelectedIndex - 1 
    BrightnessStepMouse := Number(BM.Value)
    BrightnessStepKbd   := Number(BK.Value)
    VolStepMouse        := Number(VM.Value)
    HoldThreshold       := Number(StrReplace(VD.Value, ",", ".")) ; Safety check dla float
    PokazPodpowiedzi    := CP.Value
    Uprawnienia         := UprawnieniaCheckbox.Value
    myAdminStartLvl     := SL.SelectedIndex - 1

    ; 2. Zapis INI
    IniWrite(DefaultProfile, IniPath, "Settings", "DefaultProfile") 
    IniWrite(Uprawnienia, IniPath, "Settings", "Uprawnienia")
    IniWrite(myAdminStartLvl, IniPath, "Settings", "AdminStartLvl")
    IniWrite(PokazPodpowiedzi, IniPath, "Settings", "PokazPodpowiedzi")
    IniWrite(BrightnessStepMouse, IniPath, "Settings", "BrightnessStepMouse") 
    IniWrite(BrightnessStepKbd, IniPath, "Settings", "BrightnessStepKbd") 
    IniWrite(VolStepMouse, IniPath, "Settings", "VolStepMouse")
    IniWrite(HoldThreshold, IniPath, "Settings", "HoldThreshold") 
   
    ZastosujZmianyAutostartu()

    if (ZamknijOkno)
        WinClose("ahk_id " G.Hwnd)
    PokazTip(ZamknijOkno ? "Settings Saved!" : "Settings applied", "9FFB88")
}

ManageAutostart(enable) { 
    global myAdminStartLvl
    TaskName := "MouseCtrlAutostart"
    ShortcutPath := myCachedStartupPath
    
    ; Sprawdź harmonogram
    TaskExists := myCheckAutostartTask()

    if (enable) {
        if A_IsAdmin {
            ; Admin: COM (szybki)
            try {
                Service := ComObject("Schedule.Service")
                Service.Connect()
                RootFolder := Service.GetFolder("\")

                ; Nowe zadanie
                TaskDef := Service.NewTask(0)
                TaskDef.RegistrationInfo.Description := "Runs Mouse Control with admin permissions"
                TaskDef.RegistrationInfo.Author := "MouseCtrl"
                
                ; Konfiguracja: Admin, Priorytet, Bateria
                TaskDef.Principal.RunLevel := 1 ; (admin=1/normal=0)
                TaskDef.Settings.Priority := myAdminStartLvl
                TaskDef.Settings.DisallowStartIfOnBatteries := false
                TaskDef.Settings.StopIfGoingOnBatteries := false
                TaskDef.Settings.ExecutionTimeLimit := "PT0S" ; Brak limitu czasu

                ; Wyzwalacz: Logowanie
                Triggers := TaskDef.Triggers
                Trigger := Triggers.Create(9) ; 9 = TASK_TRIGGER_LOGON
                Trigger.Enabled := true

                ; Akcja: Skrypt
                Actions := TaskDef.Actions
                Action := Actions.Create(0) ; 0 = TASK_ACTION_EXEC
                Action.Path := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
                Action.Arguments := A_IsCompiled ? "" : '"' . A_ScriptFullPath . '"'
                Action.WorkingDirectory := A_ScriptDir ; Ustawienie katalogu roboczego

                ; Zapis (Aktualizacja)
                RootFolder.RegisterTaskDefinition(TaskName, TaskDef, 6, "", "", 3)
            } catch as err {
                MsgBox("Failed to create scheduled task: " . err.Message, "Error", "Icon!")
            }

            if FileExist(ShortcutPath)
                FileDelete(ShortcutPath)
        } else {
            ; Zwykły: Skrót (jeśli brak zadania)
            if !TaskExists {
                try FileCreateShortcut(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, ShortcutPath, A_ScriptDir, A_IsCompiled ? "" : '"' . A_ScriptFullPath . '"')
            }
        }
    } else {
        ; Wyłącz: Usuń oba
        try {
            myService := ComObject("Schedule.Service")
            myService.Connect()
            myService.GetFolder("\").DeleteTask(TaskName, 0)
        }
        if FileExist(ShortcutPath)
            FileDelete(ShortcutPath)
    }
}

/** Checks if admin autostart task exists via COM (avoids slow schtasks.exe I/O) */
myCheckAutostartTask() {
    try {
        myService := ComObject("Schedule.Service")
        myService.Connect()
        myService.GetFolder("\").GetTask("MouseCtrlAutostart")
        return true
    }
    return false
}

/** Detects the first valid mouse HID and saves it to config */
myDetectMouseNative(*) {
    global TargetMouseID, IniPath, GlUs
    myNumDevices := 0
    DllCall("User32\GetRawInputDeviceList", "Ptr", 0, "UInt*", &myNumDevices, "UInt", A_PtrSize * 2)
    if (!myNumDevices)
        return

    myRawInputDeviceList := Buffer(myNumDevices * (A_PtrSize * 2), 0)
    DllCall("User32\GetRawInputDeviceList", "Ptr", myRawInputDeviceList, "UInt*", &myNumDevices, "UInt", A_PtrSize * 2)

    Loop myNumDevices {
        myHandle := NumGet(myRawInputDeviceList, (A_Index - 1) * (A_PtrSize * 2), "Ptr")
        myType := NumGet(myRawInputDeviceList, ((A_Index - 1) * (A_PtrSize * 2)) + A_PtrSize, "UInt")

        if (myType == 0) { ; 0 = RIM_TYPEMOUSE
            myNameLength := 0
            DllCall("User32\GetRawInputDeviceInfo", "Ptr", myHandle, "UInt", 0x20000007, "Ptr", 0, "UInt*", &myNameLength)
            if (myNameLength > 0) {
                myNameBuffer := Buffer(myNameLength * 2, 0)
                DllCall("User32\GetRawInputDeviceInfo", "Ptr", myHandle, "UInt", 0x20000007, "Ptr", myNameBuffer, "UInt*", &myNameLength)
                if RegExMatch(StrReplace(StrGet(myNameBuffer), "#", "\"), "i)(HID\\VID_[0-9A-F]+&PID_[0-9A-F]+)", &myMatch) {
                    TargetMouseID := myMatch[1]
                    IniWrite(TargetMouseID, IniPath, "Settings", "TargetMouseID")
                    if WinExist("ahk_id " GlUs.GuiObj.Hwnd)
                        WinClose("ahk_id " GlUs.GuiObj.Hwnd)
                    PokazTip("Detected & Saved:`n" . TargetMouseID . "`nRestarting...", "9FFB88")
                    SetTimer(() => Reload(), -2000) ; Fast script reload to apply new ID to worker
                    return
                }
            }
        }
    }
    SilnikGUI.OknoBledu("DETECTION FAILED", "No hardware matching HID\VID pattern found.", "Check your USB connection.", GlUs.GuiObj.Hwnd)
}

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- OKNO LEGENDY ---

; ============================================================================================================================================================
; SEKCJA 1: TWORZENIE I AKTUALIZACJA GUI
; ============================================================================================================================================================

PokazListeSkrotow(*) {
    global LegendaGui, CurrentProfile, GuiControls, GruboscRamki
    global SzerkokośćOknaLegendy, CustomActive
    global WymiaryLegendy 

    ; 1. Odśwież istniejące
    if LegendaIstnieje() {
        AktualizujListe()
        AktualizujTooltipWLocie()
        return
    }

    ; 2. Wstepnie Oblicz szerokość
    dane_startowe := TrescLegendy(CurrentProfile, CustomActive)
    WymiaryLegendy := ObliczSzerokoscLegendy(dane_startowe)
    SzerkokośćOknaLegendy := WymiaryLegendy.Total
    
    ; 3. Inicjalizacja GUI
    LegendaGui := Gui("+AlwaysOnTop +Border -Caption", "Mouse Control LEGEND")
    kolorTla := KolorMotywu
    LegendaGui.BackColor := kolorTla
    GruboscRamki := 2
    GuiControls.RamkaTla := SilnikGUI.RysujObrys(LegendaGui, 0, 0, 0, 0, KolorRamki, GruboscRamki)
    
    ; 4. Kontrolki (Pozycjonowanie w AktualizujListe)
    
    ; --- Nagłówek i Profil ---
    LegendaGui.SetFont("s15 bold " . KolorTekst, "Segoe UI")
    GuiControls.UprawnieniaText := LegendaGui.Add("Text", "vUprawnieniaText +0x0100 Center x0 w" . SzerkokośćOknaLegendy, (A_IsAdmin ? "ADMIN" : "REGULAR"))
    
    LegendaGui.SetFont("s10 norm")
    GuiControls.DDL := LegendaGui.Add("DropDownList", "x0 w" . szerListy . " Background" . KolorMotywu . " " . KolorTekst . " Choose" . (CurrentProfile + 1), ListaProfili)
    GuiControls.DDL.OnEvent("Change", (ctrl, *) => UstawProfil(ctrl.Value - 1, false)) 
    
    ; --- Nagłówki Sekcji ---
    LegendaGui.SetFont("s15 bold")
    GuiControls.Header     := LegendaGui.Add("Text", "vAutoTryb +0x0100 Center x0 " . KolorTekst, "")
    GuiControls.KlawHeader := LegendaGui.Add("Text", "vNaglowekKlawiatury +0x0100 Center x0 " . KolorTekst, "")
    GuiControls.MyszHeader := LegendaGui.Add("Text", "Center x0 " . KolorTekst, "")
    
    ; --- Treść (Kolumny) ---
    LegendaGui.SetFont("s13 w100")
    ; Sekcja Klawiatury
    GuiControls.KlawTextL      := LegendaGui.Add("Text", "vListaLKlawiatury +0x0100 Right x0 " . KolorTekst, "")
    GuiControls.KlawTextR      := LegendaGui.Add("Text", "vListaRKlawiatury +0x0100 Left x+0 " . KolorTekst, "")
    GuiControls.KlawTextCenter := LegendaGui.Add("Text", "Center x0 c" . KolorNieaktywny . " Hidden", "")
    ; Mysz
    GuiControls.MyszTextL      := LegendaGui.Add("Text", "Right x0 " . KolorTekst, "")
    GuiControls.MyszTextR      := LegendaGui.Add("Text", "Left x+0 " . KolorTekst, "")
    GuiControls.MyszTextCenter := LegendaGui.Add("Text", "Center x0 c" . KolorNieaktywny . " Hidden", "")
    
    ; Stopka
    LegendaGui.SetFont("s13 bold")
    GuiControls.BtnSettings := LegendaGui.Add("Text", "w140 h30 Center Background" . KolorPrzycisku . " " . KolorTekst . " +Border +0x0200", "Settings (F1)")
    GuiControls.BtnSettings.OnEvent("Click", (*) => (PokazUstawienia(), LegendaGui.Hide()))
    
    LegendaGui.SetFont("s9", "Segoe UI")
    GuiControls.Exit := LegendaGui.Add("Text", "Center x0 c" . KolorNieaktywny, "(Click this window to close)")
    
    AktualizujListe()
    UsunTip()
}

AktualizujListe() { 
    global CurrentProfile, GuiControls, CustomActive, SzerkokośćOknaLegendy, LegendaGui, WymiaryLegendy, GruboscRamki
    
    try GuiControls.DDL.Choose(CurrentProfile + 1)
    
    ; 1. Dane i wymiary
    dane := TrescLegendy(CurrentProfile, CustomActive)
    WymiaryLegendy := ObliczSzerokoscLegendy(dane)
    SzerkokośćOknaLegendy := WymiaryLegendy.Total
    
    start_x_klaw := (SzerkokośćOknaLegendy - (WymiaryLegendy.KL + WymiaryLegendy.KR)) / 2
    start_x_mysz := (SzerkokośćOknaLegendy - (WymiaryLegendy.ML + WymiaryLegendy.MR)) / 2
    
    ; 2. Układ
    
    ; A. Góra
    GuiControls.UprawnieniaText.Move((SzerkokośćOknaLegendy - WymiaryLegendy.wUpr) / 2, 10, WymiaryLegendy.wUpr)
    GuiControls.UprawnieniaText.Redraw()
    GuiControls.UprawnieniaText.GetPos(,,,&hUpr)
    
    y_curr := 10 + hUpr + 10
    GuiControls.DDL.Move((SzerkokośćOknaLegendy-szerListy)/2, y_curr)
    GuiControls.DDL.Redraw()
    GuiControls.DDL.GetPos(,,,&hDDL)
    y_curr += hDDL + 10

    ; B. Sekcje
    y_curr := OdswiezNaglowek(y_curr, GuiControls.Header, dane.Header, WymiaryLegendy.wMainHead)
    y_curr := OdswiezSekcje(y_curr, GuiControls.KlawHeader, GuiControls.KlawTextL, GuiControls.KlawTextR, GuiControls.KlawTextCenter, dane.KlawHeader, dane.KlawText, dane.KlawKolor, WymiaryLegendy.KL, WymiaryLegendy.KR, WymiaryLegendy.KS, WymiaryLegendy.hK, start_x_klaw, WymiaryLegendy.wHeadK)
    y_curr := OdswiezSekcje(y_curr, GuiControls.MyszHeader, GuiControls.MyszTextL, GuiControls.MyszTextR, GuiControls.MyszTextCenter, dane.MyszHeader, dane.MyszText, dane.MyszKolor, WymiaryLegendy.ML, WymiaryLegendy.MR, WymiaryLegendy.MS, WymiaryLegendy.hM, start_x_mysz, WymiaryLegendy.wHeadM)
    
    ; C. Dół (Przyciski)
    GuiControls.BtnSettings.Move((SzerkokośćOknaLegendy-140)/2, y_curr)
    GuiControls.BtnSettings.Redraw()
    
    y_exit := y_curr + 30 + 10
    GuiControls.Exit.Move((SzerkokośćOknaLegendy - WymiaryLegendy.wExit) / 2, y_exit, WymiaryLegendy.wExit)
    GuiControls.Exit.Redraw()
    GuiControls.Exit.GetPos(,,, &hExit) ; Pobieramy wysokość ostatniego elementu

    ; 3. Finalizacja
    wysokosc_okna := y_exit + hExit + 10
    GuiControls.RamkaTla.Move(0, 0, SzerkokośćOknaLegendy, wysokosc_okna)
    UsunTip()
    LegendaGui.Show("w" . SzerkokośćOknaLegendy . " h" . wysokosc_okna . " Center NA")
}

; ============================================================================================================================================================
; SEKCJA 2: FUNKCJE POMOCNICZE (LAYOUT I FORMATOWANIE)
; ============================================================================================================================================================

AktualizujSekcje(tekst, ctrlL, ctrlR, ctrlC, kolor) {
    if (tekst = "Shortcuts disabled") {
        ctrlL.Visible := false, ctrlR.Visible := false
        ctrlC.Visible := true, ctrlC.Value := tekst
        if (kolor != "")
            ctrlC.SetFont(kolor)
    } else {
        ctrlL.Visible := true, ctrlR.Visible := true
        ctrlC.Visible := false
        RozdzielNaKolumny(tekst, ctrlL, ctrlR, kolor)
    }
}

RozdzielNaKolumny(tekst, ctrlL, ctrlR, kolor, separator := "=") {
    txtL := "", txtR := ""
    Loop Parse, tekst, "`n", "`r" {
        if (separator != "" && InStr(A_LoopField, separator)) {
            czesc := StrSplit(A_LoopField, separator, , 2)
            txtL .= czesc[1] . "`n"
            txtR .= separator . czesc[2] . "`n"
        } else {
            txtL .= A_LoopField . "`n"
            txtR .= "`n"
        }
    }
    ctrlL.Value := txtL
    ctrlR.Value := txtR
    if (kolor != "") {
        ctrlL.SetFont(kolor)
        ctrlR.SetFont(kolor)
    }
}

OdswiezNaglowek(yStart, cHead, txtHead, szerokosc) {
    global SzerkokośćOknaLegendy
    cHead.Value := txtHead
    cHead.GetPos(,,,&hHead)
    
    if (txtHead == "") {
        hHead := 0
        marginHead := 0
        cHead.Visible := false
        startX := 0
    } else {
        if (hHead < 10) hHead := 25
        marginHead := 10
        cHead.Visible := true
        startX := (SzerkokośćOknaLegendy - szerokosc) / 2
    }
    cHead.Move(startX, yStart, szerokosc, hHead)
    cHead.Redraw()
    return yStart + hHead + marginHead
}

OdswiezSekcje(yStart, cHead, cL, cR, cC, txtHead, txtContent, kolor, wL, wR, wSingle, hContent, startX, szerokoscNaglowka) {
    global SzerkokośćOknaLegendy
    
    ; 1. Treść i styl
    cHead.Value := txtHead
    cHead.SetFont(kolor)
    AktualizujSekcje(txtContent, cL, cR, cC, kolor)
    
    ; 2. Pozycjonowanie nagłówka
    yPoNaglowku := OdswiezNaglowek(yStart, cHead, txtHead, szerokoscNaglowka)
    
    ; 3. Pozycjonowanie Treści
    hRealContent := (txtContent == "") ? 0 : hContent
    marginContent := (txtContent == "") ? 0 : 10
    
    cL.Move(startX, yPoNaglowku, wL, hRealContent)
    cR.Move(startX + wL, yPoNaglowku, wR, hRealContent)
    
    if (txtContent == "Shortcuts disabled") {
        cC.Move((SzerkokośćOknaLegendy - wSingle) / 2, yPoNaglowku, wSingle, hRealContent)
    } else {
        cC.Move(0, yPoNaglowku, SzerkokośćOknaLegendy, hRealContent)
    }
    
    cL.Redraw(), cR.Redraw(), cC.Redraw()
    return yPoNaglowku + hRealContent + marginContent
}

; ============================================================================================================================================================
; SEKCJA 3: DANE I OBLICZENIA
; ============================================================================================================================================================

TrescLegendy(profil, CustomState) {
    dane := {Header: "", KlawHeader: "", KlawText: "", MyszHeader: "", MyszText: "", KlawKolor: KolorTekst, MyszKolor: KolorTekst}
    
    ; Definicje tekstów
    txtKlawiatura := "Ctrl+Alt+R = Unlock keys`nCtrl+Alt+P = Screenshot`nCtrl+F1/F2 = Brightness`nCtrl+F12 = Change profile`nShift + `` = ~"
    txtCustom    := "Right(Hold) = Shift`nRight + Wheel = Volume`nRight + Middle = Mute`nRight + X1 = Alt+Tab`nRight + X2 = Shift+Alt+Tab`nRight(2x) = F11`nX1 + Wheel = Brightness`nX1 + Middle = Screen off`nX1(2x) = Esc`nX1(2xHold) + Wheel = Arrows 🡰 🡲`nX2(Hold) = Ctrl`nX2(Hold) + Wheel = Zoom 🔍`nX2 + Left(2x) = Ctrl+V`nX2 + Left(2xHold) = LClick+Ctrl+V`nX2 + Right = Ctrl+C`nX2 + Right(Hold) = Ctrl+X`nX2 + Right(2x) = LClick+Ctrl+C`nX2 + Right(2xHold) = LClick+Ctrl+X`nX2 + X1 + Wheel = Ctrl+Z/Y`nX2(2x) = Ctrl+Shift+S`nX2(2xHold) + Wheel = Horiz. Scroll"
    txtStandard   := "Right(Hold) = Shift`nRight + Wheel = Volume`nRight + Middle = Mute`nRight + Left = Alt+Tab`nRight(2x) = F11`nRight(2xHold) + Wheel = Arrows / H-Scroll (LClick)`nLeft + Wheel = Brightness`nLeft + Middle = Screen off`nLeft + Right = Alt+Tab"

    ; Wartości domyślne
    dane.Header     := (profil == 0) ? "AUTO" : ((profil == 4) ? "" : "MANUAL")
    dane.KlawHeader := (profil == 4) ? "ALL DISABLED" : "— KEYBOARD —"
    dane.KlawText   := (profil == 4) ? "Shortcuts disabled" : txtKlawiatura
    dane.KlawKolor  := (profil == 4) ? "c" . KolorWarn : KolorTekst
    dane.MyszHeader := [(CustomState ? "— Custom MOUSE —" : "— STANDARD MOUSE —"), "— Custom MOUSE —", "— STANDARD MOUSE —", "--- MOUSE ---", ""][profil + 1]
    dane.MyszText   := [(CustomState ? txtCustom : txtStandard), txtCustom, txtStandard, "Shortcuts disabled", ""][profil + 1]
    dane.MyszKolor  := (profil == 3) ? "c" . KolorNieaktywny : KolorTekst
    return dane
}

ObliczSzerokoscLegendy(dane) {
    dummyGui := Gui()
    dummyGui.SetFont("s13 w100", "Segoe UI") ; Czcionka standard

    ; Lokalna funkcja pomiarowa dla legendy (bez zaleznosci od usuniętego MojeFunkcje)
    ZmierzWymiarySekcji(tekst, separator := "") {
        maxLeft := 0, maxRight := 0, maxSingle := 0
        Loop Parse, tekst, "`n", "`r" {
            if (A_LoopField == "")
                continue
            if (separator != "" && InStr(A_LoopField, separator)) {
                parts := StrSplit(A_LoopField, separator, , 2)
                dummyGui.Add("Text",, parts[1]).GetPos(,, &wL)
                dummyGui.Add("Text",, separator . parts[2]).GetPos(,, &wR)
                maxLeft := Max(maxLeft, wL), maxRight := Max(maxRight, wR)
            } else {
                dummyGui.Add("Text",, A_LoopField).GetPos(,, &wS)
                maxSingle := Max(maxSingle, wS)
            }
        }
        return {L: maxLeft, R: maxRight, Single: maxSingle}
    }

    ; Mierzymy sekcję Klawiatury
    wymiaryK := ZmierzWymiarySekcji(dane.KlawText, "=")
    ; Mierzymy sekcję Myszy
    wymiaryM := ZmierzWymiarySekcji(dane.MyszText, "=")
    
    ; Pomocnik pomiaru
    MierzElement(txt, &w:=0, &h:=0) => dummyGui.Add("Text",, txt).GetPos(,, &w, &h)

    MierzElement(dane.KlawText,, &hK)
    MierzElement(dane.MyszText,, &hM)
    
    ; Czcionka nagłówków (S15 Bold)
    dummyGui.SetFont("s15 bold", "Segoe UI")
    
    MierzElement(dane.KlawHeader, &wHeadK)
    MierzElement(dane.MyszHeader, &wHeadM)
    MierzElement(dane.Header, &wMainHead)
    MierzElement((A_IsAdmin ? "ADMIN" : "REGULAR"), &wUpr)

    ; Pomiar stopki (S9)
    dummyGui.SetFont("s9", "Segoe UI")
    MierzElement("(Click this window to close)", &wExit)
    
    dummyGui.Destroy()
    
    ; Szerokość całkowita okna
    szerokoscK := wymiaryK.L + wymiaryK.R
    szerokoscM := wymiaryM.L + wymiaryM.R
    maxContent := Max(szerokoscK, szerokoscM, wymiaryK.Single, wymiaryM.Single)
    maxHeader := Max(wHeadK, wHeadM, wMainHead, wUpr)
    
    ; Marginesy (+40px czyli 20 na stronę)
    totalW := Max(maxContent, maxHeader, szerListy) + 40
        
    return {Total: totalW, KL: wymiaryK.L, KR: wymiaryK.R, ML: wymiaryM.L, MR: wymiaryM.R, KS: wymiaryK.Single, MS: wymiaryM.Single, hK: hK, hM: hM, wHeadK: wHeadK, wHeadM: wHeadM, wMainHead: wMainHead, wUpr: wUpr, wExit: wExit}
}

; ============================================================================================================================================================
; SEKCJA 4: OBSŁUGA TOOLTIPÓW (DLA ELEMENTÓW LEGENDY)
; ============================================================================================================================================================

ObslugaTooltipow(wParam, lParam, msg, hwnd) {
    global LegendaGui, CurrentProfile, GlUs
    static OstatniCtrl := 0, OstatniaTresc := ""

    ; Walidacja HWND
    if !IsInteger(hwnd)
        return

    currCtrl := GuiCtrlFromHwnd(hwnd)
    if !currCtrl
        return
        
    ; Detekcja okna (Legenda lub Ustawienia)
    isLegenda := (IsSet(LegendaGui) && IsObject(LegendaGui) && currCtrl.Gui == LegendaGui)
    isUstawienia := (IsSet(GlUs) && IsObject(GlUs) && GlUs.GuiObj && currCtrl.Gui == GlUs.GuiObj)

    Tresc := ""
    if (isLegenda || isUstawienia) {
        switch currCtrl.Name {
            case "UprawnieniaText", "admininfoU":
                Tresc := TipText.AdminTip
        }
        
    }

    if (currCtrl == OstatniCtrl && Tresc == OstatniaTresc)
        return

    OstatniCtrl := currCtrl
    OstatniaTresc := Tresc

    if (Tresc != "")
        SilnikGUI.CustomTooltip(Tresc, {trybPozycji: currCtrl, Align:"+Down+10"})
} 

; Odświeżanie tipa pod myszą
AktualizujTooltipWLocie() => LegendaIstnieje() && (MouseGetPos(,,, &hCtrl, 2), ObslugaTooltipow(0, 0, 0, hCtrl))

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- OBSŁUGA ZMIANY JASNOŚCI ---

ZmianaJasnosci(delta) {
    global currentBrightness, myWorkerHwnd, myIpcMsgId, myLowerBrightness
    currentBrightness := Min(Max(currentBrightness + delta, myLowerBrightness), 100)
    if (IsSet(myWorkerHwnd) && myWorkerHwnd)
        try PostMessage(myIpcMsgId, 5, currentBrightness,, myWorkerHwnd)
    SilnikGUI.CustomTooltip("Brightness: " . currentBrightness . "%  ◑", {czas: 1500})
}

ZmianaGlosnosci(delta) {
    SoundSetVolume((delta > 0 ? "+" : "-") . Abs(delta))
    SilnikGUI.CustomTooltip(PobierzStatusAudio(), {czas: 1500})
}

PrzelaczWyciszenie() {
    SoundSetMute(-1)
    SilnikGUI.CustomTooltip(PobierzStatusAudio(), {czas: 1500})
}

WygasEkran(klawisz := "LButton") {
    global EkranWygaszony
    static BlackScreenGui := 0
    static ZegarCtrl := 0
    static OdswiezZegar := () => (ZegarCtrl ? ZegarCtrl.Value := FormatTime(,"dd.MM.yyyy") "`n" FormatTime(,"HH:mm:ss") : "")
    static WymusZgaszenie := () => ((BlackScreenGui && WinExist(BlackScreenGui.Hwnd)) ? SendMessage(0x112, 0xF170, 2,, "Program Manager") : WygasEkran())
    static hPowerNotify := 0
    static mX := 0, mY := 0
    static ResetNaRuch := () => (SprawdzRuchMyszy(&mX, &mY, 3, true) ? SetTimer(WymusZgaszenie, -3000) : 0)
    static ObslugaWybudzenia := (wParam, lParam, msg, hwnd) => ((wParam == 0x8013) ? ((NumGet(lParam, 20, "UInt") == 1) ? (SetTimer(WymusZgaszenie, -3000), MouseGetPos(&mX, &mY), SetTimer(ResetNaRuch, 100)) : SetTimer(ResetNaRuch, 0)) : 0)

    if (BlackScreenGui) {
        if (hPowerNotify) {
            DllCall("User32\UnregisterPowerSettingNotification", "Ptr", hPowerNotify)
            hPowerNotify := 0
        }
        OnMessage(0x0218, ObslugaWybudzenia, 0) ; Wyrejestruj nasłuch
        SetTimer(WymusZgaszenie, 0)
        SetTimer(ResetNaRuch, 0) ; Stop Watchdoga
        SetTimer(OdswiezZegar, 0) ; Stop zegara
        try BlackScreenGui.Destroy()
        BlackScreenGui := 0
        ZegarCtrl := 0
        EkranWygaszony := false
        SendMessage(0x112, 0xF170, -1,, "Program Manager") ; Wymusza wybudzenie
        return
    }

    SilnikGUI.CustomTooltip("RELEASE BUTTONS")
    KeyWait(klawisz)
    KeyWait("MButton") ; Dodatkowa blokada, aby przypadkowe puszczenie przycisku nie wybudziło ekranu
    SilnikGUI.CustomTooltip()

    EkranWygaszony := true

    BlackScreenGui := Gui("+AlwaysOnTop -Caption -SysMenu +ToolWindow -DPIScale")
    BlackScreenGui.BackColor := "Black"
    BlackScreenGui.OnEvent("Close", (*) => WygasEkran()) ; Obsługa Alt+F4
        
        BlackScreenGui.SetFont("s25 c3a3a3a")
        ZegarCtrl := BlackScreenGui.Add("Text", "x0 y50 w" A_ScreenWidth " Center Hidden", FormatTime(,"dd.MM.yyyy") "`n" FormatTime(,"HH:mm:ss"))
        
        kombinacjaKlawiszy := (klawisz = "XButton1") ? "X1 + RIGHT" : "LEFT + MIDDLE"
        BlackScreenGui.SetFont("s35 bold")
        tekstInfo := BlackScreenGui.Add("Text", "x0 y" (A_ScreenHeight // 2 - 100) " w" A_ScreenWidth " Center Hidden", "PRESS AGAIN`n`n" kombinacjaKlawiszy "`n`nTO UNLOCK")
        
        SetTimer(() => (ZegarCtrl ? tekstInfo.Visible := ZegarCtrl.Visible := true : 0), -1000) ; Safe-check
        SetTimer(OdswiezZegar, 1000)

    BlackScreenGui.Show(" NA") ; Pokrywa wszystkie monitory
    BlackScreenGui.Maximize()
    WinActivate(BlackScreenGui.Hwnd) ; Zapewnia, że ekran blokady jest na wierzchu

    ; Rejestracja natywnego event-driven detekcji ekranu (GUID_SESSION_DISPLAY_STATUS)
    GUID_DISPLAY := Buffer(16)
    NumPut("UInt", 0x2B84C20E, "UShort", 0xAD23, "UShort", 0x4DDF, "UChar", 0x93, "UChar", 0xDB, "UChar", 0x05, "UChar", 0xFF, "UChar", 0xBD, "UChar", 0x7E, "UChar", 0xFC, "UChar", 0xA5, GUID_DISPLAY)
    hPowerNotify := DllCall("User32\RegisterPowerSettingNotification", "Ptr", BlackScreenGui.Hwnd, "Ptr", GUID_DISPLAY, "UInt", 0, "Ptr")
    OnMessage(0x0218, ObslugaWybudzenia, 1) ; Start nasłuchu

    WymusZgaszenie()
}

PobierzStatusAudio() {
    global myAudioCache
    return myAudioCache . Round(SoundGetVolume()) . "%" . (SoundGetMute() ? "  🔉X" : "  🔊 ")
}
; #region --- HOTKEYE DLA OKNA LEGENDY ---

; #region --- LATE BINDING (STRATEGIA 4) ---

myBindLateHotkeys() {
    ; --- OKNO LEGENDY ---
    HotIf((*) => LegendaIstnieje() && DllCall("IsWindowVisible", "Ptr", LegendaGui.Hwnd))
    Hotkey("WheelDown", myLegendaWheelDown, "On")
    Hotkey("WheelUp", myLegendaWheelUp, "On")
    Hotkey("~LButton", myLegendaLButton, "On")
    Hotkey("~Esc", (*) => LegendaGui.Hide(), "On")
    Hotkey("~MButton", (*) => LegendaGui.Hide(), "On")
    Hotkey("~RButton", (*) => LegendaGui.Hide(), "On")

    HotIf((*) => LegendaIstnieje() && DllCall("IsWindowVisible", "Ptr", LegendaGui.Hwnd) && WinGetMinMax("ahk_id " LegendaGui.hwnd) != -1)
    Hotkey("F1", (*) => (PokazUstawienia(), LegendaGui.Hide()), "On")

    ; --- MYSZ Custom ---
    HotIf((*) => (CurrentProfile == 1 || (CurrentProfile == 0 && CustomActive)))
    Hotkey("*RButton", (*) => AkcjaRButton(), "On")
    Hotkey("XButton1", myCustomXButton1, "On")
    Hotkey("XButton2", myCustomXButton2, "On")
    Hotkey("~XButton2 & LButton", myCustomX2LButton, "On")
    Hotkey("~XButton2 & RButton", myCustomX2RButton, "On")
    Hotkey("XButton2 & XButton1", myCustomX2X1, "On")
    Hotkey("~RButton & XButton1", (*) => (myAltTabState.Active := true, Send("{Blind}{Alt down}{Tab}")), "On")
    Hotkey("~RButton & XButton2", (*) => (myAltTabState.Active := true, Send("{Blind}{Alt down}{Shift down}{Tab}{Shift up}")), "On")
    Hotkey("*RButton Up", (*) => (myAltTabState.Active ? (Send("{Alt up}"), myAltTabState.Active := false) : ""), "On")

    ; --- MYSZ STANDARDOWA ---
    HotIf((*) => (CurrentProfile == 2 || (CurrentProfile == 0 && !CustomActive)))
    Hotkey("RButton", (*) => AkcjaRButton(), "On")
    
    HotIf((*) => (CurrentProfile == 2 || (CurrentProfile == 0 && !CustomActive)) && !CzyNadZablokowanymElementem() && !myStandardProxyActive)
    Hotkey("~LButton & WheelUp", (*) => (UsunTip(), ZmianaJasnosci(BrightnessStepMouse)), "On")
    Hotkey("~LButton & WheelDown", (*) => (UsunTip(), ZmianaJasnosci(-BrightnessStepMouse)), "On")
    Hotkey("~LButton & MButton", (*) => (UsunTip(), WygasEkran("LButton")), "On")
    Hotkey("~LButton & RButton", (*) => (myAltTabState.Active := true, Send("{Blind}{Alt down}{Tab}")), "On")
    Hotkey("~LButton Up", (*) => (myAltTabState.Active ? (Send("{Alt up}"), myAltTabState.Active := false) : ""), "On")
    Hotkey("~LButton", (*) => LButtonStandardTip(), "On")

    ; --- KLAWIATURA ---
    HotIf((*) => CurrentProfile != 4)
    Hotkey("^!p", (*) => (SilnikGUI.CustomTooltip("Screenshot 📸", {Transparent: 0.2,trybPozycji:"Screen",Align:"Up+20",rozmiarCzcionki: 25,DelayON:50,czas: 1500}), Send("{PrintScreen}")), "On")
    Hotkey("^F1", (*) => ZmianaJasnosci(-BrightnessStepKbd), "On")
    Hotkey("^F2", (*) => ZmianaJasnosci(BrightnessStepKbd), "On")
    Hotkey("+" . Chr(96), (*) => SendText("~"), "On") ; Shift + `

    ; --- GŁÓWNE ---
    HotIf()
    Hotkey("^!r", (*) => AwaryjneOdblokowanie(), "On")
    Hotkey("^F12", myToggleProfile, "On")

    ; --- KILL-TIP ---
    HotIf((*) => TipIstnieje() && !LegendaIstnieje() && !GetKeyState("XButton2", "P") && !myStandardProxyActive)
    Hotkey("~LButton", myKillTipLButton, "On")
    Hotkey("~MButton", (*) => (UsunTip()), "On")
    Hotkey("~RButton", (*) => (UsunTip()), "On")
    Hotkey("~Esc", (*) => UsunTip(), "On")

    ; --- USTAWIENIA ---
    HotIf((*) => UstawieniaIstnieje() && WinGetMinMax("ahk_id " GlUs.GuiObj.Hwnd) != -1 && WinActive("ahk_id " GlUs.GuiObj.Hwnd))
    Hotkey("RButton & WheelDown", (*) => Send("{shift up}{Tab}"), "On")
    Hotkey("RButton & WheelUp", (*) => Send("+{Tab}"), "On")

    HotIf() ; Reset
}

; --- WYDZIELONE HANDLERY LATE BINDING ---
myLegendaWheelDown(*) {
    if (CurrentProfile != 4) {
        UstawProfil((CurrentProfile+1), true)      
        AktualizujTooltipWLocie() 
    }
}

myLegendaWheelUp(*) {
    if (CurrentProfile != 0) {
        UstawProfil((CurrentProfile-1), true)
        AktualizujTooltipWLocie() 
    }
}

myLegendaLButton(*) {
    LButtonStandardTip()
    if !LegendaIstnieje()
        return
    try {
        if SendMessage(0x0157, 0, 0, , "ahk_id " . GuiControls.DDL.Hwnd)
            return
    }
    MouseGetPos(,, &idPodMysza, &hCtrl, 2)
    try klasaOkna := WinGetClass("ahk_id " idPodMysza)
    catch 
        klasaOkna := ""

    if (klasaOkna == "ComboLBox")
        return

    if (idPodMysza == LegendaGui.Hwnd) {
        if (hCtrl == GuiControls.DDL.Hwnd || hCtrl == GuiControls.BtnSettings.Hwnd)
            return
        LegendaGui.Hide()
    } else {
        LegendaGui.Hide()
    }
}
arrowFocusNav(button:="XButton1") => (SilnikGUI.CustomTooltip("SCROLL  🡱 🡳   ➠  ARROWS  🡰 🡲", {ON: (!EkranWygaszony && PokazPodpowiedzi), DelayON: 100}), UstawFocusPodMysz(), MouseCtrlLib.AktywujTrybKola((*) => SendEvent("{Left}"), (*) => SendEvent("{Right}"), 0, 0, () => SilnikGUI.CustomTooltip(""), button), SilnikGUI.CustomTooltip(""))

global myStandardProxyActive := false
global myAltTabState := { Active: false }

/** Proxies standard mouse scroll mode to toggle between arrows and horizontal scroll 
 * @param button */
myStandardScrollMode(button := "RButton", togle := "*LButton") {
    global myStandardProxyActive
    myState := { HScroll: false }
    
    myUpdateTooltip() => SilnikGUI.CustomTooltip(myState.HScroll ? "SCROLL  🡱 🡳   ➠   H-SCROLL  🞀 ❘❙❚❙❘ 🞂`n.[2].`nLCLICK  ➠  TOGGLE" : "SCROLL  🡱 🡳   ➠   ARROWS  🡰 🡲`n.[2].`nLCLICK  ➠  TOGGLE", {ON: (!EkranWygaszony && PokazPodpowiedzi), DelayON: 100})
    
    myToggleState(*) {
        myState.HScroll := !myState.HScroll
        myUpdateTooltip()
    }
    
    myOnStart() {
        myStandardProxyActive := true
        UstawFocusPodMysz()
        myUpdateTooltip()
        try Hotkey(togle, myToggleState, "On")
    }
    
    myOnStop() {
        try Hotkey(togle, "Off")
        myStandardProxyActive := false
        SilnikGUI.CustomTooltip("")
    }
    
    myWheelUp(*) => myState.HScroll ? (SendLevel(1), SendEvent("{WheelLeft}")) : SendEvent("{Left}")
    myWheelDown(*) => myState.HScroll ? (SendLevel(1), SendEvent("{WheelRight}")) : SendEvent("{Right}")
    
    MouseCtrlLib.AktywujTrybKola(myWheelUp, myWheelDown, myOnStart, myOnStop, () => SilnikGUI.CustomTooltip(""), button)
}

myCustomXButton1(*) {
    Multiklik("XButton1", 
        (*) => Send("{XButton1}"),
        (*) => (!PokazPodpowiedzi ? (SilnikGUI.CustomTooltip("Brightness: " . currentBrightness . "%  ◑", {ON: !EkranWygaszony, czas: 1500})) : (SilnikGUI.CustomTooltip("SCROLL  ➠  BRIGHTNESS  ◑`n..`nMIDDLE  ➠  SCREEN OFF  💻`n.[2].`n(x2)  ➠  ESC  🡰`n..`n(2xHOLD)+SCROLL  🡱 🡳  ➠  ARROWS  🡰 🡲`n.[2].`nBrightness: " . currentBrightness . "%  ◑", {ON: !EkranWygaszony, MargPoz: 4})), MouseCtrlLib.AktywujTrybKola((*) => ZmianaJasnosci(BrightnessStepMouse), (*) => ZmianaJasnosci(-BrightnessStepMouse),(*) => Hotkey("*RButton", (*) => (UsunTip(), WygasEkran("XButton1")), "On"), (*) => Hotkey("*RButton", (*) => AkcjaRButton(), "On"), 0, "XButton1"), SilnikGUI.CustomTooltip("")),
        (*) => SendEvent("{Escape}"),
        (*) => arrowFocusNav(),
        HoldThreshold
    )
}

myCustomXButton2(*) {
    Multiklik("XButton2",
        (*) => Send("{XButton2}"),
            (*) => (SilnikGUI.CustomTooltip("CTRL  ✲`n..`nSCROLL  🡱 🡳  ➠  ZOOM   ( + ) 🔍 ( - )`n.[4].`n- L E F T -`n.[3].`n(x2) ➠  CTRL+V  📄`n..`n(2xHOLD)  ➠  CTRL+V+LEFT  📄🡳`n.[4].`n- R I G H T -`n.[3].`n(x1)  ➠  CTRL+C  📄📄`n..`n(HOLD)  ➠  CTRL+X  ✂`n..`n(x2)  ➠  CTRL+C+LEFT   📄📄🡳`n..`n(2xHOLD)  ➠  CTRL+X+LEFT  ✂🡳`n.[4].`nX1+SCROLL  🡱 🡳  ➠  CTRL+Z/Y  🡷 🡵`n.[3].`n(x2)  ➠  CTRL+SHIFT+S  ✍`n..`n(2xHOLD)+SCROLL  🡱 🡳  ➠  SCROLL  🞀 ❘❙❚❙❘ 🞂", {ON: (!EkranWygaszony && PokazPodpowiedzi), MargPoz: 2}), MouseCtrlLib.AktywujTrybKola((*) => Send("{WheelUp}"), (*) => Send("{WheelDown}"), (*) => Send("{Ctrl Down}"), (*) => Send("{Ctrl Up}"), () => SilnikGUI.CustomTooltip(""), "XButton2"), SilnikGUI.CustomTooltip("")),
        (*) => SendEvent("^a"),
            (*) => (SilnikGUI.CustomTooltip("SCROLL  🡱 🡳  ➠  SCROLL  🞀 ❘❙❚❙❘ 🞂", {ON: (!EkranWygaszony && PokazPodpowiedzi)}), MouseCtrlLib.AktywujTrybKola((*) => (SendLevel(1), SendEvent("{WheelLeft}")), (*) => (SendLevel(1), SendEvent("{WheelRight}")), 0, 0, () => SilnikGUI.CustomTooltip(""), "XButton2"), SilnikGUI.CustomTooltip("")),
        HoldThreshold
    )
}

myCustomX2LButton(*) {
    Multiklik("LButton",
    (*) => (SilnikGUI.CustomTooltip(""), Click("Left")),
    (*) => (SilnikGUI.CustomTooltip(""), Send("{Blind}{LButton Down}"), KeyWait("LButton"), Send("{Blind}{LButton Up}")),
    (*) => (SilnikGUI.CustomTooltip(""), Send("^v")),
    (*) => (SilnikGUI.CustomTooltip(""), (Click("Left"), Send("^v"))),
    HoldThreshold)
}

myCustomX2RButton(*) {
    Multiklik("RButton", 
    (*) => (SilnikGUI.CustomTooltip(""), Send("^c")), 
    (*) => (SilnikGUI.CustomTooltip(""), Send("^x")), 
    (*) => (SilnikGUI.CustomTooltip(""), (Send("{Ctrl Up}"), Click("Left"), Send("^c"))), 
    (*) => (SilnikGUI.CustomTooltip(""), (Send("{Ctrl Up}"), Click("Left"), Send("^x"))), 
    HoldThreshold)
}

myCustomX2X1(*) {
    SilnikGUI.CustomTooltip("SCROLL  🡱 🡳  ➠  CTRL+Z/Y  🡷 🡵", {ON: (!EkranWygaszony && PokazPodpowiedzi)})
    MouseCtrlLib.AktywujTrybKola((*) => Send("^z"), (*) => Send("^y"), 0, 0, () => SilnikGUI.CustomTooltip(""), "xbutton2")
}

myToggleProfile(*) {
    if CurrentProfile < 3 {
        UstawProfil(CurrentProfile+1, true)   
        AktualizujTooltipWLocie() 
    } else if (CurrentProfile = 3) {
        UstawProfil(0, true)
        AktualizujTooltipWLocie()
    }
}

myKillTipLButton(*) {
    UsunTip()
    LButtonStandardTip(HoldThreshold*1000-100)
}
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region Funkcje Pomocnicze - główne skróty
LButtonStandardTip(czasUspienia := HoldThreshold*1000) {
    if !(CurrentProfile = 2 or (CurrentProfile = 0 and !CustomActive))
        return

    (!PokazPodpowiedzi) ? (SilnikGUI.CustomTooltip("Brightness: " . currentBrightness . "%  ◑", {DelayON: czasUspienia, ON: !EkranWygaszony, czas: 1500})) : SilnikGUI.CustomTooltip("SCROLL  ➠  BRIGHTNESS  ◑`n.[1].`nMIDDLE  ➠  SCREEN OFF  💻`n.[1].`nRIGHT  ➠  ALT+TAB`n.[2].`nBrightness: " . currentBrightness . "%  ◑", {DelayON : czasUspienia, ON: !EkranWygaszony})
    KeyWait("LButton")
    SilnikGUI.CustomTooltip()
}

CzyNadZablokowanymElementem() {
    MouseGetPos(,,, &hCtrl, 2)
    ; Sprawdź globalne tagi WinAPI (działają między procesami)
    return (hCtrl && (Utils.GetTag(hCtrl, "IsSilnikScrollbarBtn") || Utils.GetTag(hCtrl, "IsSilnikScrollbarThumb") || Utils.GetTag(hCtrl, "IsSilnikScrollbarTrack")))
}

; Funkcja pomocnicza dla AkcjaRButton, wywoływana przy przytrzymaniu
_AkcjaRButton_Hold() {
    PokazDymek := () => !PokazPodpowiedzi ? (SilnikGUI.CustomTooltip(PobierzStatusAudio(), {ON: !EkranWygaszony, czas: 1500})) : SilnikGUI.CustomTooltip("SHIFT  🡱`n..`n" . ((CurrentProfile = 1 or (CurrentProfile = 0 and CustomActive))? "X1  ➠  Alt+Tab`nX2  ➠  Shift+Alt+Tab`n..`n" : "LEFT  ➠  Alt+Tab`n..`n(2xHOLD)+SCROLL  🡱 🡳  ➠  ARROWS / H-SCROLL`n..`n") . "2X  ➠  f11`n..`nSCROLL  🡱 🡳  ➠  VOLUME(+/-)`nMIDDLE  ➠  MUTE  🔉X`n.[2].`n" . PobierzStatusAudio(), {ON: !EkranWygaszony}) 
    CzyscDymek := (*) => SilnikGUI.CustomTooltip()

    ; Timer dymka
    SetTimer(PokazDymek, -Round(HoldThreshold * 1000))

    ; LButton czyści dymek
    try Hotkey("~*LButton", CzyscDymek, "On")
    try Hotkey("*MButton", (*) => PrzelaczWyciszenie(), "On")

    MouseCtrlLib.AktywujTrybKola(
        (*) => (SetTimer(PokazDymek, 0), ZmianaGlosnosci(VolStepMouse)), 
        (*) => (SetTimer(PokazDymek, 0), ZmianaGlosnosci(-VolStepMouse)), 
        (*) => Send("{LShift Down}"), 
        (*) => Send("{LShift Up}"),
        (*) => "", 
        "RButton"
    )

    ; Sprzątanie
    try Hotkey("~*LButton", "Off")
    try Hotkey("*MButton", "Off")
    SetTimer(PokazDymek, 0)
    CzyscDymek()
}

AkcjaRButton() {
    Multiklik("RButton", 
        (*) => (SendInput("{RButton Down}"), SendInput("{RButton Up}")),
        _AkcjaRButton_Hold,
        (*) =>(UstawFocusPodMysz(), SendEvent("{F11}")), 
        (*) => ((CurrentProfile = 2 or (CurrentProfile = 0 and !CustomActive)) ? myStandardScrollMode("RButton") : ""), HoldThreshold, 5
    )
}

; Focus pod myszą (dla XButton1)
UstawFocusPodMysz() {
    try UIA.ElementFromPoint().SetFocus()
}

; Awaryjny zrzut zablokowanych klawiszy logicznych
AwaryjneOdblokowanie() {
    klawisze := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift"]
    sekwencja := ""
    for k in klawisze
        if GetKeyState(k)
            sekwencja .= "{" k " Up}"
    if (sekwencja != "")
        Send("{Blind}" sekwencja)
    SilnikGUI.CustomTooltip("KEYS`nUNLOCKED", {Transparent: 0.2, trybPozycji:"Screen",Align:"UP+20",czas: 2000,rozmiarCzcionki: 25})
}

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
