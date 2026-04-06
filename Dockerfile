FROM dustynv/ros:jazzy-ros-base-r36.4.0-cu128-24.04
# =============================================================================
# ZED 2i Docker Image — Talicska Robot
# =============================================================================
#
# Platform: Jetson Orin Nano, L4T R36.4.3 (JetPack 6.2), ARM64
#
# dustynv-specifikus workaround-ok (azonosak a realsense-jetson/Dockerfile-ban):
#   --force-overwrite: dustynv NVIDIA OpenCV 4.11 ↔ apt libopencv-*-dev 4.6 ütközés
#   CMAKE_PREFIX_PATH: /opt/ros/jazzy/install (dustynv forrásból buildelt ROS2)
#   setup script: /opt/ros/jazzy/install/setup.sh (nem /opt/ros/jazzy/setup.sh)
#   rosdep KIHAGYVA: rosdep apt hívások nem kezelik a --force-overwrite-ot
#                    → deps kézzel listázva, azonos elvek mint RealSense Dockerfile-ban
#
# Build: make build (~20 perc, egyszer kell)
# =============================================================================

ENV DEBIAN_FRONTEND=noninteractive

# ZED SDK 5.x — Jetson L4T R36.4 (JetPack 6.2)
# silent:         GUI, interaktív prompts kihagyva
# skip_tools:     ZED Explorer/Diagnostic tools (nincs display)
# skip_od_module: Object detection model kihagyva — /usr/local/zed/resources/ (host-mounted)
ARG ZED_SDK_URL=https://download.stereolabs.com/zedsdk/5.0/l4t36.4/jetsons

# ── 1. ROS2 apt kulcs + build függőségek ──────────────────────────────────────
# --force-overwrite: dustynv NVIDIA OpenCV 4.11 ↔ apt libopencv-*-dev 4.6 dpkg ütközés
# ROS2 apt key: EXPKEYSIG F42ED6FBAB17C654 a dustynv base-ben — frissítés szükséges
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
        libgeographiclib-dev \
    && apt-get install -y --no-install-recommends \
        ros-jazzy-robot-localization \
    && rm -rf /var/lib/apt/lists/*

# ── 2. ZED SDK telepítése ──────────────────────────────────────────────────────
RUN wget -q "${ZED_SDK_URL}" -O /tmp/zed_sdk.run \
    && chmod +x /tmp/zed_sdk.run \
    && /tmp/zed_sdk.run -- silent skip_tools skip_od_module \
    && rm -f /tmp/zed_sdk.run

ENV LD_LIBRARY_PATH=/usr/local/zed/lib:${LD_LIBRARY_PATH}
ENV ZED_SDK_ROOT=/usr/local/zed
ENV PATH=/usr/local/zed/tools:${PATH}

# ── 3. zed_ros2_wrapper colcon build ──────────────────────────────────────────
# rosdep KIHAGYVA — deps kézzel telepítve fent (--force-overwrite miatt)
# CMAKE_PREFIX_PATH: /opt/ros/jazzy/install (dustynv forrásból buildelt ROS2 prefix)
# zed_msgs: KÜLÖN repóban van (stereolabs/zed-ros2-interfaces) — előbb kell buildelni
# zed-ros2-wrapper v5.2.2 (Jazzy, 2026-04-01)
RUN mkdir -p /opt/zed_ws/src \
    && cd /opt/zed_ws/src \
    && git clone --branch master --depth 1 \
        https://github.com/stereolabs/zed-ros2-interfaces.git \
    && git clone --branch v5.2.2 --depth 1 \
        https://github.com/stereolabs/zed-ros2-wrapper.git \
    && cd /opt/zed_ws \
    && . /opt/ros/jazzy/install/setup.sh \
    && colcon build \
        --packages-select zed_msgs \
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
    && rm -rf /opt/zed_ws/src/zed-ros2-wrapper \
    && rm -rf /opt/zed_ws/src/zed-ros2-interfaces

# PATH — dustynv workaround (ros2 CLI: install/bin alatt van)
ENV PATH=/opt/ros/jazzy/install/bin:/opt/ros/jazzy/bin:${PATH}

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
