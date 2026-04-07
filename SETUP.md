# ZED 2i — Teljes visszaállítási útmutató

**Platform:** Jetson Orin Nano, L4T R36.4.3, JetPack 6.2, ARM64
**Kamera:** Stereolabs ZED 2i, S/N 98214176
**SDK:** ZED SDK 5.2.3, zed-ros2-wrapper v5.2.2, ROS2 Jazzy
**Base image:** `dustynv/ros:jazzy-ros-base-r36.4.0-cu128-24.04`

---

## 1. Előfeltételek (egyszer kell, install.sh feladata)

### 1.1 Docker + NVIDIA container runtime
```bash
# Docker telepítve és futó NVIDIA runtime szükséges
docker run --rm --runtime=nvidia --gpus all ubuntu:22.04 nvidia-smi
# Ha ez hibázik, a NVIDIA container toolkit nincs telepítve
```

### 1.2 ZED SDK telepítése a HOSTON (tools-szal)
A hoston futó SDK szükséges a ZED Explorer és ZED Calibration eszközökhöz.
```bash
wget https://download.stereolabs.com/zedsdk/5.2/l4t36.4/jetsons -O /tmp/zed_sdk.run
chmod +x /tmp/zed_sdk.run
sudo /tmp/zed_sdk.run -- silent skip_od_module
# FONTOS: skip_tools NEM kell — az Explorer és Calibration tool szükséges
```

### 1.3 Qt5 könyvtárak (ZED Explorer futtatásához)
```bash
sudo apt-get install -y \
    libqt5network5 libqt5widgets5 libqt5gui5 libqt5core5a \
    libqt5opengl5 libqt5sql5 libqt5xml5 libturbojpeg
```

### 1.4 `zed` csoport hozzáadása a userhez
```bash
sudo usermod -aG zed $USER
# Újrabejelentkezés szükséges, vagy: newgrp zed
```

### 1.5 Host könyvtárak létrehozása (Docker volume-okhoz)
```bash
sudo mkdir -p /usr/local/zed/resources/
sudo mkdir -p /usr/local/zed/settings/
```

### 1.6 udev szabályok telepítése
```bash
make install-udev
# Ez a 99-zed.rules-t /etc/udev/rules.d/-ba másolja
# USB autosuspend kikapcsolva, jogosultságok beállítva
```

---

## 2. Kalibrációs fájl telepítése

**KRITIKUS:** A `calib.stereolabs.com` szerver **NEM tartalmazza** SN 98214176-ot.
A `ZED_Explorer --dc 98214176` is csak hibaüzenetet ad vissza.

### 2.1 Közelítő kalibrációs fájl (ebből a repoból)
```bash
sudo cp SN98214176.conf /usr/local/zed/settings/SN98214176.conf
sudo chown root:zed /usr/local/zed/settings/SN98214176.conf
sudo chmod 664 /usr/local/zed/settings/SN98214176.conf
```

**Tartalom:** ZED 2i gyári specifikáció szerinti becsült értékek (fx≈700px HD720-nál,
baseline=120mm). Nem pontos gyári kalibráció — a `self_calib: true` futásidőben korrigál.

### 2.2 Pontos kalibráció megszerzése (TODO)
Két opció a valódi gyári kalibráció megszerzéséhez:

**A) Stereolabs support:**
```
E-mail: support@stereolabs.com
Tárgy: Factory calibration file for ZED 2i SN 98214176
Tartalom: SN + vásárlási igazolás
```
Ők feltöltik az adatbázisba → `ZED_Explorer --dc 98214176` utána működik.

**B) ZED Calibration tool (helyszíni kalibráció):**
1. Állítsd le a Docker containert: `make down`
2. Nyomtasd ki a sakktáblát: 9×6 belső sarok, ~35-40mm négyzetek, A3 papír
3. Futtasd: `sg zed -c "/usr/local/zed/tools/ZED_Calibration"`
4. Kövesd az utasításokat (~1 perc)
5. Az eredmény: `/usr/local/zed/settings/SN98214176.conf`

---

## 3. Docker image build

```bash
make build
# ~20 perc, egyszer kell
# Build log: /tmp/zed-build.log
```

**FONTOS:** A build előtt a kamera ne legyen lefoglalva (nincs futó container).

---

## 4. Első indítás

```bash
make up
# Várj 6-8 percet az első indításnál!
# A TensorRT neural depth modell letöltődik és optimalizálódik (~500MB, ~6 perc)
# Csak egyszer kell — /usr/local/zed/resources/-ban marad

make logs
# Sikeres init: "Camera successfully opened" + "Video mode: HD1080@30"
```

