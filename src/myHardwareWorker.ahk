#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Force

DetectHiddenWindows true

if (A_Args.Length < 2)
    ExitApp()

myMainHwnd := A_Args[1]
myTargetMouseID := A_Args[2]
myIniPath := A_ScriptDir . "\myHardwareState.ini"

/** 1. Fetch mouse state via WMI */
myGenesisActive := 0
try myGenesisActive := ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery("SELECT * FROM Win32_PnPEntity WHERE DeviceID LIKE '%" . StrReplace(myTargetMouseID, "\", "\\") . "%' AND Status='OK'").Count > 0

/** 2. Fetch screen brightness via WMI */
myBrightness := 10
try for monitor in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
    myBrightness := monitor.CurrentBrightness

/** 3. Save to temp cache and notify main process (IPC) */
IniWrite(myGenesisActive, myIniPath, "State", "GenesisActive")
IniWrite(myBrightness, myIniPath, "State", "Brightness")
PostMessage(0x5555, 0, 0,, "ahk_id " . myMainHwnd)
ExitApp()