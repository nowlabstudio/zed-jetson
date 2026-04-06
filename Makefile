SHELL := /bin/bash

.PHONY: build up down restart logs shell validate \
        depth-hz rgb-hz imu-hz pointcloud-hz \
        body-enable body-disable tf-check health \
        mapping-enable mapping-disable mapping-save \
        save-pcd install-udev setup-host topics

# ── ZED ROS2 shell helper ─────────────────────────────────────────────────────
ZED_ROS := source /opt/ros/jazzy/install/setup.bash && \
            source /opt/zed_ws/install/setup.bash && \
            export CYCLONEDDS_URI=file:///root/talicska-robot/cyclonedds.xml &&

# =============================================================================
# Docker lifecycle
# =============================================================================

## Docker image build (~20 perc, csak egyszer kell)
## Build log: /tmp/zed-build.log
build:
	sudo docker compose build 2>&1 | tee /tmp/zed-build.log
	@echo ""
	@echo "Build log: /tmp/zed-build.log"

## ZED container indítása
up:
	sudo docker compose up -d
	@echo "ZED container elindítva. Logs: make logs"

## ZED container leállítása
down:
	sudo docker compose stop

## ZED container újraindítása (pl. zed_params.yaml módosítás után)
restart:
	sudo docker compose restart ros2-zed

## Container logok (követés)
logs:
	sudo docker compose logs -f ros2-zed

## Bash shell a containerben (hibakereséshez)
shell:
	sudo docker compose exec ros2-zed bash

# =============================================================================
# Validáció — önálló kamera teszt
# =============================================================================

## Teljes validáció: logok + topic lista + Hz mérés
validate:
	@echo "── ZED 2i validáció ──"
	@echo ""
	@echo "1) Container logok (utolsó 20 sor):"
	@sudo docker compose logs --tail=20 ros2-zed
	@echo ""
	@echo "2) ZED topic lista:"
	@sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 topic list 2>/dev/null | grep -i zed || echo "NINCS ZED topic — kamera még nem indult?"'
	@echo ""
	@echo "3) Depth Hz (5s):"
	@sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) timeout 5 ros2 topic hz /zed/zed_node/depth/depth_registered --window 5 2>&1; true'
	@echo ""
	@echo "4) RGB Hz (5s):"
	@sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) timeout 5 ros2 topic hz /zed/zed_node/rgb/image_rect_color --window 5 2>&1; true'

## Mélységkép publikálási frekvencia
depth-hz:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 topic hz /zed/zed_node/depth/depth_registered --window 10'

## RGB kép publikálási frekvencia
rgb-hz:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 topic hz /zed/zed_node/rgb/image_rect_color --window 10'

## IMU frekvencia
imu-hz:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 topic hz /zed/zed_node/imu/data --window 10'

## Pontfelhő frekvencia
pointcloud-hz:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 topic hz /zed/zed_node/point_cloud/cloud_registered --window 10'

## Összes elérhető topic
topics:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 topic list'

## Kamera egészségi állapot (egyszer)
health:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) timeout 5 ros2 topic echo /zed/zed_node/status/health --once 2>&1 || echo "health topic nem elérhető"'

## TF fa ellenőrzés — zed_camera_link látszik-e?
tf-check:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) timeout 5 ros2 run tf2_ros tf2_echo base_link zed_camera_link 2>&1 | head -15'

# =============================================================================
# Body tracking
# =============================================================================

## Body tracking bekapcsolása (FOLLOW módhoz)
## Figyelem: ~2-3 másodperces késleltetés amíg a neural model betöltődik
body-enable:
	@echo "Body tracking engedélyezése..."
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 param set /zed/zed_node body_tracking.body_trk_enabled true'

## Body tracking kikapcsolása
body-disable:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 param set /zed/zed_node body_tracking.body_trk_enabled false'

# =============================================================================
# 3D Mapping (Isaac Sim területi felvételhez)
# =============================================================================

## 3D mapping bekapcsolása — területi pontfelhő felvételhez (Isaac Sim scene)
mapping-enable:
	@echo "3D mapping engedélyezése..."
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 param set /zed/zed_node mapping.mapping_enabled true'

## 3D mapping kikapcsolása
mapping-disable:
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 param set /zed/zed_node mapping.mapping_enabled false'

## Térkép mentése (mapping-enable után)
mapping-save:
	@echo "Térkép mentése /tmp/zed_map.ply-ba..."
	sudo docker compose exec ros2-zed bash -c \
		'$(ZED_ROS) ros2 service call /zed/zed_node/save_3d_map zed_interfaces/srv/SaveMesh "{filename: \"/tmp/zed_map.ply\"}" 2>&1'

# =============================================================================
# Pointcloud felvétel (Isaac Sim előkészítés)
# =============================================================================

## Pointcloud mentése ros2 bag-be (Isaac Sim scene alapjához)
## A bag tartalmazza: point_cloud/cloud_registered + rgb/image_rect_color
## Konverzió .pcd-re: ros2 bag → pointcloud_to_pcd (jövőbeli lépés)
## Leállítás: Ctrl+C
save-pcd:
	@echo "Pointcloud felvétel indítása — leállítás: Ctrl+C"
	@echo "Mentési hely: ./zed_pointcloud_$(shell date +%Y%m%d_%H%M%S)/"
	ros2 bag record \
		/zed/zed_node/point_cloud/cloud_registered \
		/zed/zed_node/rgb/image_rect_color \
		-o ./zed_pointcloud_$(shell date +%Y%m%d_%H%M%S)

# =============================================================================
# Host setup
# =============================================================================

## udev rule telepítés (egyszer kell — bármely USB porthoz)
## ZED 2i automatikusan felismerhető lesz idVendor=2b03 alapján
install-udev:
	@echo "── ZED udev rule telepítés ──"
	sudo cp 99-zed.rules /etc/udev/rules.d/
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	@echo "Kész. ZED 2i bármely USB3 porton működik."

## Host előkészítés: TensorRT cache könyvtár létrehozása
## Szükséges a docker-compose.yml volume mount-hoz
setup-host:
	@echo "── Host könyvtárak létrehozása ──"
	sudo mkdir -p /usr/local/zed/resources/
	@echo "TensorRT cache könyvtár: /usr/local/zed/resources/ — kész."
	@echo "Első futáskor a ZED SDK neural modelleket tölt ide (~500MB)."
