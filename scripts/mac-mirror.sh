#!/usr/bin/env bash
# mac-mirror.sh - Mac'te AirPlay Ekran Yansitma'yi scriptle baslat/durdur.
# Yalnizca macOS. Denetim Merkezi'ni UI scripting (System Events) ile tiklar.
#
# Kullanim:
#   mac-mirror.sh probe            # Denetim Merkezi ogelerini listeler (teshis, hicbir sey degistirmez)
#   mac-mirror.sh start [TV adi]   # yansitmayi baslatir (varsayilan: $AIRPLAY_NAME ya da "Salon TV")
#   mac-mirror.sh stop  [TV adi]   # yansitmayi durdurur
#   mac-mirror.sh click [TV adi]   # durum okumadan cihaz satirina bir kez tiklar
#                                  # (macOS arayuz durumu guvenilmez; 60-soak gercek
#                                  #  durumu TV'den okuyup bunu kullanir)
#
# Gereken izin (bir kez): Sistem Ayarlari > Gizlilik ve Guvenlik > Erisilebilirlik
# altinda Terminal (ya da kullandiginiz terminal uygulamasi) acik olmali.
# Turkce ve Ingilizce macOS arayuzu desteklenir ("Yans" / "Mirroring" eslesmesi).
set -u

ACTION="${1:-}"
TV="${2:-${AIRPLAY_NAME:-Salon TV}}"
case "$ACTION" in probe|start|stop|click) ;; *) echo "Kullanim: $0 {probe|start|stop|click} [TV adi]" >&2; exit 2 ;; esac
[ "$(uname -s)" = "Darwin" ] || { echo "Bu script yalnizca macOS'ta calisir." >&2; exit 2; }

osascript - "$ACTION" "$TV" <<'APPLESCRIPT'
-- Ogenin aciklamasi | adi | AXIdentifier'i. System Events baglaminda okunmali,
-- aksi halde ozellikler cozulmez ve bos doner.
on descOf(el)
	set t to ""
	tell application "System Events"
		try
			set d to description of el
			if d is not missing value then set t to (d as text)
		end try
		try
			set n to name of el
			if n is not missing value then set t to t & " | " & (n as text)
		end try
		try
			set i to value of attribute "AXIdentifier" of el
			if i is not missing value then set t to t & " | " & (i as text)
		end try
	end tell
	return t
end descOf

on isMirroring(el)
	set t to my descOf(el)
	return (t contains "Mirroring") or (t contains "Yans")
end isMirroring

-- Denetim Merkezi / Ekran Yansitma menusunu acar; acilan pencereyi dondurur
on openMirroringPanel()
	tell application "System Events" to tell application process "ControlCenter"
		-- 1) Menu cubugunda ayri "Ekran Yansitma" ogesi varsa onu kullan
		repeat with mbi in (menu bar items of menu bar 1)
			if my isMirroring(mbi) then
				click mbi
				delay 1.5
				return window 1
			end if
		end repeat
		-- 2) Yoksa Denetim Merkezi'ni ac, icindeki Ekran Yansitma karosuna tikla
		set opened to false
		repeat with mbi in (menu bar items of menu bar 1)
			set t to my descOf(mbi)
			if (t contains "Control Center") or (t contains "Denetim Merkezi") or (t contains "controlcenter") then
				click mbi
				set opened to true
				exit repeat
			end if
		end repeat
		if not opened then error "Denetim Merkezi menu ogesi bulunamadi (probe ciktisini gonderin)"
		delay 1.5
		repeat with el in (entire contents of window 1)
			try
				if (my isMirroring(el)) and ((role of el) is in {"AXCheckBox", "AXButton", "AXDisclosureTriangle"}) then
					click el
					delay 1.5
					return window 1
				end if
			end try
		end repeat
		error "Ekran Yansitma karosu bulunamadi (probe ciktisini gonderin)"
	end tell
end openMirroringPanel

on closePanel()
	tell application "System Events" to key code 53 -- Esc
end closePanel

