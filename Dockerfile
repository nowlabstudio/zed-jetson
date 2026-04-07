FROM stereolabs/zed:5.2-runtime-l4t-r36.4
# =============================================================================
# ZED 2i Docker Image — Talicska Robot
# =============================================================================
#
# Platform: Jetson Orin Nano, L4T R36.4.3 (JetPack 6.2), ARM64
#
# Base: stereolabs/zed:5.2-runtime-l4t-r36.4
#   - ZED SDK 5.2 pre-installálva
#   - Standard Ubuntu 22.04 base (nem dustynv)
#   - Normál apt prefix: /opt/ros/jazzy/
#   - Nincs dustynv workaround szükséges
#
# Build: make build (~20 perc, egyszer kell)
# =============================================================================

ENV DEBIAN_FRONTEND=noninteractive

# ── 1. ROS2 Jazzy apt telepítés ───────────────────────────────────────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        gnupg2 \
        lsb-release \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
        http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/ros2.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        cmake \
        build-essential \
        pkg-config \
        python3-colcon-common-extensions \
        nlohmann-json3-dev \
        libeigen3-dev \
        libgeographiclib-dev \
        ros-jazzy-ros-base \
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
        ros-jazzy-robot-localization \
        ros-jazzy-rosidl-default-generators \
        ros-jazzy-rosidl-default-runtime \
    && rm -rf /var/lib/apt/lists/*

# ── 2. zed_ros2_wrapper colcon build ──────────────────────────────────────────
# zed_msgs: stereolabs/zed-ros2-interfaces (külön repó)
# zed_description: stereolabs/zed-ros2-description (külön repó)
# zed-ros2-wrapper v5.2.2: zed_components + zed_wrapper
# Build sorrend: zed_msgs + zed_description → zed_components + zed_wrapper
RUN mkdir -p /opt/zed_ws/src \
    && cd /opt/zed_ws/src \
    && git clone --branch master --depth 1 \
        https://github.com/stereolabs/zed-ros2-interfaces.git \
    && git clone --branch main --depth 1 \
        https://github.com/stereolabs/zed-ros2-description.git \
    && git clone --branch v5.2.2 --depth 1 \
        https://github.com/stereolabs/zed-ros2-wrapper.git \
    && cd /opt/zed_ws \
    && . /opt/ros/jazzy/setup.sh \
    && colcon build \
        --packages-select zed_msgs zed_description \
        --cmake-args -DCMAKE_BUILD_TYPE=Release \
    && . /opt/zed_ws/install/setup.sh \
    && colcon build \
        --packages-select zed_components zed_wrapper \
        --cmake-args -DCMAKE_BUILD_TYPE=Release \
    && rm -rf /opt/zed_ws/log /opt/zed_ws/build \
    && rm -rf /opt/zed_ws/src

ENV ZED_SDK_ROOT=/usr/local/zed
ENV PATH=/usr/local/zed/tools:${PATH}

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
