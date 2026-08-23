# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file LICENSE.rst or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION ${CMAKE_VERSION}) # this file comes with cmake

# If CMAKE_DISABLE_SOURCE_CHANGES is set to true and the source directory is an
# existing directory in our source tree, calling file(MAKE_DIRECTORY) on it
# would cause a fatal error, even though it would be a no-op.
if(NOT EXISTS "C:/ncs/v3.4.0/modules/tee/tf-m/trusted-firmware-m")
  file(MAKE_DIRECTORY "C:/ncs/v3.4.0/modules/tee/tf-m/trusted-firmware-m")
endif()
file(MAKE_DIRECTORY
  "E:/Coding/LightningDetector/Firmware/build/Firmware/tfm"
  "E:/Coding/LightningDetector/Firmware/build/Firmware/modules/trusted-firmware-m/tfm-prefix"
  "E:/Coding/LightningDetector/Firmware/build/Firmware/modules/trusted-firmware-m/tfm-prefix/tmp"
  "E:/Coding/LightningDetector/Firmware/build/Firmware/modules/trusted-firmware-m/tfm-prefix/src/tfm-stamp"
  "E:/Coding/LightningDetector/Firmware/build/Firmware/modules/trusted-firmware-m/tfm-prefix/src"
  "E:/Coding/LightningDetector/Firmware/build/Firmware/modules/trusted-firmware-m/tfm-prefix/src/tfm-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "E:/Coding/LightningDetector/Firmware/build/Firmware/modules/trusted-firmware-m/tfm-prefix/src/tfm-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "E:/Coding/LightningDetector/Firmware/build/Firmware/modules/trusted-firmware-m/tfm-prefix/src/tfm-stamp${cfgdir}") # cfgdir has leading slash
endif()
