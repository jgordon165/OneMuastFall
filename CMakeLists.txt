cmake_minimum_required(VERSION 3.20)
project(OneMuastFall VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(OMF_TESTS "Build the test suite" ON)

# One static MSVC runtime for everything (SDL, Lua, libxmp and the engine), so
# releases need no Visual C++ redistributable and nothing mismatches at link.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

include(FetchContent)

# ---- Xbox 360 ------------------------------------------------------------------
# -DCMAKE_TOOLCHAIN_FILE=platform/xenon/toolchain.cmake builds for the console
# with LibXenon (onemustfall.elf32, run from XeLL). -DCMAKE_TOOLCHAIN_FILE=
# <xsdk>/cmake/xsdk.cmake (openpak/x360-sdk, which sets XSDK) builds a normal
# title: onemustfall.xex. -DOMF_XENON_SIM=ON builds the same SDL and layout
# on a PC, to test them without a console (platform/xenon/xenon_platform_sim.c).
# The same platform layer as Meguarace and Raptua.
option(OMF_XENON_SIM "Build the Xbox 360's SDL and layout on a PC, for testing" OFF)
if(OMF_XENON_TARGET OR OMF_XENON_SIM OR XSDK)
    set(OMF_XENON ON)
    set(OMF_TESTS OFF CACHE BOOL "" FORCE)
else()
    set(OMF_XENON OFF)
endif()

# ---- SDL2 (static) ---------------------------------------------------------
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON  CACHE BOOL "" FORCE)
set(SDL_TEST   OFF CACHE BOOL "" FORCE)
if(OMF_XENON)
    # Only SDL's sources: platform/xenon/sdl2_xenon.cmake builds them with the
    # Xbox 360 drivers.
    FetchContent_Declare(SDL2
        GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
        GIT_TAG        release-2.30.9
        GIT_SHALLOW    TRUE
        SOURCE_SUBDIR  sources-only)
    FetchContent_MakeAvailable(SDL2)
    set(SDL2_SRC ${sdl2_SOURCE_DIR})
    include(platform/xenon/sdl2_xenon.cmake)
else()
    FetchContent_Declare(SDL2
        GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
        GIT_TAG        release-2.30.9
        GIT_SHALLOW    TRUE)
    FetchContent_MakeAvailable(SDL2)
endif()
if(XSDK)
    # newlib's <limits.h> leaves LLONG_MAX out of C++ here, and Lua then refuses
    # 64-bit integers (luaconf.h); C sees it, so give C++ the same (as
    # platform/xenon/toolchain.cmake does for LibXenon).
    add_compile_definitions(
        $<$<COMPILE_LANGUAGE:CXX>:LLONG_MAX=__LONG_LONG_MAX__>
        "$<$<COMPILE_LANGUAGE:CXX>:LLONG_MIN=(-__LONG_LONG_MAX__-1LL)>"
        "$<$<COMPILE_LANGUAGE:CXX>:ULLONG_MAX=(__LONG_LONG_MAX__*2ULL+1ULL)>")
endif()

