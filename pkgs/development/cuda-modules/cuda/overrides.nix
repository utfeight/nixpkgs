{cudaVersion, lib}:
let
  inherit (lib) attrsets lists strings;
  # cudaVersionOlder : Version -> Boolean
  cudaVersionOlder = strings.versionOlder cudaVersion;
  # cudaVersionAtLeast : Version -> Boolean
  cudaVersionAtLeast = strings.versionAtLeast cudaVersion;

  addBuildInputs =
    drv: buildInputs:
    drv.overrideAttrs (prevAttrs: {buildInputs = prevAttrs.buildInputs ++ buildInputs;});
in
# NOTE: Filter out attributes that are not present in the previous version of
# the package set. This is necessary to prevent the appearance of attributes
# like `cuda_nvcc` in `cudaPackages_10_0, which predates redistributables.
final: prev:
attrsets.filterAttrs (attr: _: (builtins.hasAttr attr prev)) {
  libcufile = prev.libcufile.overrideAttrs (
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        final.libcublas.lib
        final.pkgs.numactl
        final.pkgs.rdma-core
      ];
      # Before 11.7 libcufile depends on itself for some reason.
      env.autoPatchelfIgnoreMissingDeps =
        prevAttrs.env.autoPatchelfIgnoreMissingDeps
        + strings.optionalString (cudaVersionOlder "11.7") " libcufile.so.0";
    }
  );

  libcusolver = addBuildInputs prev.libcusolver (
    # Always depends on this
    [final.libcublas.lib]
    # Dependency from 12.0 and on
    ++ lists.optionals (cudaVersionAtLeast "12.0") [final.libnvjitlink.lib]
    # Dependency from 12.1 and on
    ++ lists.optionals (cudaVersionAtLeast "12.1") [final.libcusparse.lib]
  );

  libcusparse = addBuildInputs prev.libcusparse (
    lists.optionals (cudaVersionAtLeast "12.0") [final.libnvjitlink.lib]
  );

  cuda_compat = prev.cuda_compat.overrideAttrs (
    prevAttrs: {
      env.autoPatchelfIgnoreMissingDeps =
        prevAttrs.env.autoPatchelfIgnoreMissingDeps + " libnvrm_gpu.so libnvrm_mem.so";
      # `cuda_compat` only works on aarch64-linux, and only when building for Jetson devices.
      brokenConditions = prevAttrs.brokenConditions // {
        "Trying to use cuda_compat on aarch64-linux targeting non-Jetson devices" =
          !final.flags.isJetsonBuild;
      };
    }
  );

  cuda_gdb = addBuildInputs prev.cuda_gdb (
    # x86_64 only needs gmp from 12.0 and on
    lists.optionals (cudaVersionAtLeast "12.0") [final.pkgs.gmp]
  );

  cuda_nvcc = prev.cuda_nvcc.overrideAttrs (
    oldAttrs: {
      propagatedBuildInputs = [final.setupCudaHook];

      meta = (oldAttrs.meta or {}) // {
        mainProgram = "nvcc";
      };
    }
  );

  cuda_nvprof = prev.cuda_nvprof.overrideAttrs (
    prevAttrs: {buildInputs = prevAttrs.buildInputs ++ [final.cuda_cupti.lib];}
  );

  cuda_demo_suite = addBuildInputs prev.cuda_demo_suite [
    final.pkgs.freeglut
    final.pkgs.libGLU
    final.pkgs.libglvnd
    final.pkgs.mesa
    final.libcufft.lib
    final.libcurand.lib
  ];

  nsight_compute = prev.nsight_compute.overrideAttrs (
    prevAttrs: {
      nativeBuildInputs =
        prevAttrs.nativeBuildInputs
        ++ (
          if (strings.versionOlder prev.nsight_compute.version "2022.2.0") then
            [final.pkgs.qt5.wrapQtAppsHook]
          else
            [final.pkgs.qt6.wrapQtAppsHook]
        );
      buildInputs =
        prevAttrs.buildInputs
        ++ (
          if (strings.versionOlder prev.nsight_compute.version "2022.2.0") then
            [final.pkgs.qt5.qtwebview]
          else
            [final.pkgs.qt6.qtwebview]
        );
    }
  );

  nsight_systems = prev.nsight_systems.overrideAttrs (
    prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [final.pkgs.qt5.wrapQtAppsHook];
      buildInputs = prevAttrs.buildInputs ++ [
        final.pkgs.alsa-lib
        final.pkgs.e2fsprogs
        final.pkgs.nss
        final.pkgs.numactl
        final.pkgs.pulseaudio
        final.pkgs.wayland
        final.pkgs.xorg.libXcursor
        final.pkgs.xorg.libXdamage
        final.pkgs.xorg.libXrandr
        final.pkgs.xorg.libXtst
      ];
    }
  );

  nvidia_driver = prev.nvidia_driver.overrideAttrs {
    # No need to support this package as we have drivers already
    # in linuxPackages.
    meta.broken = true;
  };
}
