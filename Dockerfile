FROM dustynv/ros:jazzy-ros-base-r36.4.0-cu128-24.04
# =============================================================================
# ZED 2i Docker Image — Talicska Robot
# =============================================================================
#
# Alap image: dustynv/ros:jazzy-ros-base-r36.4.0 (azonos a főstackkel)
# Platform:   Jetson Orin Nano, L4T R36.4.3 (JetPack 6.2), ARM64
#
# Ez a Dockerfile:
#   1. ZED SDK 5.x telepítése (Stereolabs Jetson silent installer)
#   2. zed_ros2_wrapper + zed_interfaces colcon build
#
# dustynv-specifikus workaround-ok (ugyanazok mint RealSense Dockerfile-ban):
#   - ROS2 PATH: /opt/ros/jazzy/install/bin/ros2
#   - CMAKE_PREFIX_PATH: /opt/ros/jazzy
#   - setup script: /opt/ros/jazzy/setup.bash
#
# Build: docker compose build  (~20 perc, egyszer kell)
# =============================================================================

# ZED SDK 5.x — Jetson L4T R36.4 (JetPack 6.2)
# Silent install: GUI, interaktív prompts kihagyva
# skip_tools:     ZED Explorer/Diagnostic tools kihagyva (nincs display)
# skip_od_module: Object detection neural model kihagyva (első futáskor tölti le)
#                 A modellek /usr/local/zed/resources/-ben tárolódnak (host-mounted volume)
ARG ZED_SDK_URL=https://download.stereolabs.com/zedsdk/5.0/l4t36.4/jetsons

# ROS2 apt kulcs frissítése — dustynv base-ben lejárt (EXPKEYSIG F42ED6FBAB17C654)
# Azonos workaround mint realsense-jetson/Dockerfile-ban
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        wget \
        zstd \
        libgomp1 \
        libopenblas-dev \
        python3-colcon-common-extensions \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "${ZED_SDK_URL}" -O /tmp/zed_sdk.run \
    && chmod +x /tmp/zed_sdk.run \
    && /tmp/zed_sdk.run -- silent skip_tools skip_od_module \
    && rm -f /tmp/zed_sdk.run

# ZED SDK library path beállítás
ENV LD_LIBRARY_PATH=/usr/local/zed/lib:${LD_LIBRARY_PATH}
ENV ZED_SDK_ROOT=/usr/local/zed
ENV PATH=/usr/local/zed/tools:${PATH}

# zed_ros2_wrapper + zed_interfaces
# Tartalmaz: zed_wrapper (launch, params), zed_interfaces (custom msgs: skeleton, health)
#
# dustynv workaround: CMAKE_PREFIX_PATH=/opt/ros/jazzy szükséges, mert
# a setup.sh nem adja hozzá az apt prefix-et automatikusan (dustynv-specifikus).
RUN mkdir -p /opt/zed_ws/src \
    && cd /opt/zed_ws/src \
    && git clone --branch master --depth 1 \
        https://github.com/stereolabs/zed-ros2-wrapper.git \
    && cd /opt/zed_ws \
    && . /opt/ros/jazzy/setup.bash \
    && rosdep update \
    && rosdep install --from-paths src --ignore-src -r -y \
    && colcon build \
        --packages-select zed_interfaces zed_components zed_wrapper zed_ros2_wrapper \
        --cmake-args \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_PREFIX_PATH="/opt/ros/jazzy" \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /opt/zed_ws/log /opt/zed_ws/build \
    && rm -rf /opt/zed_ws/src/zed-ros2-wrapper

# PATH beállítás — dustynv workaround (ros2 CLI: install/bin alatt van)
ENV PATH=/opt/ros/jazzy/install/bin:/opt/ros/jazzy/bin:${PATH}

CMD ["/bin/bash", "-c", \
     "source /opt/ros/jazzy/setup.bash && \
      source /opt/zed_ws/install/setup.bash && \
      export CYCLONEDDS_URI=file:///root/talicska-robot/cyclonedds.xml && \
      ros2 launch zed_wrapper zed_camera.launch.py \
        camera_model:=zed2i \
        camera_name:=zed \
        node_name:=zed_node \
        config_path:=/config/zed_params.yaml \
        publish_imu_tf:=false"]
