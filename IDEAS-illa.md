# Ide notch versi illa

## ✅ Dipilih illa (9 Nov 2026), urutan kerja
0. Langkah 0 (bundle id, matikan Sparkle, nama + icon)
1. Shelf pinter (prioritas!)
2. Claude Code status + pet mascot animasi waktu agent jalan (cari pet open source)
3. Clipboard history
4. Next meeting countdown + tombol Join
5. Cuaca (tanpa jam sholat)
6. Toggle Do Not Disturb
7. Polish: warna ikut album art di semua tab

Ditolak: pomodoro, quick notes, jam sholat.

Fork: okashiina/boring.notch (upstream: TheBoredTeam/boring.notch, GPL-3.0)

## Langkah 0: bikin jadi "punya kita" (wajib duluan)
- Ganti bundle id ke `com.okashiina.notch` (helper XPC ikut ganti), biar bisa jalan barengan / gantiin versi installed.
- Matikan Sparkle auto-update (SUFeedURL masih nunjuk upstream, nanti app-nya "update" balik ke versi asli).
- Nama + icon sendiri.

## Tier 1: paling kerasa sehari-hari
1. **Pomodoro / focus timer** di notch tertutup (sisa waktu kecil di sebelah notch), plus mode Focus macOS.
2. **Clipboard history** sebagai tab baru: 20 copy terakhir, klik = copy lagi, pin item favorit.
3. **Claude Code / agent status**: notch nunjukin kalau sesi Claude lagi kerja / nunggu jawabanmu / selesai (lewat hook yang nulis ke file atau URL scheme). Cocok sama workflow-mu yang banyak sesi paralel.
4. **Next meeting countdown**: "Standup dalam 5 menit", tombol Join buat link Zoom/Meet/Teams.
5. **Quick notes / to-do**: ketik catatan cepat dari notch, opsional simpan ke vault Obsidian.

## Tier 2: enak tapi nggak urgent
6. **Render / job tracker**: progress render Remotion atau job di Legion tampil di notch (via file/HTTP lokal).
7. **YouTube upload watcher**: hitung mundur jadwal publish Two Tabs.
8. **Cuaca + jam sholat** di notch tertutup.
9. **Kontrol cepat**: toggle Do Not Disturb, caffeinate (keep awake), mic mute.
10. **Shelf yang lebih pinter**: kompres/convert gambar, upload ke tempat share, langsung dapat link.

## Tier 3: polishing
11. Tema/warna sesuai album art di semua tab, bukan cuma musik.
12. Shortcut keyboard buat buka tab tertentu.
13. Pecah `SettingsView.swift` (1799 baris) biar gampang nambah setting.

## Catatan teknis
- Upstream lagi bikin sistem extension (branch `stack/extensions-*`) yang ngerombak ContentView/coordinator. Kalau kita ngedit file itu berat-berat, nanti susah narik update upstream. Saran: fitur baru taruh di folder sendiri (`boringNotch/illa/`), sentuh file inti sesedikit mungkin.
- Nambah tab: `NotchViews` (enums/generic.swift), array `tabs` (components/Tabs/TabSelectionView.swift), switch di ContentView.swift ~L346.
