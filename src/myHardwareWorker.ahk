#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Ignore
Persistent(true)

DetectHiddenWindows true

if (A_Args.Length < 6)
    ExitApp()

global myMainHwnd       := A_Args[1]
global myTargetMouseID  := A_Args[2]
global myIpcMsgId       := Integer(A_Args[3])
global myIpcSignature   := Integer(A_Args[4])
global myIpcSeparator   := A_Args[5]
global myWmiNamespace   := A_Args[6]
global WM_COPYDATA      := 0x004A

; #region --- WMI EVENT SINK (Async Brightness Monitor) ---
global myWmiSink := ComObject("WbemScripting.SWbemSink")
ComObjConnect(myWmiSink, "myWmiSink_")
try ComObjGet(myWmiNamespace).ExecNotificationQueryAsync(myWmiSink, "SELECT * FROM __InstanceModificationEvent WITHIN 1 WHERE TargetInstance ISA 'WmiMonitorBrightness'")
; #endregion

OnMessage(myIpcMsgId, myHandleRequest)

/** WMI Event callback */
myWmiSink_OnObjectReady(objWbemObject, *) {
    try myDispatchIpcEvent(-1, objWbemObject.TargetInstance.CurrentBrightness)
}

/** Dispatches IPC payload to main script
 * @param genesisState -1: skip, 0/1: state
 * @param brightnessVal -1: skip, 1-100: val */
myDispatchIpcEvent(genesisState, brightnessVal) {
    global myMainHwnd, myIpcSignature, myIpcSeparator, WM_COPYDATA
    
    myPayload := genesisState . myIpcSeparator . brightnessVal
    myStrBuf := Buffer(StrPut(myPayload, "UTF-16"), 0)
    StrPut(myPayload, myStrBuf, "UTF-16")

    myCopyData := Buffer(A_PtrSize * 3, 0)
    NumPut("UPtr", myIpcSignature, myCopyData, 0)
    NumPut("UInt", myStrBuf.Size, myCopyData, A_PtrSize)
    NumPut("UPtr", myStrBuf.Ptr, myCopyData, A_PtrSize * 2)

    SendMessage(WM_COPYDATA, 0, myCopyData.Ptr,, Integer(myMainHwnd))
}

myHandleRequest(wParam, lParam, msg, hwnd) {
    global myTargetMouseID, myWmiNamespace
    
    if (wParam == 4)
        ExitApp()
        
    /** 1. Fetch mouse state via WMI */
    myGenesisActive := -1
    if (wParam & 1) {
        try myGenesisActive := ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery("SELECT * FROM Win32_PnPEntity WHERE DeviceID LIKE '%" . StrReplace(myTargetMouseID, "\", "\\") . "%' AND Status='OK'").Count > 0
    }

    /** 2. Fetch screen brightness via WMI */
    myBrightness := -1
    if (wParam & 2) {
        try for monitor in ComObjGet(myWmiNamespace).ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
            myBrightness := monitor.CurrentBrightness
    }

    /** 3. Dispatch data */
    myDispatchIpcEvent(myGenesisActive, myBrightness)
    return 1
}