-- Paneli acar ve cihazin durumunu dondurur: {"off", kutu} ya da {"on", ucgen}.
-- macOS 15: bagli degilken cihaz AXCheckBox (value 0); yansitilirken ayni
-- AXIdentifier ile AXDisclosureTriangle + "Su An Yansitiliyor" metni gorunur.
-- Ogeler probe ile ayni yoldan (process > window > entire contents, indeksle)
-- okunur. Birden fazla cihazda TV adi baslik/yardim metninde aranir.
on deviceState(tv)
	my openMirroringPanel()
	set devBoxes to {}
	set devTris to {}
	set matchedDev to missing value
	tell application "System Events" to tell application process "ControlCenter"
		repeat with wi from 1 to (count of windows)
			set items_ to entire contents of window wi
			repeat with k from 1 to (count of items_)
				set el to item k of items_
				set r to ""
				try
					set r to (role of el) as text
				end try
				if r is "AXCheckBox" or r is "AXDisclosureTriangle" then
					set t to my descOf(el)
					if t contains "screen-mirroring-device-" then
						-- Acik cihaz bazen ucgen, bazen value=1 kutu olarak gorunur
						set cv to 0
						if r is "AXCheckBox" then
							try
								set cv to (value of el) as integer
							end try
						end if
						if r is "AXCheckBox" and cv is 0 then
							set onOff to "off"
							set end of devBoxes to el
						else
							set onOff to "on"
							set end of devTris to el
						end if
						try
							set t to t & " | " & ((value of attribute "AXTitle" of el) as text)
						end try
						try
							set t to t & " | " & ((help of el) as text)
						end try
						if t contains tv then set matchedDev to {onOff, el}
					end if
				end if
			end repeat
		end repeat
	end tell
	if matchedDev is not missing value then
		return matchedDev
	end if
	if (count of devTris) > 0 and (count of devBoxes) is 0 then return {"on", item 1 of devTris}
	if (count of devBoxes) is 1 and (count of devTris) is 0 then return {"off", item 1 of devBoxes}
	my closePanel()
	error "'" & tv & "' secilemedi: " & (count of devBoxes) & " kapali + " & (count of devTris) & " acik cihaz (probe ciktisini gonderin)"
end deviceState

-- Panel gec acilabilir ya da cihaz listesi (durdurduktan hemen sonra) bir
-- sure bos gelebilir: 6 kez, 2 sn arayla yeniden denenir.
on stateWithRetry(tv)
	repeat with tryNo from 1 to 6
		try
			return my deviceState(tv)
		on error errMsg
			my closePanel()
			if tryNo is 6 then error errMsg
			delay 2
		end try
	end repeat
end stateWithRetry

on run argv
	set act to item 1 of argv
	set tv to item 2 of argv
	if act is "probe" then
		set out to "== Menu cubugu (ControlCenter) ==" & linefeed
		tell application "System Events" to tell application process "ControlCenter"
			repeat with mbi in (menu bar items of menu bar 1)
				set out to out & "  " & my descOf(mbi) & linefeed
			end repeat
		end tell
		try
			set w to my openMirroringPanel()
			tell application "System Events" to tell application process "ControlCenter"
				set out to out & "== Pencere sayisi: " & (count of windows) & " ==" & linefeed
				repeat with wi from 1 to (count of windows)
					set ww to window wi
					set items_ to entire contents of ww
					set out to out & "== Pencere " & wi & " (" & (count of items_) & " oge) ==" & linefeed
					set k to 0
					repeat with el in items_
						set k to k + 1
						if k > 120 then exit repeat
						set r to "?"
						try
							set r to (role of el) as text
						end try
						set v to ""
						try
							set v to (value of el) as text
						end try
						set out to out & "  " & r & " : " & my descOf(el) & " = " & v & linefeed
					end repeat
				end repeat
			end tell
		on error msg
			set out to out & "HATA: " & msg & linefeed
		end try
		my closePanel()
		return out
	end if

	set devState to my stateWithRetry(tv)
	if act is "click" then
		tell application "System Events" to click (item 2 of devState)
		delay 0.5
		my closePanel()
		return "click tamam (" & tv & ", arayuz durumu once: " & (item 1 of devState) & ")"
	end if
	if act is "start" then
		if (item 1 of devState) is "on" then
			my closePanel()
			return "start: zaten yansitiliyor (" & tv & ")"
		end if
		tell application "System Events" to click (item 2 of devState)
		delay 0.5
		my closePanel()
		-- dogrula: baglanti birkac saniye surebilir
		delay 3
		set devState2 to my stateWithRetry(tv)
		my closePanel()
		if (item 1 of devState2) is "off" then error "start dogrulanamadi: tiklamadan sonra yansitma baslamadi"
		return "start tamam (" & tv & ")"
	end if
	-- stop
	if (item 1 of devState) is "off" then
		my closePanel()
		return "stop: zaten yansitma yok (" & tv & ")"
	end if
	tell application "System Events" to click (item 2 of devState)
	delay 0.5
	my closePanel()
	-- dogrula: panel yeniden acilip durum okunur
	delay 2
	set devState2 to my stateWithRetry(tv)
	my closePanel()
	if (item 1 of devState2) is "on" then error "stop dogrulanamadi: tiklamadan sonra hala yansitiliyor (probe ciktisini gonderin)"
	return "stop tamam (" & tv & ")"
end run
APPLESCRIPT
