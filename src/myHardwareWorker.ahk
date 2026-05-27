#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Ignore
ProcessSetPriority "High"
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
global QueueTime        := -1

OnExit(myGracefulShutdown)

/** Gracefully cancels WMI subscriptions before exit 
 * @param ExitReason 
 * @param ExitCode */
myGracefulShutdown(ExitReason, ExitCode) {
    global myWmiSink
    try myWmiSink.Cancel()
}

; #region --- WMI EVENT SINK (Async Brightness Monitor) ---
global myWmiSink := ComObject("WbemScripting.SWbemSink")
ComObjConnect(myWmiSink, "myWmiSink_")
try ComObjGet(myWmiNamespace).ExecNotificationQueryAsync(myWmiSink, "SELECT * FROM __InstanceModificationEvent WITHIN 1 WHERE TargetInstance ISA 'WmiMonitorBrightness'")
; #endregion

/** Handles async WMI events for brightness changes 
 * @param objWbemObject 
 * @param args */
myWmiSink_OnObjectReady(objWbemObject, args*) {
    global myAppliedBrightness
    try {
        myNewBrightness := objWbemObject.TargetInstance.CurrentBrightness
        if (myNewBrightness != myAppliedBrightness) {
            myAppliedBrightness := myNewBrightness
            myDispatchIpcEvent(-1, myNewBrightness, "-1")
        }
    }
}

global myPendingBrightness := 0
global myWmiBusy := false
global myAppliedBrightness := -1
OnMessage(myIpcMsgId, myHandleRequest)

global myMouseBusy := false
global myPendingMouseCheck := 0
global myAudioBusy := false
global myPendingAudioCheck := 0
OnMessage(0x219, myOnDeviceChange)

/** Dispatches IPC payload to main script
 * @param genesisState -1: skip, 0/1: state
 * @param brightnessVal -1: skip, 1-100: val
 * @param audioState "-1": skip, string: val */
myDispatchIpcEvent(genesisState, brightnessVal, audioState := "-1") {
    global myMainHwnd, myIpcSignature, myIpcSeparator, WM_COPYDATA
    
    myPayload := genesisState . myIpcSeparator . brightnessVal . myIpcSeparator . audioState
    myStrBuf := Buffer(StrPut(myPayload, "UTF-16") * 2, 0)
    StrPut(myPayload, myStrBuf, "UTF-16")

    myCopyData := Buffer(A_PtrSize * 3, 0)
    NumPut("UPtr", myIpcSignature, myCopyData, 0)
    NumPut("UInt", myStrBuf.Size, myCopyData, A_PtrSize)
    NumPut("UPtr", myStrBuf.Ptr, myCopyData, A_PtrSize * 2)

    SendMessage(WM_COPYDATA, 0, myCopyData.Ptr,, Integer(myMainHwnd))
}

/** Applies brightness and recurses if new target was buffered during WMI lag */
myProcessBrightnessQueue() {
    global myPendingBrightness, myWmiNamespace, myWmiBusy, myAppliedBrightness
    myCurrentTarget := myPendingBrightness
    try {
        for method in ComObjGet(myWmiNamespace).ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
            method.WmiSetBrightness(0, myCurrentTarget)
        myAppliedBrightness := myCurrentTarget
    }
    
    if (myPendingBrightness != myAppliedBrightness)
        SetTimer(myProcessBrightnessQueue, -1)
    else
        myWmiBusy := false
}

