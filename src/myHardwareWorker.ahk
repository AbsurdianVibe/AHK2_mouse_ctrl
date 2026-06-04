class HardwareDaemon {
    static Boot(args) {
        DetectHiddenWindows(true)
        WinSetTitle("MouseCtrl_Daemon_Window", "ahk_id " A_ScriptHwnd)
        
        if (args.Length < 7)
            ExitApp()
            
        this.myMainHwnd       := args[2]
        this.myTargetMouseID  := args[3]
        this.myIpcMsgId       := Integer(args[4])
        this.myIpcSignature   := Integer(args[5])
        this.myIpcSeparator   := args[6]
        this.myWmiNamespace   := args[7]
        this.WM_COPYDATA      := 0x004A
        this.QueueTime        := -1

        this.myWmiInitialized := false
        this.myPendingBrightness := 0
        this.myWmiBusy := false
        this.myAppliedBrightness := -1
        this.myAudioBusy := false
        this.myPendingAudioCheck := 0
        
        try SetTimer(ObjBindMethod(SilnikGUI, "GłównaPętlaStanu"), 0) ; Disable UI loop in headless daemon

        OnExit(ObjBindMethod(this, "GracefulShutdown"))

        OnMessage(this.myIpcMsgId, ObjBindMethod(this, "HandleRequest"))
        this.RegisterRawInput()
        OnMessage(0x00FE, ObjBindMethod(this, "OnInputDeviceChange"))
        OnMessage(0x219, ObjBindMethod(this, "OnDeviceChange"))
        
        Persistent(true)
    }

    static GracefulShutdown(ExitReason, ExitCode) {
        if (this.HasOwnProp("myWmiSink") && this.myWmiSink)
            try this.myWmiSink.Cancel()
    }

    static InitWmiAsync() {
        if (this.myWmiInitialized)
            return
        try {
            this.myWmiSink := ComObject("WbemScripting.SWbemSink")
            ComObjConnect(this.myWmiSink, this)
            ComObjGet(this.myWmiNamespace).ExecNotificationQueryAsync(this.myWmiSink, "SELECT * FROM __InstanceModificationEvent WITHIN 1 WHERE TargetInstance ISA 'WmiMonitorBrightness'")
            this.myWmiInitialized := true
        }
    }

    static OnObjectReady(objWbemObject, args*) {
        try {
            myNewBrightness := objWbemObject.TargetInstance.CurrentBrightness
            if (myNewBrightness != this.myAppliedBrightness) {
                this.myAppliedBrightness := myNewBrightness
                this.DispatchIpcEvent(-1, myNewBrightness, "-1")
            }
        }
    }

    static RegisterRawInput() {
        myRid := Buffer(8 + A_PtrSize, 0)
        NumPut("UShort", 1, myRid, 0)
        NumPut("UShort", 2, myRid, 2)
        NumPut("UInt", 0x00002000, myRid, 4) ; RIDEV_DEVNOTIFY
        NumPut("Ptr", A_ScriptHwnd, myRid, 8)
        DllCall("User32\RegisterRawInputDevices", "Ptr", myRid, "UInt", 1, "UInt", myRid.Size)
    }

    static DispatchIpcEvent(CustomState, brightnessVal, audioState := "-1") {
        myPayload := CustomState . this.myIpcSeparator . brightnessVal . this.myIpcSeparator . audioState
        myStrBuf := Buffer(StrPut(myPayload, "UTF-16") * 2, 0)
        StrPut(myPayload, myStrBuf, "UTF-16")

        myCopyData := Buffer(A_PtrSize * 3, 0)
        NumPut("UPtr", this.myIpcSignature, myCopyData, 0)
        NumPut("UInt", myStrBuf.Size, myCopyData, A_PtrSize)
        NumPut("UPtr", myStrBuf.Ptr, myCopyData, A_PtrSize * 2)

        SendMessage(this.WM_COPYDATA, 0, myCopyData.Ptr,, Integer(this.myMainHwnd))
    }

    static ProcessBrightnessQueue() {
        myCurrentTarget := this.myPendingBrightness
        try {
            for method in ComObjGet(this.myWmiNamespace).ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
                method.WmiSetBrightness(0, myCurrentTarget)
            this.myAppliedBrightness := myCurrentTarget
        }
        
        if (this.myPendingBrightness != this.myAppliedBrightness)
            SetTimer(ObjBindMethod(this, "ProcessBrightnessQueue"), -1)
        else
            this.myWmiBusy := false
    }

    static CheckCustomState() {
        myNumDevices := 0
        DllCall("User32\GetRawInputDeviceList", "Ptr", 0, "UInt*", &myNumDevices, "UInt", A_PtrSize * 2)
        if (!myNumDevices)
            return 0
            
        myRawInputDeviceList := Buffer(myNumDevices * (A_PtrSize * 2), 0)
        DllCall("User32\GetRawInputDeviceList", "Ptr", myRawInputDeviceList, "UInt*", &myNumDevices, "UInt", A_PtrSize * 2)
        
        Loop myNumDevices {
            myHandle := NumGet(myRawInputDeviceList, (A_Index - 1) * (A_PtrSize * 2), "Ptr")
                
            myNameLength := 0
            DllCall("User32\GetRawInputDeviceInfo", "Ptr", myHandle, "UInt", 0x20000007, "Ptr", 0, "UInt*", &myNameLength)
            
            if (myNameLength > 0) {
                myNameBuffer := Buffer(myNameLength * 2, 0)
                DllCall("User32\GetRawInputDeviceInfo", "Ptr", myHandle, "UInt", 0x20000007, "Ptr", myNameBuffer, "UInt*", &myNameLength)
                
                if InStr(StrReplace(StrGet(myNameBuffer), "#", "\"), this.myTargetMouseID)
                    return 1
            }
        }
        return 0
    }

    static OnInputDeviceChange(wParam, lParam, msg, hwnd) {
        if (wParam == 1 || wParam == 2)
            SetTimer(ObjBindMethod(this, "ProcessMouseState"), -50)
    }

    static ProcessMouseState() {
        this.DispatchIpcEvent(this.CheckCustomState(), -1, "-1")
    }

    static OnDeviceChange(wParam, lParam, msg, hwnd) {
        if (!lParam) {
            this.myPendingAudioCheck++
            if (!this.myAudioBusy) {
                this.myAudioBusy := true
                SetTimer(ObjBindMethod(this, "ProcessAudioQueue"), this.QueueTime)
            }
            return
        }

        if (NumGet(lParam, 4, "UInt") == 5) {
            if (StrGet(lParam + 28, "UTF-16") ~= "i)(AUDIO|MMDEVAPI|RENDER)") {
                this.myPendingAudioCheck++
                if (!this.myAudioBusy) {
                    this.myAudioBusy := true
                    SetTimer(ObjBindMethod(this, "ProcessAudioQueue"), this.QueueTime)
                }
            }
        }
    }

    static ProcessAudioQueue() {
        myCurrentCheck := this.myPendingAudioCheck
        
        myAudio := HardwareDaemon.AudioMonitor.Update()
        
        if (this.myPendingAudioCheck != myCurrentCheck)
            SetTimer(ObjBindMethod(this, "ProcessAudioQueue"), this.QueueTime)
        else {
            this.myAudioBusy := false
            this.DispatchIpcEvent(-1, -1, myAudio)
        }
    }

    static HandleRequest(wParam, lParam, msg, hwnd) {
        if (wParam == 4)
            ExitApp()
            
        /** 0. Throttle Brightness Update */
        if (wParam == 5) {
            this.myPendingBrightness := lParam
            if (!this.myWmiBusy) {
                this.myWmiBusy := true
                SetTimer(ObjBindMethod(this, "ProcessBrightnessQueue"), -1)
            }
            return 1
        }

        /** 1. Fetch mouse state via Raw Input API */
        myCustomActive := -1
        if (wParam & 1)
            myCustomActive := this.CheckCustomState()

        /** 2. Fetch screen brightness via WMI */
        myBrightness := -1
        if (wParam & 2) {
            try for monitor in ComObjGet(this.myWmiNamespace).ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
                myBrightness := monitor.CurrentBrightness
        }

        /** 3. Fetch Audio status via COM */
        myAudio := "-1"
        if (wParam & 4)
            myAudio := HardwareDaemon.AudioMonitor.Update()

        /** 4. Dispatch data */
        this.DispatchIpcEvent(myCustomActive, myBrightness, myAudio)
        SetTimer(ObjBindMethod(this, "InitWmiAsync"), -50)
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
}