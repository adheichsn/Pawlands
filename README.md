# Pawlands — Pet Follow Foundation

Tahap pertama: maksimal **4 pet aktif**, satu jenis/species hanya boleh muncul sekali dalam party. Semua nama, pesan runtime, dan command feedback menggunakan bahasa Inggris.

Paket ini menambahkan fondasi source baru untuk `Pawlands(1).rbxl`. Semua file source berstatus **ADDED**. Tidak ada file existing yang diedit, dihapus, atau dipindahkan.

## Pasang ke project pertama

1. Extract ZIP ke folder baru bernama `Pawlands`. Di dalamnya harus langsung terlihat `default.project.json`, `README.md`, dan `src`.
2. Buka folder tersebut di VS Code.
3. Buka **Pawlands(1).rbxl yang sudah berisi aset pet** di Roblox Studio, dalam Edit mode.
4. Di terminal VS Code jalankan:

   ```sh
   rojo serve default.project.json
   ```

5. Di plugin Rojo pada Studio, hubungkan ke server lokal (port default `34872`), lalu lakukan sync.
6. Gunakan **Play**, bukan Run. Saat Play di Studio, Bunny, Cat, Dog, dan Dragon akan menjadi party preview.

Project Rojo hanya mengelola namespace `Pawlands` pada ReplicatedStorage, ServerScriptService, dan StarterPlayerScripts. Parent service menggunakan `$ignoreUnknownInstances = true`. Map, Lighting, SpawnLocation, StarterGui, dan `ReplicatedStorage/Assets` tetap dikelola di Studio.

`rojo build` untuk paket ini hanya menghasilkan source fondasi. Gunakan live sync ke RBXL yang berisi map dan aset untuk bermain.

## Aset Studio yang dipakai

Lokasi model: `ReplicatedStorage > Assets > Pets > StoneIsland`.

Nama yang didukung: **Bunny, Cat, Chicken, Cow, Dog, Dragon, Piggy, Raccoon, Rat, Turtle**.

Semua model pada file yang diperiksa mempunyai MeshPart bernama `Body`. Pada salinan runtime, script memilih Body sebagai PrimaryPart serta membuat pet Anchored dan non-collidable. Template Studio tetap menjadi sumber model. Tidak ada model atau GUI baru yang perlu dibuat untuk tahap ini; script hanya menyalin model pet yang sudah kamu sediakan.

Gerakan darat menggunakan hop kecil; Dragon memakai mode melayang yang dapat diubah di `PetCatalog.lua`. Gerakan ini menggunakan transform model dan tidak memerlukan Animation, SFX, atau VFX tambahan.

## Struktur modular

| Folder source | Lokasi runtime | Tanggung jawab |
|---|---|---|
| `src/shared/Config` | `ReplicatedStorage/Pawlands/Shared/Config` | Katalog pet, batas party, dan angka gerakan |
| `src/shared/Pets` | `ReplicatedStorage/Pawlands/Shared/Pets` | Validasi party, format sinkronisasi, pencarian aset |
| `src/server/Config` | `ServerScriptService/Pawlands/Config` | Konfigurasi preview Studio |
| `src/server/Pets` | `ServerScriptService/Pawlands/Pets` | State party server dan command pengujian Studio |
| `src/client/Pets` | `StarterPlayerScripts/Pawlands/Pets` | Pengamatan party dan lifecycle player |
| `src/client/Pets/Follow` | `StarterPlayerScripts/Pawlands/Pets/Follow` | Formasi, pembacaan permukaan tanah, model visual, gerakan |

`Bootstrap.server.lua` dan `Bootstrap.client.lua` hanya menjalankan modul. Tidak ada satu file yang menampung seluruh sistem.

## Menguji party tanpa GUI

Command ini hanya aktif saat Play/Team Test di **Studio**. Pesan hasil muncul di **Server Output**.

| Command chat | Hasil |
|---|---|
| `!pets Bunny Cat Dog Dragon` | Empat pet berbeda |
| `!pets Cow Rat Turtle` | Ganti menjadi tiga pet |
| `!pets Dragon Dragon` | Ditolak; party lama tetap utuh |
| `!pets Drago Dragon` | Ditolak; Drago adalah alias Dragon |
| `!pets Bunny Cat Dog Dragon Cow` | Ditolak karena melebihi empat |
| `!pets clear` | Kosongkan party |
| `!pets list` | Tampilkan daftar pet di Output |

Huruf besar/kecil dan pemisah koma/spasi diterima. Duplikat diperiksa berdasarkan `SpeciesId`; varian yang kelak memiliki SpeciesId sama juga tidak dapat dipakai bersamaan.

