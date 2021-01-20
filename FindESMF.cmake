function(append_globbed_directories VAR)
	cmake_parse_arguments(ARGS
		"" 
		""
		"PATTERNS;PATHS" 
		${ARGN}
	)
	set(MATCHED_LIST "")
	foreach(PREFIX ${ARGS_PATHS})
        foreach(PATTERN ${ARGS_PATTERNS})
            if(IS_ABSOLUTE ${PREFIX})
                file(GLOB MATCHED ${PREFIX}/${PATTERN})
            else()
                file(GLOB MATCHED ${CMAKE_BINARY_DIR}/${PREFIX}/${PATTERN})
            endif()
            foreach(MATCHED_FILE ${MATCHED})
                get_filename_component(MATCHED_DIR ${MATCHED_FILE} DIRECTORY)
                list(APPEND MATCHED_LIST ${MATCHED_DIR})
            endforeach()
		endforeach()
    endforeach()
    if("${MATCHED_LIST}")
        list(REMOVE_DUPLICATES MATCHED_LIST)
	endif()
	list(APPEND ${VAR} ${MATCHED_LIST})
	set(${VAR} ${${VAR}} PARENT_SCOPE)
endfunction()

# Add globbed directories to CMAKE_PREFIX_PATH for upcoming find_paths
append_globbed_directories(CMAKE_PREFIX_PATH
	PATTERNS
		mod/mod*/*.*.*.*.*/esmf.mod
		lib/lib*/*.*.*.*.*/libesmf.a
	PATHS
		${CMAKE_PREFIX_PATH}
)

# Find the installed ESMF files
find_path(ESMF_HEADERS_DIR
	ESMC.h
	DOC "The path to the directory containing \"ESMC.h\"."
	PATH_SUFFIXES "include"
)

find_path(ESMF_MOD_DIR
	esmf.mod
	DOC "The path to the directory containing \"esmf.mod\"."
	PATH_SUFFIXES "mod" "include"
)

find_library(ESMF_LIBRARY
	libesmf.a
	DOC "The path to the directory containing \"libesmf.a\"."
	PATH_SUFFIXES "lib"
)

find_file(ESMF_MK_FILEPATH
	esmf.mk
	DOC "The path to \"esmf.mk\" in your ESMF installation."
	PATH_SUFFIXES "lib"
)

# Get ESMF's versions number
if(EXISTS ${ESMF_HEADERS_DIR}/ESMC_Macros.h)
	file(READ ${ESMF_HEADERS_DIR}/ESMC_Macros.h ESMC_MACROS)
	if("${ESMC_MACROS}" MATCHES "#define[ \t]+ESMF_VERSION_MAJOR[ \t]+([0-9]+)")
		set(ESMF_VERSION_MAJOR "${CMAKE_MATCH_1}")
	endif()
	if("${ESMC_MACROS}" MATCHES "#define[ \t]+ESMF_VERSION_MINOR[ \t]+([0-9]+)")
		set(ESMF_VERSION_MINOR "${CMAKE_MATCH_1}")
	endif()
	if("${ESMC_MACROS}" MATCHES "#define[ \t]+ESMF_VERSION_REVISION[ \t]+([0-9]+)")
		set(ESMF_VERSION_REVISION "${CMAKE_MATCH_1}")
	endif()
	set(ESMF_VERSION "${ESMF_VERSION_MAJOR}.${ESMF_VERSION_MINOR}.${ESMF_VERSION_REVISION}")
else()
	set(ESMF_VERSION "NOTFOUND")
endif()

