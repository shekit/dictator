cmake_minimum_required(VERSION 3.22.1)
project(whisper-jni)

find_library(log-lib log)

include(FetchContent)

# Disable whisper.cpp extras we don't need
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# Disable ggml backends not available on Android
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_SYCL OFF CACHE BOOL "" FORCE)
set(GGML_KOMPUTE OFF CACHE BOOL "" FORCE)
set(GGML_RPC OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    whisper
    GIT_REPOSITORY https://github.com/ggml-org/whisper.cpp.git
    GIT_TAG v1.7.3
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(whisper)

add_library(whisper-jni SHARED whisper-jni.cpp)
target_link_libraries(whisper-jni whisper ${log-lib})
target_include_directories(whisper-jni PRIVATE ${whisper_SOURCE_DIR}/include)