/** WMI query for Genesis Mouse */
myCheckGenesisState() {
    global myTargetMouseID
    try {
        return ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery("SELECT * FROM Win32_PnPEntity WHERE DeviceID LIKE '%" . StrReplace(myTargetMouseID, "\", "\\") . "%' AND Status='OK'").Count > 0
    } catch as err {
        OutputDebug("WMI Mouse Query Error: " . err.Message)
        return -1
    }
}

/** Broadcast receiver for USB/PnP changes with L7 routing */
myOnDeviceChange(wParam, lParam, msg, hwnd) {
    global myPendingMouseCheck, myMouseBusy, myPendingAudioCheck, myAudioBusy, QueueTime

    if (!lParam) {
        myPendingMouseCheck++
        if (!myMouseBusy) {
            myMouseBusy := true
            SetTimer(myProcessMouseQueue, QueueTime)
        }
        myPendingAudioCheck++
        if (!myAudioBusy) {
            myAudioBusy := true
            SetTimer(myProcessAudioQueue, QueueTime)
        }
        return
    }

    myDeviceType := NumGet(lParam, 4, "UInt")
    if (myDeviceType == 5) {
        myDevString := StrGet(lParam + 28, "UTF-16")
        
        if (myDevString ~= "i)(HID|USB)") {
            myPendingMouseCheck++
            if (!myMouseBusy) {
                myMouseBusy := true
                SetTimer(myProcessMouseQueue, QueueTime)
            }
        }
        
        if (myDevString ~= "i)(AUDIO|MMDEVAPI|RENDER)") {
            myPendingAudioCheck++
            if (!myAudioBusy) {
                myAudioBusy := true
                SetTimer(myProcessAudioQueue, QueueTime)
            }
        }
    }
}

/** Processes mouse state sync and recurses if event storm occurs */
myProcessMouseQueue() {
    global myPendingMouseCheck, myMouseBusy
    myCurrentCheck := myPendingMouseCheck
    
    myGenesisActive := myCheckGenesisState()
    
    if (myPendingMouseCheck != myCurrentCheck)
        SetTimer(myProcessMouseQueue, QueueTime)
    else {
        myMouseBusy := false
        myDispatchIpcEvent(myGenesisActive, -1, "-1")
    }
}

/** Processes audio state sync and recurses if event storm occurs */
myProcessAudioQueue() {
    global myPendingAudioCheck, myAudioBusy
    myCurrentCheck := myPendingAudioCheck
    
    myAudio := AudioMonitor.Update()
    
    if (myPendingAudioCheck != myCurrentCheck)
        SetTimer(myProcessAudioQueue, QueueTime)
    else {
        myAudioBusy := false
        myDispatchIpcEvent(-1, -1, myAudio)
    }
}

myHandleRequest(wParam, lParam, msg, hwnd) {
    global myTargetMouseID, myWmiNamespace, myPendingBrightness, myWmiBusy
    
    if (wParam == 4)
        ExitApp()
        
    /** 0. Throttle Brightness Update */
    if (wParam == 5) {
        myPendingBrightness := lParam
        if (!myWmiBusy) {
            myWmiBusy := true
            SetTimer(myProcessBrightnessQueue, -1)
        }
        return 1
    }

    /** 1. Fetch mouse state via WMI */
    myGenesisActive := -1
    if (wParam & 1)
        myGenesisActive := myCheckGenesisState()

    /** 2. Fetch screen brightness via WMI */
    myBrightness := -1
    if (wParam & 2) {
        try for monitor in ComObjGet(myWmiNamespace).ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
            myBrightness := monitor.CurrentBrightness
    }

    /** 3. Fetch Audio status via COM */
    myAudio := "-1"
    if (wParam & 4)
        myAudio := AudioMonitor.Update()

    /** 4. Dispatch data */
    myDispatchIpcEvent(myGenesisActive, myBrightness, myAudio)
    return 1
}

class AudioMonitor {
    static myEnumerator := 0
    static PKEY_FormFactor := Buffer(20, 0)
    static PKEY_DevEnum := Buffer(20, 0)
    static PKEY_DevId := Buffer(20, 0)

    static __New() {
        DllCall("Ole32\CLSIDFromString", "Str", "{1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E}", "Ptr", this.PKEY_FormFactor)
        NumPut("UInt", 0, this.PKEY_FormFactor, 16)
        DllCall("Ole32\CLSIDFromString", "Str", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "Ptr", this.PKEY_DevEnum)
        NumPut("UInt", 24, this.PKEY_DevEnum, 16)
        DllCall("Ole32\CLSIDFromString", "Str", "{78C34FC8-E0AF-4E42-AAEC-27220C63243C}", "Ptr", this.PKEY_DevId)
        NumPut("UInt", 256, this.PKEY_DevId, 16)
    }
    
    static Update() {
        try {
            if (!this.myEnumerator)
                this.myEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
                
            ComCall(4, this.myEnumerator, "Int", 0, "Int", 1, "Ptr*", &device := 0)
            if !device
                return "-1"
            
            ComCall(4, device, "Int", 0, "Ptr*", &storePtr := 0)
            ObjRelease(device)
            if !storePtr
                return "-1"
            
            store := ComValue(13, storePtr)
            formFactor := this.GetProp(store, this.PKEY_FormFactor)
            devEnum := this.GetProp(store, this.PKEY_DevEnum)
            devId := this.GetProp(store, this.PKEY_DevId)
            
            fullInfo := devEnum . " " . devId . " " . SoundGetName()
            iconConn := "💻 : " 
            if (fullInfo ~= "i)(USB|UAC)")
                iconConn := "ψ : "
            else if (fullInfo ~= "i)(Blue|BT|BTH)")
                iconConn := "ᛒ : "
            else if (fullInfo ~= "i)(HDAUDIO|PCI|Realtek|High Def)")
                iconConn := (formFactor == 3 || formFactor == 5) ? "Jack ⊙ : " : "💻 : "
            
            iconForm := (formFactor == 3) ? "🎧/🔊" : ((formFactor == 5) ? "📞" : "🔊")
            return iconConn . " " . iconForm . "   "
            
        } catch as err {
            OutputDebug("AudioMonitor COM Error: " . err.Message)
            return "🔊?   "
        }
    }

    static GetProp(store, pk) {
        val := Buffer(24, 0)
        try ComCall(5, store, "Ptr", pk, "Ptr", val)
        catch as err {
            OutputDebug("AudioMonitor GetProp Error: " . err.Message)
            return ""
        }
            
        vt := NumGet(val, 0, "UShort")
        res := ""
        if (vt == 19)
            res := NumGet(val, 8, "UInt")
        else if (vt == 31)
            res := StrGet(NumGet(val, 8, "Ptr"))
        
        DllCall("Ole32\PropVariantClear", "Ptr", val)
        return res
    }
}