---

## 5. USB port — KRITIKUS HARDVERES ISMERET

**A ZED 2i csak bizonyos USB3 porton működik a Jetson Orin Nano J401 kártyán.**

| Port | Kernel path | Állapot |
|------|-------------|---------|
| Működő port | `usb-3610000.usb-1.2` (`2-1.2`) | ✅ 30fps hiba nélkül |
| Hibás port | `usb-3610000.usb-1.4` (`2-1.4`) | ❌ EPROTO (-71) USB isochronous hiba |

**Ellenőrzés:**
```bash
lsusb -t | grep -A1 "2b03"
# Bus 02: ... Port 2: Dev X, Class=Video → 2-1.2 = jó port
sudo dmesg | grep "uvc.*2-1\." | tail -5
# Ha "Non-zero status (-71)" jelenik meg → rossz port, dugd át
```

**Ha az EPROTO hiba visszatér:**
1. Dugd át a kamerát a másik USB3 portra
2. `sudo dmesg | grep "uvc"` — nincs `-71` hiba = jó port

---

## 6. ZED Explorer (host-on futtatva)

Ha a Docker container fut, az Explorer nem tudja megnyitni a kamerát (EBUSY).
Mindig állítsd le a containert előtte:

```bash
make down
# Ezután:
DISPLAY=:0 XAUTHORITY=/home/eduard/.Xauthority sg zed -c "/usr/local/zed/tools/ZED_Explorer"
# Vagy a desktop shortcuton keresztül (jobb klikk → Allow Launching)
```

Desktop shortcutok:
- `/home/eduard/Desktop/ZED_Explorer.desktop`
- `/home/eduard/Desktop/ZED_Calibration.desktop`

---

## 7. Validáció

```bash
make validate    # depth Hz, rgb Hz, imu Hz, pointcloud Hz
make health      # /zed/zed_node/status/health topic
make topics      # összes ZED topic listája
```

Elvárt értékek:
| Topic | Hz |
|-------|-----|
| depth | ~22 Hz (NEURAL LIGHT módban) |
| IMU | ~100 Hz |
| pointcloud | ~2 Hz |

---

## 8. Hibaelhárítás

### "CAMERA STREAM FAILED TO START"
```bash
# 1. Ellenőrizd a USB portot:
sudo dmesg | grep "uvc.*Non-zero status" | tail -3
# Ha van -71 hiba → dugd át másik USB3 portra

# 2. Ellenőrizd, más nem foglalja-e a kamerát:
sudo lsof /dev/video0
# Ha ZED_Explorer vagy python3 van → állítsd le

# 3. Ellenőrizd a kalibrációs fájlt:
sudo cat /usr/local/zed/settings/SN98214176.conf | head -3
# Ha "ERROR : Serial number not found!" → töröld és másold vissza a repoból (lsd. 2.1)
```

### "CALIBRATION FILE NOT AVAILABLE"
```bash
# A kalibrációs fájl hiányzik vagy sérült
sudo ls /usr/local/zed/settings/
# Ha üres vagy "ERROR..."-t tartalmaz → 2.1 lépés
```

### Container EBUSY (video0 foglalt)
```bash
sudo lsof /dev/video0
sudo kill -9 <PID>
```

### TensorRT modell újraoptimalizálás (ha /usr/local/zed/resources/ elveszett)
```bash
# Az első make up automatikusan letölti és optimalizálja (~6 perc)
# Könyvtár újralétrehozása:
sudo mkdir -p /usr/local/zed/resources/
make up
```

---

## 9. Fájlok és könyvtárak összefoglaló

| Elérési út | Leírás | Tartalom |
|---|---|---|
| `Dockerfile` | Image build leírása | repo ✅ |
| `docker-compose.yml` | Futtatási konfig | repo ✅ |
| `zed_params.yaml` | ZED node paraméterek | repo ✅ |
| `99-zed.rules` | udev szabályok | repo ✅ |
| `SN98214176.conf` | Közelítő kalibrációs fájl | repo ✅ |
| `/usr/local/zed/settings/SN98214176.conf` | Aktív kalibrációs fájl | host volume |
| `/usr/local/zed/resources/` | TensorRT model cache (~500MB) | host volume |
| `/usr/local/zed/` | Host ZED SDK (tools) | manuális install |
| `/etc/udev/rules.d/99-zed.rules` | Telepített udev szabály | `make install-udev` |
