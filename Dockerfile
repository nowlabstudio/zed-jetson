FROM dustynv/ros:jazzy-ros-base-r36.4.0-cu128-24.04
# =============================================================================
# ZED 2i Docker Image — Talicska Robot
# =============================================================================
#
# Platform: Jetson Orin Nano, L4T R36.4.3 (JetPack 6.2), ARM64
#
# Base: dustynv/ros:jazzy-ros-base-r36.4.0-cu128-24.04
#   Ubuntu 24.04, ROS2 Jazzy forrásból építve, CUDA 12.8
#   (Stereolabs base nem használható: Ubuntu 22.04 → ros-jazzy apt nem elérhető)
#
# dustynv kettős-prefix workaround-ok:
#   Forrásból épített ROS2 prefix: /opt/ros/jazzy/install/
#   Apt-ból telepített ros-jazzy-* prefix: /opt/ros/jazzy/
#   → PATH, PYTHONPATH, LD_LIBRARY_PATH, AMENT_PREFIX_PATH mind kiegészítve
#
#   --force-overwrite: dustynv NVIDIA OpenCV 4.11 ↔ apt libopencv-*-dev 4.6 ütközés
#   ROS2 apt key: EXPKEYSIG F42ED6FBAB17C654 → ros.key frissítés szükséges
#   xacro: apt entry_point script javítva (importlib.metadata dist-info hiányzik)
#
# Build: make build (~20 perc, egyszer kell)
# =============================================================================

ENV DEBIAN_FRONTEND=noninteractive

