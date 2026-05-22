#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Force

DetectHiddenWindows true

if (A_Args.Length < 2)
    ExitApp()

myMainHwnd := A_Args[1]
myTargetMouseID := A_Args[2]

/** 1. Fetch mouse state via WMI */
myGenesisActive := 0
try myGenesisActive := ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery("SELECT * FROM Win32_PnPEntity WHERE DeviceID LIKE '%" . StrReplace(myTargetMouseID, "\", "\\") . "%' AND Status='OK'").Count > 0

/** 2. Fetch screen brightness via WMI */
myBrightness := 10
try for monitor in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
    myBrightness := monitor.CurrentBrightness

/** 3. Pack payload and send via WM_COPYDATA */
myPayload := myGenesisActive . "|" . myBrightness
myStrBuf := Buffer(StrPut(myPayload, "UTF-16"), 0)
StrPut(myPayload, myStrBuf, "UTF-16")

myCopyData := Buffer(A_PtrSize * 3, 0)
NumPut("UPtr", 0x5555, myCopyData, 0)
NumPut("UInt", myStrBuf.Size, myCopyData, A_PtrSize)
NumPut("UPtr", myStrBuf.Ptr, myCopyData, A_PtrSize * 2)

SendMessage(0x004A, 0, myCopyData.Ptr,, "ahk_id " . myMainHwnd)
ExitApp()