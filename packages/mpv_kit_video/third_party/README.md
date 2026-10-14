# Vendored third-party sources

Copied verbatim (C headers only) so the plugin builds offline and through
CocoaPods, which cannot download sources for path pods.

| Directory | Upstream | Tag | Archive sha256 | License |
|---|---|---|---|---|
| `vulkan-headers/` | https://github.com/KhronosGroup/Vulkan-Headers | vulkan-sdk-1.4.363.0 | 4a078be12bef21cfebc09d878b77a63cff9d68f899254a0b00d0e37ef73e7f7e | Apache-2.0 OR MIT |
| `volk/` | https://github.com/zeux/volk | vulkan-sdk-1.4.363.0 | 1547d8d74395d4048fb3f4a6313da56db626e89b55db238d0d7e8944c8a645f3 | MIT |

To update: download both archives at the same SDK tag, verify the sha256,
copy `include/vulkan/*.h`, `include/vk_video/` and `volk.{c,h}`, and update
this table.