# Determine extra link libraries for ESMF built with 3rd party support
if(EXISTS ${ESMF_MK_FILEPATH})
    file(READ ${ESMF_MK_FILEPATH} ESMF_MK)

   # Inspect ESMF_F90LINKLIBS to determine any extra extra link libraries that are needed
   string(REGEX MATCH "ESMF_F90LINKLIBS=[^\n]*" ESMF_F90LINKLIBS "${ESMF_MK}")                  # Get ESMF_F90LINKLIBS line
   set(ESMF_F90LINKLIBS "${ESMF_F90LINKLIBS}" CACHE INTERNAL "ESMF_F90LINKLIBS from esmf.mk")
   
   string(REGEX MATCHALL "-l[^ ]*" ESMF_F90LINKLIB_NAMES "${ESMF_F90LINKLIBS}")                 # Get list of libs
   string(REPLACE "-l" "" ESMF_F90LINKLIB_NAMES "${ESMF_F90LINKLIB_NAMES}")
   set(ESMF_F90LINKLIB_NAMES "${ESMF_F90LINKLIB_NAMES}" CACHE INTERNAL "ESMF link libraries from ESMF_F90LINKLIBS")

   # Remove link lib entries that we always link anyways
   set(ESMF_LINKLIBS_STD ${MPI_CXX_LIB_NAMES} stdc++ rt dl)
   list(REMOVE_ITEM ESMF_F90LINKLIB_NAMES ${ESMF_LINKLIBS_STD})
   set(ESMF_F90LINKLIBS_3RD_PARTY "${ESMF_F90LINKLIB_NAMES}" CACHE INTERNAL "ESMF link libraries for 3rd party extensions")

   # Find each link library in ESMF_F90LINKLIBS_3RD_PARTY
   set(ESMF_LINKLIB_3RD_PARTY_EXTRA_REQUIRED "")
   foreach(THIRD_PARTY_LIBNAME ${ESMF_F90LINKLIBS_3RD_PARTY})
      find_library(ESMF_3RD_PARTY_LINKLIB_${THIRD_PARTY_LIBNAME}     # name of cache variable
         ${THIRD_PARTY_LIBNAME}                                      # name of library 
         DOC "The path to ESMF 3rd partly link library ${THIRD_PARTY_LIBNAME}."
         PATH_SUFFIXES "lib"
      )
      list(APPEND ESMF_LINKLIB_3RD_PARTY_EXTRA_REQUIRED "ESMF_3RD_PARTY_LINKLIB_${THIRD_PARTY_LIBNAME}")
   endforeach()
endif()

# Throw an error if anything went wrong
find_package_handle_standard_args(ESMF 
	REQUIRED_VARS 
		ESMF_HEADERS_DIR 
		ESMF_MOD_DIR 
      ESMF_LIBRARY
      ${ESMF_LINKLIB_3RD_PARTY_EXTRA_REQUIRED}
	VERSION_VAR ESMF_VERSION
	FAIL_MESSAGE "${ESMF_ERRMSG}"
)

# Specify the other libraries that need to be linked for ESMF
find_package(NetCDF REQUIRED)
find_package(MPI REQUIRED)
execute_process (COMMAND ${CMAKE_CXX_COMPILER} --print-file-name=libstdc++.so OUTPUT_VARIABLE stdcxx OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process (COMMAND ${CMAKE_CXX_COMPILER} --print-file-name=libgcc.a OUTPUT_VARIABLE libgcc OUTPUT_STRIP_TRAILING_WHITESPACE)
set(ESMF_LIBRARIES ${ESMF_LIBRARY} ${NETCDF_LIBRARIES} ${MPI_Fortran_LIBRARIES} ${MPI_CXX_LIBRARIES} rt ${stdcxx} ${libgcc})
set(ESMF_INCLUDE_DIRS ${ESMF_HEADERS_DIR} ${ESMF_MOD_DIR})

# Check if ESMF is built with OpenMP. If so, link OpenMP
if(EXISTS ${ESMF_MK_FILEPATH})
    file(READ ${ESMF_MK_FILEPATH} ESMF_MK)
    string(REPLACE ";" "|" OpenMP_LIBNAME_PATTERNS "${OpenMP_CXX_FLAGS};${OpenMP_Fortran_FLAGS}")
    if(ESMF_MK MATCHES "ESMF_(F90|CXX)LINKOPTS *= *[^\n]*(${OpenMP_LIBNAME_PATTERNS})[^\n]*\n")
        list(APPEND ESMF_LIBRARIES ${OpenMP_CXX_FLAGS} ${OpenMP_Fortran_FLAGS})
    endif()
endif()

# Add all third party libraries
foreach(THIRD_PARTY_LIB ${ESMF_LINKLIB_3RD_PARTY_EXTRA_REQUIRED})
   list(APPEND ESMF_LIBRARIES ${${THIRD_PARTY_LIB}})
endforeach()

# Make an imported target for ESMF
if(NOT TARGET ESMF)
	add_library(ESMF STATIC IMPORTED)
	set_target_properties(ESMF PROPERTIES
		IMPORTED_LOCATION ${ESMF_LIBRARY}
	)
	target_link_libraries(ESMF 
		INTERFACE 
			${NETCDF_LIBRARIES} 
			${MPI_Fortran_LIBRARIES} ${MPI_CXX_LIBRARIES} 
			rt ${stdcxx} ${libgcc}
	)
	target_include_directories(ESMF INTERFACE ${ESMF_INCLUDE_DIRS})
endif()
