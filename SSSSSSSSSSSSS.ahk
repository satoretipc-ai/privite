#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn
#Warn All, Off

; ====== 中央領域 PixelSearch版 → 長押し ======
ConfigFile := A_ScriptDir "\config.ini"

; ---- デフォルト値 ----
Defaults := Map(
    "ActiveKey", "Alt",
    "ActiveColorName", "赤",
    "ColorTol", 85,
    "HoldMs", 150,
    "PingMs", 10,
    "RepeatDownMs", 0,
    "ReactionMs", 60,            ; ★追加: 反応速度(ms)
    "SingleShotIntervalMs", 120, ; ★追加: 単発の次弾間隔(ms)
    "RandomHold", 1,
    "MinHoldMs", 100,
    "MaxHoldMs", 300,
    "WASDDelayMs", 20,
    "WASDDisable", 1,
    "FovX", 3,
    "FovY", 7,
    "TriggerMode", "ホールド"
)

; ---- 設定読み込み ----
ActiveKey       := IniRead(ConfigFile, "Settings", "ActiveKey", "Alt")
ActiveColorName := IniRead(ConfigFile, "Settings", "ActiveColorName", "赤")
ColorTol        := Integer(IniRead(ConfigFile, "Settings", "ColorTol", 85))
HoldMs          := Integer(IniRead(ConfigFile, "Settings", "HoldMs", 150))
PingMs          := Integer(IniRead(ConfigFile, "Settings", "PingMs", 10))
RepeatDownMs    := Integer(IniRead(ConfigFile, "Settings", "RepeatDownMs", 0))
ReactionMs      := Integer(IniRead(ConfigFile, "Settings", "ReactionMs", 60))
SingleShotIntervalMs := Integer(IniRead(ConfigFile, "Settings", "SingleShotIntervalMs", 120))
RandomHold      := Integer(IniRead(ConfigFile, "Settings", "RandomHold", 1))
MinHoldMs       := Integer(IniRead(ConfigFile, "Settings", "MinHoldMs", 100))
MaxHoldMs       := Integer(IniRead(ConfigFile, "Settings", "MaxHoldMs", 300))
WASDDelayMs     := Integer(IniRead(ConfigFile, "Settings", "WASDDelayMs", 20))
WASDDisable     := Integer(IniRead(ConfigFile, "Settings", "WASDDisable", 1))
FovX            := Integer(IniRead(ConfigFile, "Settings", "FovX", 3))
FovY            := Integer(IniRead(ConfigFile, "Settings", "FovY", 7))
TriggerMode     := IniRead(ConfigFile, "Settings", "TriggerMode", "ホールド")

; ---- 固定 ----
TimerInterval := 1
SW := A_ScreenWidth // 2, SH := A_ScreenHeight // 2
SL := SW - FovX, ST := SH - FovY, SR := SW + FovX, SB := SH + FovY

ColorTable := Map("赤",0xFF0000, "黄",0xFFFF00, "紫",0x800080)
TargetColor := ColorTable[ActiveColorName]

; ---- 実行環境 ----
CoordMode("Pixel","Screen"), CoordMode("Mouse","Screen")
ProcessSetPriority("H")
Critical("On")
SetKeyDelay(-1,1), SetMouseDelay(-1), SetWinDelay(-1)
try DllCall("winmm\timeBeginPeriod","UInt",1)
OnExit( (*) => DllCall("winmm\timeEndPeriod","UInt",1) )

; ---- 状態 ----
BotRunning := false
Paused := false
_isHolding := false
_holdX := 0, _holdY := 0
_holdEndAt := 0
_hChild := 0, _hRoot := 0
_lpChild := 0, _lpRoot := 0
_nextPingAt := 0
_nextRepeatDownAt := 0
_lastWASDReleaseTime := 0

_nextSingleShotAt := 0        ; ★単発: 次にクリックしてよい時刻
_singleShotConsumed := false  ; ★単発: 今見えてる色は撃った(消えるまで撃たない)

; ================= GUI =================
myGui := Gui("+AlwaysOnTop +MinSize")
myGui.Title := "色クリック設定（PixelSearch版）"

