# coding:      utf-8
# cython: language_level=3

cimport libc.stdio
cimport libc.stdlib
cimport posix.dlfcn

cdef extern from '<dlfcn.h>':

    # If the first argument of `dlsym' or `dlvsym' is set to RTLD_NEXT
    # the run-time address of the symbol called NAME in the next shared
    # object is returned.  The "next" relation is defined by the order
    # the shared objects were loaded.
    void *RTLD_NEXT  # ((void *) -1l)

cdef public int C10kSocket_initialized = 0

cdef void* load_sym(char *symname, void *proxyfunc) nogil:
    cdef void *funcptr = posix.dlfcn.dlsym(RTLD_NEXT, symname)
    if NULL == funcptr:
        libc.stdio.fprintf(
            libc.stdio.stderr,
            b'Cannot load symbol \'%s\' %s',
            symname,
            posix.dlfcn.dlerror()
        )
        libc.stdlib.exit(1)
    if proxyfunc == funcptr:
        libc.stdio.fprintf(
            libc.stdio.stderr,
            b'circular reference detected, aborting!\n'
        )
        libc.stdlib.abort()
    return funcptr