# ---- Lua 5.4 (built from source; upstream has no CMake) ---------------------
FetchContent_Declare(lua
    GIT_REPOSITORY https://github.com/lua/lua.git
    GIT_TAG        v5.4.7
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(lua)

file(GLOB LUA_SOURCES ${lua_SOURCE_DIR}/*.c)
list(FILTER LUA_SOURCES EXCLUDE REGEX ".*/(lua|luac|onelua|ltests)\\.c$")
add_library(lua_static STATIC ${LUA_SOURCES})
target_include_directories(lua_static PUBLIC ${lua_SOURCE_DIR})
set_target_properties(lua_static PROPERTIES LINKER_LANGUAGE C)
if(UNIX AND NOT APPLE)
    target_compile_definitions(lua_static PRIVATE LUA_USE_LINUX)
    target_link_libraries(lua_static PUBLIC m dl)
elseif(APPLE)
    target_compile_definitions(lua_static PRIVATE LUA_USE_MACOSX)
endif()
target_compile_options(lua_static PRIVATE $<IF:$<C_COMPILER_ID:MSVC>,/W0,-w>)

# ---- libxmp (MIT): plays the game's PSM music modules -----------------------
# Same library OpenOMF uses for the PSM songs. Pinned to a release tag.
set(BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC ON  CACHE BOOL "" FORCE)
set(LIBXMP_DOCS  OFF CACHE BOOL "" FORCE)
set(LIBXMP_DISABLE_DEPACKERS ON CACHE BOOL "" FORCE)
set(LIBXMP_DISABLE_PROWIZARD ON CACHE BOOL "" FORCE)
FetchContent_Declare(libxmp
    GIT_REPOSITORY https://github.com/libxmp/libxmp.git
    GIT_TAG        libxmp-4.6.3
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(libxmp)

# ---- Warnings ----------------------------------------------------------------
if(MSVC)
    set(OMF_WARN /W4 /permissive- /wd4100 /wd4244 /wd4267)
else()
    set(OMF_WARN -Wall -Wextra -Wno-unused-parameter)
endif()

# ---- Formats library: the original files' decoders, no SDL -----------------
add_library(omf_formats STATIC
    src/formats/reader.cpp
    src/formats/sprite.cpp
    src/formats/animation.cpp
    src/formats/bk.cpp
    src/formats/af.cpp
    src/formats/pic.cpp
    src/formats/sounds.cpp
    src/formats/language.cpp
    src/formats/font.cpp
    src/formats/altpal.cpp)
target_include_directories(omf_formats PUBLIC src)
target_compile_options(omf_formats PRIVATE ${OMF_WARN})

# ---- The game -------------------------------------------------------------------
add_executable(onemustfall WIN32
    src/main.cpp
    src/log.cpp
    src/vfs.cpp
    src/video.cpp
    src/audio.cpp
    src/input.cpp
    src/lua_api.cpp)
if(WIN32)
    target_sources(onemustfall PRIVATE res/onemustfall.rc)
endif()
target_compile_options(onemustfall PRIVATE ${OMF_WARN})
target_compile_definitions(onemustfall PRIVATE OMF_VERSION="${PROJECT_VERSION}")
target_link_libraries(onemustfall PRIVATE omf_formats lua_static SDL2::SDL2-static libxmp::xmp_static)
if(TARGET SDL2::SDL2main)
    target_link_libraries(onemustfall PRIVATE SDL2::SDL2main)
endif()
if(OMF_XENON)
    # Paths, controls and leaving laid out for the console (src/main.cpp,
    # src/input.cpp, src/lua_api.cpp).
    target_compile_definitions(onemustfall PRIVATE OMF_XENON_LAYOUT=1)
    target_include_directories(onemustfall PRIVATE ${CMAKE_SOURCE_DIR}/platform/xenon)
endif()
if(OMF_XENON_TARGET)
    # LibXenon and its FAT driver, then the .elf32 that XeLL loads.
    target_link_libraries(onemustfall PRIVATE -Wl,--start-group fat xenon m c stdc++ -Wl,--end-group)
    set_target_properties(onemustfall PROPERTIES SUFFIX ".elf")
    add_custom_command(TARGET onemustfall POST_BUILD
        COMMAND ${XENON_OBJCOPY} -O elf32-powerpc --adjust-vma 0x80000000
                $<TARGET_FILE:onemustfall> $<TARGET_FILE_DIR:onemustfall>/onemustfall.elf32
        COMMENT "onemustfall.elf32 for XeLL")
endif()
if(XSDK)
    # A normal title: xsdk links its start-up and library, then packs
    # onemustfall.xex. Its own title ID ("OMF2"), so Aurora keeps its art and
    # settings apart from other xsdk titles (xsdk's default ID is shared by
    # all of them): packs onemustfall.xex again after xsdk_add_xex's packing.
    xsdk_add_xex(onemustfall)
    add_custom_command(TARGET onemustfall POST_BUILD
        COMMAND python3 "${XSDK_ROOT}/tools/elf2xex.py" --title-id 4F4D4632
                "$<TARGET_FILE:onemustfall>" "$<TARGET_FILE_DIR:onemustfall>/onemustfall.xex"
        VERBATIM)
endif()

# Lua scripts are copied next to the executable (scripts/), where main.cpp
# looks for them by default; on every build, so script edits always land.
add_custom_target(onemustfall_scripts ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_SOURCE_DIR}/scripts $<TARGET_FILE_DIR:onemustfall>/scripts
    COMMENT "Copying Lua scripts")
add_dependencies(onemustfall_scripts onemustfall)

if(NOT OMF_XENON)
    install(TARGETS onemustfall RUNTIME DESTINATION .)
endif()
install(DIRECTORY scripts DESTINATION .)
install(FILES README.md LICENSE DESTINATION .)

# ---- Tests ----------------------------------------------------------------------
if(OMF_TESTS)
    enable_testing()
    add_executable(omf_tests tests/test_formats.cpp)
    target_link_libraries(omf_tests PRIVATE omf_formats)
    target_compile_options(omf_tests PRIVATE ${OMF_WARN})
    add_test(NAME formats COMMAND omf_tests)
    # With OMF_DATA set to a game folder, the tests also decode every original
    # file (CI has none, so there they only run the synthetic cases).

    # The game boots (headless) to its no-data screen without a game folder.
    add_test(NAME boot_nodata COMMAND onemustfall --data ${CMAKE_BINARY_DIR}/no-such-folder --frames 10
             --scripts ${CMAKE_SOURCE_DIR}/scripts)

    # With OMF_DATA set at configure time: every BK/AF animation through the
    # script player.
    if(DEFINED ENV{OMF_DATA})
        add_test(NAME smoke_data COMMAND onemustfall --data $ENV{OMF_DATA} --smoke
                 --scripts ${CMAKE_SOURCE_DIR}/scripts)
        # and a whole computer-vs-computer match, start to finish
        add_test(NAME fight_data COMMAND onemustfall --data $ENV{OMF_DATA} --fight --frames 30000
                 --scripts ${CMAKE_SOURCE_DIR}/scripts)
        set_tests_properties(fight_data PROPERTIES ENVIRONMENT "OMF_FIGHT=4,7,3,4,4"
                             PASS_REGULAR_EXPRESSION "fight over" FAIL_REGULAR_EXPRESSION "lua error")
    endif()

    add_executable(omf_luatest tests/luatest.cpp)
    target_link_libraries(omf_luatest PRIVATE lua_static)
    add_test(NAME lua COMMAND omf_luatest ${CMAKE_SOURCE_DIR}/scripts ${CMAKE_SOURCE_DIR}/tests/lua/main.lua)
endif()