; モード選択（最上部に配置）
myGui.Add("Text","Section","動作モード:")
ddMode := myGui.Add("DropDownList","w160",["ホールド","ストッピング","単発"])
ddMode.Choose(TriggerMode)
ddMode.OnEvent("Change", (*) => UpdateModeUI())

myGui.Add("Text","xs Section","発動キー:")
ddKey := myGui.Add("DropDownList","w160",["Alt","Shift","Ctrl","XButton1","XButton2", "t"])
ddKey.Choose(ActiveKey)

myGui.Add("Text","xs","色:")
ddColor := myGui.Add("DropDownList","w160",["赤","黄","紫"])
ddColor.Choose(ActiveColorName)

myGui.Add("Text","xs","ColorTol (0-255):")
eTol := myGui.Add("Edit","w120"), eTol.Value := ColorTol

; 検索範囲設定
myGui.Add("Text","xs","検索範囲 FovX (横):")
eFovX := myGui.Add("Edit","w120"), eFovX.Value := FovX

myGui.Add("Text","xs","検索範囲 FovY (縦):")
eFovY := myGui.Add("Edit","w120"), eFovY.Value := FovY

; WASD制御設定
myGui.Add("Text","xs","WASD制御:")
chkWASDDisable := myGui.Add("Checkbox","xs", "WASD中無効")
chkWASDDisable.Value := WASDDisable

myGui.Add("Text","xs","WASD遅延 (ms):")
eWASDDelay := myGui.Add("Edit","w120"), eWASDDelay.Value := WASDDelayMs

; ホールド時間設定
myGui.Add("Text","xs","ホールド時間設定:")
chkRandom := myGui.Add("Checkbox","xs", "ランダムホールド")
chkRandom.Value := RandomHold

myGui.Add("Text","xs","固定HoldMs (ms):")
eHold := myGui.Add("Edit","w120"), eHold.Value := HoldMs

myGui.Add("Text","xs","ランダム最小値 (ms):")
eMinHold := myGui.Add("Edit","w120"), eMinHold.Value := MinHoldMs

myGui.Add("Text","xs","ランダム最大値 (ms):")
eMaxHold := myGui.Add("Edit","w120"), eMaxHold.Value := MaxHoldMs

myGui.Add("Text","xs","PingMs (MMOVE間隔):")
ePing := myGui.Add("Edit","w120"), ePing.Value := PingMs

; 反応速度
myGui.Add("Text","xs","反応速度 (ms):")
eReact := myGui.Add("Edit","w120"), eReact.Value := ReactionMs

; ★単発間隔
myGui.Add("Text","xs","単発間隔 (ms):")
eSingleInterval := myGui.Add("Edit","w120"), eSingleInterval.Value := SingleShotIntervalMs

myGui.Add("Text","xs","RepeatDownMs (0=無効):")
eRep := myGui.Add("Edit","w120"), eRep.Value := RepeatDownMs

btnApply := myGui.Add("Button","xs w240","適用 & 保存")
btnApply.OnEvent("Click", (*) => ApplySettings())

; ボット制御ボタン
myGui.Add("Text", "xs Section", "")
btnStart := myGui.Add("Button","xs w115","起動")
btnStop := myGui.Add("Button","x+10 w115","停止")
btnExit := myGui.Add("Button","xs w240","スクリプト終了")

btnStart.OnEvent("Click", (*) => StartBot())
btnStop.OnEvent("Click", (*) => StopBot())
btnExit.OnEvent("Click", (*) => ExitApp())

; ステータス表示
statusText := myGui.Add("Text","xs w240 Center +Border","ステータス: 停止中")