Apabila chat tidak tersedia dalam konfigurasi Studio kamu, gunakan Command Bar pada **konteks Server saat Play**:

```lua
local players = game:GetService("Players")
local player = players:GetPlayers()[1]
local service = require(game:GetService("ServerScriptService").Pawlands.Pets.PetPartyService)
if player then
    print(service.SetParty(player, { "Bunny", "Cat", "Dog", "Dragon" }))
end
```

Untuk tes beberapa player, ganti pemilihan player dengan `players:FindFirstChild("Player1")` atau nama player yang terlihat di Explorer.

## Batas tahap ini

- Party preview otomatis hanya aktif di Studio. Ubah `src/server/Config/Development.lua` untuk mengganti susunan atau menonaktifkannya.
- Preview bukan pemberian pet permanen. Pada server live, party awal kosong sampai logic server memanggil `PetPartyService.SetParty(player, ids)`.
- `SetParty` adalah API server internal. Sistem inventory/tutorial berikutnya harus memvalidasi kepemilikan sebelum memanggilnya. Tidak ada equip remote dari client pada paket ini.
- Party bertahan saat respawn dalam sesi yang sama. Inventory, hatch, save/load, combat, GUI, SFX, VFX, NPC, dan tutorial belum termasuk tahap ini.
- Pet bergerak memakai formasi dan raycast permukaan; navigasi mengitari tembok belum termasuk. Jika tanah belum termuat, visual ditahan sampai permukaan tersedia, atau dikembalikan ke dekat player.
- Pet player lain ditampilkan ketika karakternya tersedia dalam jarak render. Clone visual pet dibuat lokal pada setiap client dari party yang diterbitkan server.

## Konfigurasi yang sering diubah

| File | Pengaturan |
|---|---|
| `src/shared/Config/PetParty.lua` | `MaxSize = 4`, attribute sinkronisasi, lokasi model |
| `src/shared/Config/PetCatalog.lua` | Nama model, SpeciesId, ground/flying, HoverHeight, YawOffset |
| `src/shared/Config/PetFollow.lua` | Jarak formasi, kelancaran gerak, hop, raycast, recall, jarak render |
| `src/server/Config/Development.lua` | Party preview dan command khusus Studio |

Jika suatu model tampak membelakangi arah player, ubah **YawOffset pet tersebut** menjadi `180`, kemudian ulangi Play. Arah depan mesh tetap perlu diverifikasi secara visual di Studio.

## Validasi

- Seluruh **17 file Lua** berhasil dikompilasi dengan Luau 0.740.
- Modul aturan/config/codec/formasi yang tidak memerlukan engine lolos Luau analyzer.
- **45 pengujian Luau** lolos untuk aturan party, alias/species, batas kapasitas, codec, formasi, perubahan server yang atomik, observer respawn/cleanup, serta pembatasan preview ke Studio. Layanan Roblox pada tes ini menggunakan mock; ini bukan sesi Roblox Studio.
- `rojo build` dan `rojo sourcemap` berhasil dengan Rojo 7.7.0. Hasil source berisi satu Script bootstrap server dan satu LocalScript bootstrap client, tanpa GUI atau aset map.
- Belum dijalankan di Roblox Studio. Pemeriksaan visual dan multiplayer tetap diperlukan di map asli.

Tes Studio yang perlu kamu lakukan setelah sync:

1. Jalan, berhenti, berbelok, melompat, dan naik/turun ramp. Periksa empat model terpisah dan arah depannya.
2. Reset Character: pet mengikuti karakter baru dan tidak tertinggal pada karakter lama.
3. Coba command duplikat dan lima pet; party sebelumnya harus tetap utuh.
4. Jalankan dua player: masing-masing melihat party player lain; pet hilang saat pemilik keluar.
5. Ubah posisi karakter jauh melalui Server Command Bar: pet kembali dekat karakter setelah area tersedia.

## Referensi implementasi

File UXR Pet System v5.0 yang kamu berikan digunakan sebagai referensi pola follow, formasi, raycast tanah, dan perbedaan gerak ground/flying. Fondasi ini memakai modul Pawlands sendiri dan aset dari RBXL terbaru.

- [Rojo project format](https://rojo.space/docs/v7/project-format/)
- [Roblox RunService](https://create.roblox.com/docs/reference/engine/classes/RunService)
- [Roblox RaycastParams](https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams)

## Suggested commit

```text
Add modular pet follow foundation

- Add server-owned parties with four unique species per party.
- Reuse Studio pet models with client-side follow visuals.
- Separate catalog, validation, formation, ground probing, and motion.
- Handle character replacement, distant recall, and player cleanup.
- Add Studio-only preview parties and test commands.
- Preserve Studio-owned assets with scoped Rojo mounts.
```