# ── 1. ROS2 apt kulcs + build függőségek ──────────────────────────────────────
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && apt-get update \
    && apt-get -o Dpkg::Options::="--force-overwrite" \
        install -y --no-install-recommends \
        wget \
        zstd \
        libgomp1 \
        libopenblas-dev \
        git \
        cmake \
        build-essential \
        pkg-config \
        python3-colcon-common-extensions \
        nlohmann-json3-dev \
        libeigen3-dev \
        ros-jazzy-rosidl-default-generators \
        ros-jazzy-rosidl-default-runtime \
        ros-jazzy-cv-bridge \
        ros-jazzy-image-transport \
        ros-jazzy-image-transport-plugins \
        ros-jazzy-diagnostic-updater \
        ros-jazzy-diagnostic-msgs \
        ros-jazzy-launch-ros \
        ros-jazzy-lifecycle-msgs \
        ros-jazzy-rclcpp-components \
        ros-jazzy-rclcpp-lifecycle \
        ros-jazzy-std-srvs \
        ros-jazzy-tf2-ros \
        ros-jazzy-tf2-geometry-msgs \
        ros-jazzy-nav-msgs \
        ros-jazzy-sensor-msgs \
        ros-jazzy-geometry-msgs \
        ros-jazzy-geographic-msgs \
        ros-jazzy-nmea-msgs \
        ros-jazzy-message-filters \
        ros-jazzy-angles \
        ros-jazzy-tf2-eigen \
        ros-jazzy-rmw-cyclonedds-cpp \
        ros-jazzy-backward-ros \
        ros-jazzy-stereo-msgs \
        ros-jazzy-visualization-msgs \
        ros-jazzy-shape-msgs \
        ros-jazzy-rosgraph-msgs \
        ros-jazzy-point-cloud-transport \
        ros-jazzy-xacro \
        libgeographiclib-dev \
    && apt-get install -y --no-install-recommends \
        ros-jazzy-robot-localization \
    && rm -rf /var/lib/apt/lists/*

# xacro workaround: apt entry_point script importlib.metadata-t hív,
# ami nem találja a dist-info-t. Közvetlen Python hívással helyettesítjük.
RUN printf '#!/usr/bin/env python3\nimport sys\nfrom xacro import main\nsys.exit(main())\n' \
    > /opt/ros/jazzy/bin/xacro && chmod +x /opt/ros/jazzy/bin/xacro

# ── 2. ZED SDK telepítése ──────────────────────────────────────────────────────
# ZED SDK 5.2 (→ 5.2.3): zed-ros2-wrapper v5.2.2 API-val kompatibilis
# silent: GUI/interaktív prompts kihagyva
# skip_tools: ZED Explorer/Diagnostic (nincs display)
# skip_od_module: Object detection model kihagyva (/usr/local/zed/resources/ host-mounted)
ARG ZED_SDK_URL=https://download.stereolabs.com/zedsdk/5.2/l4t36.4/jetsons
RUN wget -q "${ZED_SDK_URL}" -O /tmp/zed_sdk.run \
    && chmod +x /tmp/zed_sdk.run \
    && /tmp/zed_sdk.run -- silent skip_tools skip_od_module \
    && rm -f /tmp/zed_sdk.run

# ── 3. dustynv kettős-prefix ENV fix-ek ───────────────────────────────────────
# Apt ros-jazzy-* csomagok /opt/ros/jazzy/-be kerülnek,
# dustynv setup.sh csak az install/ prefixet regisztrálja.

# ZED SDK lib
ENV LD_LIBRARY_PATH=/usr/local/zed/lib:/opt/ros/jazzy/lib:${LD_LIBRARY_PATH}
ENV ZED_SDK_ROOT=/usr/local/zed
ENV PATH=/usr/local/zed/tools:/opt/ros/jazzy/install/bin:/opt/ros/jazzy/bin:${PATH}

# Python: apt ros csomagok site-packages-ba kerülnek
ENV PYTHONPATH=/opt/ros/jazzy/lib/python3.12/site-packages:${PYTHONPATH}

# Ament: apt ros csomagok /opt/ros/jazzy/ prefixben vannak
ENV AMENT_PREFIX_PATH=/opt/ros/jazzy:${AMENT_PREFIX_PATH}

# ── 4. zed_ros2_wrapper colcon build ──────────────────────────────────────────
# Három külön Stereolabs repó (5.x architektúra):
#   zed-ros2-interfaces  (branch: master) → zed_msgs
#   zed-ros2-description (branch: main)   → zed_description
#   zed-ros2-wrapper     (tag: v5.2.2)    → zed_components, zed_wrapper
# Build sorrend: zed_msgs + zed_description → zed_components + zed_wrapper
# CMAKE_PREFIX_PATH: mindkét dustynv prefix szükséges
RUN mkdir -p /opt/zed_ws/src \
    && cd /opt/zed_ws/src \
    && git clone --branch master --depth 1 \
        https://github.com/stereolabs/zed-ros2-interfaces.git \
    && git clone --branch main --depth 1 \
        https://github.com/stereolabs/zed-ros2-description.git \
    && git clone --branch v5.2.2 --depth 1 \
        https://github.com/stereolabs/zed-ros2-wrapper.git \
    && cd /opt/zed_ws \
    && . /opt/ros/jazzy/install/setup.sh \
    && colcon build \
        --packages-select zed_msgs zed_description \
        --cmake-args \
            -DCMAKE_BUILD_TYPE=Release \
            "-DCMAKE_PREFIX_PATH=/opt/ros/jazzy/install;/opt/ros/jazzy" \
    && . /opt/zed_ws/install/setup.sh \
    && colcon build \
        --packages-select zed_components zed_wrapper \
        --cmake-args \
            -DCMAKE_BUILD_TYPE=Release \
            "-DCMAKE_PREFIX_PATH=/opt/ros/jazzy/install;/opt/ros/jazzy" \
    && rm -rf /opt/zed_ws/log /opt/zed_ws/build \
    && rm -rf /opt/zed_ws/src

CMD ["/bin/bash", "-c", \
     "source /opt/ros/jazzy/install/setup.bash && \
      source /opt/zed_ws/install/setup.bash && \
      export CYCLONEDDS_URI=file:///root/talicska-robot/cyclonedds.xml && \
      ros2 launch zed_wrapper zed_camera.launch.py \
        camera_model:=zed2i \
        camera_name:=zed \
        node_name:=zed_node \
        config_path:=/config/zed_params.yaml \
        publish_imu_tf:=false"]