; ホットキー説明
hotkeyText := myGui.Add("Text","xs w240", "
(
F1: 一時停止切替
F10: GUI表示
F11: 起動
F12: 停止
)")

myGui.OnEvent("Close", (*) => myGui.Hide())
myGui.OnEvent("Escape", (*) => myGui.Hide())

UpdateModeUI(){
    global ddMode, ddKey, hotkeyText
    currentMode := ddMode.Text
    if currentMode = "ストッピング" || currentMode = "単発" {
        ddKey.Visible := false
        hotkeyText.Visible := false
    } else {
        ddKey.Visible := true
        hotkeyText.Visible := true
    }
}

ShowGUI(){
    global myGui
    UpdateModeUI()
    myGui.Show("AutoSize Center")
    WinActivate("ahk_id " myGui.Hwnd)
}
ShowGUI()

; ---- トレイメニュー ----
A_TrayMenu.Delete()
A_TrayMenu.Add("設定を開く", (*) => ShowGUI())
A_TrayMenu.Add("起動", (*) => StartBot())
A_TrayMenu.Add("停止", (*) => StopBot())
A_TrayMenu.Add("一時停止切替", (*) => TogglePause())
A_TrayMenu.Add()
A_TrayMenu.Add("終了", (*) => ExitApp())

TogglePause(){
    global Paused, BotRunning
    if !BotRunning {
        ToolTip("ボットが起動していません", 10, 90)
        SetTimer(() => ToolTip(), -600)
        return
    }
    Paused := !Paused
    ToolTip("State: " (Paused ? "Paused" : "Running"), 10, 90)
    SetTimer(() => ToolTip(), -600)
}

; ================= ボット制御 =================
StartBot(){
    global BotRunning, statusText, TimerInterval, TriggerMode
    if BotRunning {
        ToolTip("既に起動中です", 10, 90)
        SetTimer(() => ToolTip(), -600)
        return
    }
    BotRunning := true
    statusText.Text := "ステータス: 起動中 (" TriggerMode "モード)"
    SetTimer(WatchLoop, TimerInterval)
    ToolTip("起動 (" TriggerMode "モード)", 10, 90)
    SetTimer(() => ToolTip(), -1000)
}

StopBot(){
    global BotRunning, statusText, _isHolding
    if !BotRunning {
        ToolTip("既に停止中です", 10, 90)
        SetTimer(() => ToolTip(), -600)
        return
    }
    if _isHolding {
        EndHold()
        _isHolding := false
    }
    BotRunning := false
    statusText.Text := "ステータス: 停止中"
    SetTimer(WatchLoop, 0)
    ToolTip("停止", 10, 90)
    SetTimer(() => ToolTip(), -1000)
}

; ================= 設定反映 =================
ApplySettings(){
    global ActiveKey, ActiveColorName, TargetColor, ConfigFile, ColorTable
    global ColorTol, HoldMs, PingMs, RepeatDownMs, RandomHold, MinHoldMs, MaxHoldMs
    global WASDDelayMs, WASDDisable, FovX, FovY, SW, SH, SL, ST, SR, SB, TriggerMode
    global ReactionMs, SingleShotIntervalMs
    global ddMode, ddKey, ddColor, eTol, eFovX, eFovY, eHold, ePing, eRep, eReact, eSingleInterval
    global chkRandom, eMinHold, eMaxHold, eWASDDelay, chkWASDDisable

    TriggerMode     := ddMode.Text
    ActiveKey       := ddKey.Text
    ActiveColorName := ddColor.Text
    TargetColor     := ColorTable[ActiveColorName]

    ColorTol      := Max(0, Min(255, Integer(Trim(eTol.Value))))
    FovX          := Max(1, Min(100, Integer(Trim(eFovX.Value))))
    FovY          := Max(1, Min(100, Integer(Trim(eFovY.Value))))
    HoldMs        := Max(1, Min(20000, Integer(Trim(eHold.Value))))
    PingMs        := Max(1, Min(1000, Integer(Trim(ePing.Value))))
    RepeatDownMs  := Max(0, Min(1000, Integer(Trim(eRep.Value))))
    ReactionMs    := Max(0, Min(2000, Integer(Trim(eReact.Value))))
    SingleShotIntervalMs := Max(0, Min(5000, Integer(Trim(eSingleInterval.Value))))
    RandomHold    := chkRandom.Value
    MinHoldMs     := Max(1, Min(20000, Integer(Trim(eMinHold.Value))))
    MaxHoldMs     := Max(MinHoldMs, Min(20000, Integer(Trim(eMaxHold.Value))))
    WASDDelayMs   := Max(0, Min(1000, Integer(Trim(eWASDDelay.Value))))
    WASDDisable   := chkWASDDisable.Value

    SL := SW - FovX, ST := SH - FovY, SR := SW + FovX, SB := SH + FovY

    if MinHoldMs > MaxHoldMs {
        temp := MinHoldMs
        MinHoldMs := MaxHoldMs
        MaxHoldMs := temp
        eMinHold.Value := MinHoldMs
        eMaxHold.Value := MaxHoldMs
    }

    IniWrite(TriggerMode,     ConfigFile, "Settings", "TriggerMode")
    IniWrite(ActiveKey,       ConfigFile, "Settings", "ActiveKey")
    IniWrite(ActiveColorName, ConfigFile, "Settings", "ActiveColorName")
    IniWrite(ColorTol,        ConfigFile, "Settings", "ColorTol")
    IniWrite(FovX,            ConfigFile, "Settings", "FovX")
    IniWrite(FovY,            ConfigFile, "Settings", "FovY")
    IniWrite(HoldMs,          ConfigFile, "Settings", "HoldMs")
    IniWrite(PingMs,          ConfigFile, "Settings", "PingMs")
    IniWrite(RepeatDownMs,    ConfigFile, "Settings", "RepeatDownMs")
    IniWrite(ReactionMs,      ConfigFile, "Settings", "ReactionMs")
    IniWrite(SingleShotIntervalMs, ConfigFile, "Settings", "SingleShotIntervalMs")
    IniWrite(RandomHold,      ConfigFile, "Settings", "RandomHold")
    IniWrite(MinHoldMs,       ConfigFile, "Settings", "MinHoldMs")
    IniWrite(MaxHoldMs,       ConfigFile, "Settings", "MaxHoldMs")
    IniWrite(WASDDelayMs,     ConfigFile, "Settings", "WASDDelayMs")
    IniWrite(WASDDisable,     ConfigFile, "Settings", "WASDDisable")

    UpdateModeUI()

    wasdStatus := WASDDisable ? "有効" : "無効"
    ToolTip("保存: " TriggerMode " / Fov(" FovX "," FovY ") / 反応 " ReactionMs "ms / 単発 " SingleShotIntervalMs "ms / WASD " wasdStatus, 10, 10)
    SetTimer(() => ToolTip(), -1500)
}

; ================== SendInput (物理押下) ==================
SendInput_Mouse(flags){
    cbSize := (A_PtrSize=8) ? 40 : 28
    buf := Buffer(cbSize, 0)
    NumPut("UInt", 0, buf, 0)
    NumPut("Int", 0, buf, 4)
    NumPut("Int", 0, buf, 8)
    NumPut("UInt", 0, buf, 12)
    NumPut("UInt", flags, buf, 16)
    NumPut("UInt", 0, buf, 20)
    NumPut("UPtr", 0, buf, 24)
    DllCall("user32\SendInput", "UInt",1, "Ptr",buf.Ptr, "Int",cbSize)
}

; ================== PM ユーティリティ ==================
HwndFromPoint(x, y){
    x := x & 0xFFFFFFFF, y := y & 0xFFFFFFFF
    return DllCall("user32\WindowFromPoint", "Int64", (y<<32) | x, "Ptr")
}
GetRootWindow(hWnd){
    return hWnd ? DllCall("user32\GetAncestor","Ptr",hWnd,"UInt",2,"Ptr") : 0
}
ScreenToClientXY(hWnd, x, y, &cx, &cy){
    cx := 0, cy := 0
    if !hWnd
        return false
    pt := Buffer(8,0)
    NumPut("Int", x, pt, 0), NumPut("Int", y, pt, 4)
    if !DllCall("user32\ScreenToClient","Ptr",hWnd,"Ptr",pt.Ptr)
        return false
    cx := NumGet(pt,0,"Int"), cy := NumGet(pt,4,"Int")
    return true
}
LParamFor(hWnd, x, y){
    cx := 0, cy := 0
    if !ScreenToClientXY(hWnd, x, y, &cx, &cy)
        return 0
    return (cy<<16) | (cx & 0xFFFF)
}

BeginHold(x, y){
    global _hChild, _hRoot, _lpChild, _lpRoot
    _hChild := HwndFromPoint(x, y)
    if !_hChild
        return false
    _hRoot := GetRootWindow(_hChild)
    _lpChild := LParamFor(_hChild, x, y)
    _lpRoot  := (_hRoot && _hRoot!=_hChild) ? LParamFor(_hRoot, x, y) : 0

    SendInput_Mouse(0x0002)

    if (_hChild && _lpChild) {
        DllCall("user32\PostMessageW","Ptr",_hChild,"UInt",0x0200,"UPtr",0x0001,"Ptr",_lpChild)
        DllCall("user32\PostMessageW","Ptr",_hChild,"UInt",0x0201,"UPtr",0x0001,"Ptr",_lpChild)
    }
    if (_hRoot && _lpRoot) {
        DllCall("user32\PostMessageW","Ptr",_hRoot,"UInt",0x0200,"UPtr",0x0001,"Ptr",_lpRoot)
        DllCall("user32\PostMessageW","Ptr",_hRoot,"UInt",0x0201,"UPtr",0x0001,"Ptr",_lpRoot)
    }
    return true
}

KeepAlive(){
    global _hChild, _hRoot, _lpChild, _lpRoot, RepeatDownMs
    if (_hChild && _lpChild) {
        DllCall("user32\PostMessageW","Ptr",_hChild,"UInt",0x0200,"UPtr",0x0001,"Ptr",_lpChild)
        if (RepeatDownMs>0)
            DllCall("user32\PostMessageW","Ptr",_hChild,"UInt",0x0201,"UPtr",0x0001,"Ptr",_lpChild)
    }
    if (_hRoot && _lpRoot) {
        DllCall("user32\PostMessageW","Ptr",_hRoot,"UInt",0x0200,"UPtr",0x0001,"Ptr",_lpRoot)
        if (RepeatDownMs>0)
            DllCall("user32\PostMessageW","Ptr",_hRoot,"UInt",0x0201,"UPtr",0x0001,"Ptr",_lpRoot)
    }
}

EndHold(){
    global _hChild, _hRoot, _lpChild, _lpRoot
    if (_hChild && _lpChild)
        DllCall("user32\PostMessageW","Ptr",_hChild,"UInt",0x0202,"UPtr",0,"Ptr",_lpChild)
    if (_hRoot && _lpRoot)
        DllCall("user32\PostMessageW","Ptr",_hRoot,"UInt",0x0202,"UPtr",0,"Ptr",_lpRoot)
    SendInput_Mouse(0x0004)
    _hChild := 0, _hRoot := 0, _lpChild := 0, _lpRoot := 0
}

; ================= 検出 =================
ActiveKeyPressed(){
    global ActiveKey
    switch ActiveKey {
        case "Alt":      return GetKeyState("Alt","P") || GetKeyState("LAlt","P") || GetKeyState("RAlt","P")
        case "Shift":    return GetKeyState("Shift","P") || GetKeyState("LShift","P") || GetKeyState("RShift","P")
        case "Ctrl":     return GetKeyState("Ctrl","P") || GetKeyState("LCtrl","P") || GetKeyState("RCtrl","P")
        case "XButton1": return GetKeyState("XButton1","P")
        case "XButton2": return GetKeyState("XButton2","P")
        case "t":        return GetKeyState("t","P")
        default: return false
    }
}

WASDPressed(){
    return GetKeyState("w","P") || GetKeyState("a","P") || GetKeyState("s","P") || GetKeyState("d","P")
}

ShouldAllowClick(){
    global WASDDelayMs, WASDDisable, _lastWASDReleaseTime
    if !WASDDisable
        return true
    if WASDPressed() {
        _lastWASDReleaseTime := A_TickCount
        return false
    }
    return (A_TickCount - _lastWASDReleaseTime) >= WASDDelayMs
}

GetRandomHoldTime() {
    global RandomHold, HoldMs, MinHoldMs, MaxHoldMs
    if !RandomHold
        return HoldMs
    return Random(MinHoldMs, MaxHoldMs)
}

FindTargetColor(&outX, &outY) {
    global SL, ST, SR, SB, TargetColor, ColorTol
    foundX := 0, foundY := 0
    try {
        if PixelSearch(&foundX, &foundY, SL, ST, SR, SB, TargetColor, ColorTol) {
            outX := foundX
            outY := foundY
            return true
        }
    } catch {
        return false
    }
    return false
}

; ================= 監視ループ =================
WatchLoop(){
    global Paused, BotRunning, WASDDelayMs, WASDDisable, _lastWASDReleaseTime
    global _isHolding, _holdEndAt
    global _nextPingAt, PingMs, _nextRepeatDownAt, RepeatDownMs
    global TriggerMode, ReactionMs
    global SingleShotIntervalMs, _nextSingleShotAt, _singleShotConsumed

    if !BotRunning
        return
    if Paused
        return

    now := A_TickCount

    ; ★ 単発モード：1検出＝1クリック（色が消えるまで再発射しない）
    if TriggerMode = "単発" {
        if WASDPressed() {
            _lastWASDReleaseTime := now
            return
        }
        if (now - _lastWASDReleaseTime) < WASDDelayMs
            return

        FoundX := 0, FoundY := 0
        found := FindTargetColor(&FoundX, &FoundY)

        ; 色が見つからない＝解除（次の出現で撃てる）
        if !found {
            _singleShotConsumed := false
            return
        }

        ; すでにこの「表示中の色」に対して撃っているなら何もしない
        if _singleShotConsumed
            return

        ; クールダウン（次弾まで待つ）
        if (now < _nextSingleShotAt)
            return

        Sleep(ReactionMs)

        ; 念のため：Sleep中に色が消えたら撃たない
        FoundX2 := 0, FoundY2 := 0
        if !FindTargetColor(&FoundX2, &FoundY2) {
            _singleShotConsumed := false
            return
        }

        ; 念のため：Sleep中に時間が進むので再チェック
        now2 := A_TickCount
        if (now2 < _nextSingleShotAt)
            return

        Click(FoundX2, FoundY2)

        ; この出現は消費済み（色が消えるまで再発射しない）
        _singleShotConsumed := true
        _nextSingleShotAt := now2 + SingleShotIntervalMs
        return
    }

    ; ストッピングモード
    if TriggerMode = "ストッピング" {
        if WASDPressed() {
            if _isHolding {
                EndHold()
                _isHolding := false
            }
            _lastWASDReleaseTime := now
            return
        }
        if (now - _lastWASDReleaseTime) < WASDDelayMs
            return

        if !_isHolding {
            FoundX := 0, FoundY := 0
            if FindTargetColor(&FoundX, &FoundY) {
                Sleep(ReactionMs)
                if BeginHold(FoundX, FoundY) {
                    _isHolding := true
                    currentHoldMs := GetRandomHoldTime()
                    _holdEndAt := now + currentHoldMs
                    _nextPingAt := now + PingMs
                    _nextRepeatDownAt := (RepeatDownMs>0) ? now + RepeatDownMs : 0
                }
            }
        } else {
            if (now >= _nextPingAt) {
                KeepAlive()
                _nextPingAt := now + PingMs
            }
            if (RepeatDownMs>0 && now >= _nextRepeatDownAt) {
                KeepAlive()
                _nextRepeatDownAt := now + RepeatDownMs
            }
            if (now >= _holdEndAt) {
                EndHold()
                _isHolding := false
            }
        }
        return
    }

    ; ホールドモード（元のロジック）
    if !ActiveKeyPressed(){
        if _isHolding {
            EndHold()
            _isHolding := false
        }
        return
    }

    if _isHolding && WASDDisable && WASDPressed() {
        EndHold()
        _isHolding := false
        _lastWASDReleaseTime := now
        return
    }

    if !ShouldAllowClick()
        return

    if !_isHolding {
        FoundX := 0, FoundY := 0
        if FindTargetColor(&FoundX, &FoundY) {
            Sleep(ReactionMs)
            if BeginHold(FoundX, FoundY) {
                _isHolding := true
                currentHoldMs := GetRandomHoldTime()
                _holdEndAt := now + currentHoldMs
                _nextPingAt := now + PingMs
                _nextRepeatDownAt := (RepeatDownMs>0) ? now + RepeatDownMs : 0
            }
        }
    } else {
        if (now >= _nextPingAt) {
            KeepAlive()
            _nextPingAt := now + PingMs
        }
        if (RepeatDownMs>0 && now >= _nextRepeatDownAt) {
            KeepAlive()
            _nextRepeatDownAt := now + RepeatDownMs
        }
        if (now >= _holdEndAt) {
            EndHold()
            _isHolding := false
        }
    }
}

; ================= ホットキー =================
F1::TogglePause()
F10::ShowGUI()
F11::StartBot()
F12::StopBot()
F2::Edit
F3::Reload
F4::ExitApp
