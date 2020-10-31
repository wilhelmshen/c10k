#include <pthread.h>
#include <Python.h>
#include "C10kPthread.h"
// #include "C10kSocket.h"

static int volatile libc10k_initialized = 0;
static int volatile libc10k_finalized   = 0;

PyObject *pC10kPthreadModule = NULL;
// PyObject *pC10kSocketModule  = NULL;

void libc10k__init__()
{
    if (libc10k_initialized)
        return;
    if (PyImport_AppendInittab( "c10k.C10kPthread",
                               PyInit_C10kPthread) == -1) {
        errno = 1;
        perror("could not extend in-built modules table");
        exit(errno);
    }
    /* if (PyImport_AppendInittab( "c10k.C10kSocket",
                               PyInit_C10kSocket) == -1) {
        errno = 1;
        perror("could not extend in-built modules table");
        exit(errno);
    } */
    Py_Initialize();
    pC10kPthreadModule = PyImport_ImportModule("c10k.C10kPthread");
    if (NULL == pC10kPthreadModule) {
        errno = 2;
        perror("c10k.C10kPthread");
        exit(errno);
    } else {
        C10kPthread_initialized = 1;
    }
    /* pC10kSocketModule = PyImport_ImportModule("c10k.C10kSocket");
    if (NULL == pC10kSocketModule) {
        errno = 2;
        perror("c10k.C10kSocket");
        exit(errno);
    } else {
        C10kSocket_initialized = 1;
    } */
    libc10k_initialized = 1;
}

void libc10k__fini__()
{
    if (libc10k_finalized)
        return;
    Py_XDECREF(pC10kPthreadModule);
    // Py_XDECREF(pC10kSocketModule);
    if (Py_FinalizeEx() < 0) {
        exit(120);
    }
    libc10k_finalized = 1;
}
