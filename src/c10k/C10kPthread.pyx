# coding:      utf-8
# cython: language_level=3

cimport cpython.mem
cimport cpython.object
cimport cpython.ref
cimport cython
cimport libc.errno
cimport libc.stdint
cimport libc.stdio
cimport libc.stdlib
cimport posix.time
cimport posix.types
cimport posix.unistd

from pthread cimport *

cdef extern from '<errno.h>':

    enum:
        EDEADLK,    # 35  Resource deadlock would occur
        # for robust mutexes
        EOWNERDEAD  # 130 Owner died

cdef extern from '<Python.h>':

    cpython.object.PyObject* _PyObject_CallMethod  \
                             'PyObject_CallMethod' \
        (
            cpython.object.PyObject *,
            char *,
            ...
        ) nogil

cdef extern from '<greenlet/greenlet.h>':

    ctypedef struct PyGreenlet:

        char*  stack_start
        PyGreenlet* parent
        cpython.object.PyObject* run_info

    ctypedef class greenlet.greenlet [object PyGreenlet]:

        cdef greenlet parent
        cdef object run_info

    greenlet PyGreenlet_GetCurrent()

cdef extern from '_gevent_cgreenlet.h':

    ctypedef struct PyC10kGeventGreenlet:

        PyGreenlet __pyx_base
        void     * __pyx_vtab
        cpython.object.PyObject *value
        cpython.object.PyObject *args
        cpython.object.PyObject *kwargs
        cpython.object.PyObject *spawning_greenlet
        cpython.object.PyObject *spawning_stack
        cpython.object.PyObject *spawn_tree_locals
        cpython.object.PyObject *_links
        cpython.object.PyObject *_exc_info
        cpython.object.PyObject *_notifier
        cpython.object.PyObject *_start_event
        cpython.object.PyObject *_formatted_info
        cpython.object.PyObject *_ident

    ctypedef class gevent._greenlet.Greenlet [object PyC10kGeventGreenlet]:

        cdef object value
        cdef object args
        cdef object kwargs
        cdef object spawning_greenlet
        cdef object spawning_stack
        cdef object spawn_tree_locals
        cdef object _links
        cdef object _exc_info
        cdef object _notifier
        cdef object _start_event
        cdef object _formatted_info
        cdef object _ident

cdef extern from 'C10kPthread.h':

    cpython.object.PyObject* __pyx_empty_tuple
    cpython.object.PyObject* __Pyx_PyObject_CallOneArg \
        (
            cpython.object.PyObject *,
            cpython.object.PyObject *
        )

cdef public int C10kPthread_initialized = 0
cdef        int __concurrency = 0
cdef pthread_key_t  key_limbo = <pthread_key_t><libc.stdint.uintptr_t>0
cdef void *key_limbo_specific
cdef pthread_once_t ONCE_DONE = <pthread_once_t><unsigned int>-1
cdef pthread_t TH_MAIN = <pthread_t><libc.stdint.uintptr_t>0

###########################################################################

import sys
# TODO
#sys.setswitchinterval(0xffffffff)

import gevent.greenlet
# XXX
gevent.greenlet._cancelled_start_event = gevent.greenlet._dummy_event()
gevent.greenlet._start_completed_event = gevent.greenlet._dummy_event()

import gevent
import gevent.event
import gevent.local
import gevent.lock
import gevent.queue
import weakref

from gevent._greenlet import Greenlet

g_main    = gevent.getcurrent()
greenlets = \
    {
        <unsigned long><libc.stdint.uintptr_t>TH_MAIN            : g_main,
        <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g_main: g_main
    }
mutexes   = {}
rwlocks   = {}
conds     = {}
local     = gevent.local.local()
LOCAL_KEY = 'C10kPthreadKey'

###########################################################################

cdef class Attr:

    cdef int detachstate
    cdef size_t guardsize
    cdef sched_param schedparam
    cdef int schedpolicy
    cdef int inheritsched
    cdef int scope
    cdef void  *stackaddr
    cdef size_t stacksize

    cdef int init(self, const pthread_attr_t *attr):
        if NULL == attr:
            return self.set_default()
        else:
            return self.set(attr)

    cdef int set_default(self):
        cdef pthread_attr_t attr
        cdef int fail = pthread_attr_init(&attr)
        if fail:
            return fail
        return self.set(&attr)

    cdef int set(self, const pthread_attr_t *attr):
        cdef int fail
        fail = pthread_attr_getdetachstate(attr, &self.detachstate)
        if fail:
            return fail
        fail = pthread_attr_getguardsize(attr, &self.guardsize)
        if fail:
            return fail
        fail = pthread_attr_getschedparam(attr, &self.schedparam)
        if fail:
            return fail
        fail = pthread_attr_getschedpolicy(attr, &self.schedpolicy)
        if fail:
            return fail
        fail = pthread_attr_getinheritsched(attr, &self.inheritsched)
        if fail:
            return fail
        fail = pthread_attr_getscope(attr, &self.scope)
        if fail:
            return fail
        fail = \
            pthread_attr_getstack(
                attr,
                &self.stackaddr,
                &self.stacksize
            )
        if fail:
            return fail
        return 0

    cdef int get(self, pthread_attr_t *attr):
        cdef int fail
        fail = pthread_attr_setdetachstate(attr, self.detachstate)
        if fail:
            return fail
        fail = pthread_attr_setguardsize(attr, self.guardsize)
        if fail:
            return fail
        fail = pthread_attr_setschedparam(attr, &self.schedparam)
        if fail != 0:
            return fail
        fail = pthread_attr_setschedpolicy(attr, self.schedpolicy)
        if fail != 0:
            return fail
        fail = pthread_attr_setinheritsched(attr, self.inheritsched)
        if fail != 0:
            return fail
        fail = pthread_attr_setscope(attr, self.scope)
        if fail != 0:
            return fail
        fail = pthread_attr_setstack(attr, self.stackaddr, self.stacksize)
        if fail:
            return fail
        return 0

cdef class Thread:

    cdef bytes name
    cdef Attr  attr
    cdef int cancelstate
    cdef int canceltype
    cdef void *(*start_routine) (void *)
    cdef void *arg
    cdef void *retval

    cdef int init \
        (
            self,
            bytes name,
            Attr  attr,
            void  *(*start_routine) (void *),
            void  *arg
        ):
        self.name = name
        self.attr = attr
        self.cancelstate = PTHREAD_CANCEL_DISABLE
        self.canceltype  = PTHREAD_CANCEL_DEFERRED
        self.start_routine = start_routine
        self.arg = arg
        self.retval = NULL
        return 0

def run():
    g = <Greenlet?>gevent.getcurrent()
    if g._start_event is None:
        g._start_event = gevent.greenlet._cancelled_start_event
    g._start_event.stop()
    g._start_event.close()
    g._start_event = gevent.greenlet._start_completed_event
    t = <Thread?>g.args[0]
    cdef void *start_routine = t.start_routine
    cdef void *arg = t.arg
    del t
    del g
    cdef void *retval = (<void *(*) (void*)>start_routine)(arg)
    g   = <Greenlet?>gevent.getcurrent()
    t   = <Thread?>g.args[0]
    key = \
              <unsigned long>     \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>g
    t.retval = retval
    g._exc_info = (None, None, None)
    g.value = None
    if g._links and not g._notifier:
        g._notifier = (<greenlet>g) \
                    .    parent     \
                    .     loop      \
                    . run_callback(g._notify_links)
    del g.run
    g.args = ()
    g.kwargs.clear()
    del greenlets[key]

# Create a new thread, starting with execution of START-ROUTINE
# getting passed ARG.  Creation attributed come from ATTR.  The new
# handle is stored in *NEWTHREAD.
cdef public int pthread_create \
    (
        pthread_t *newthread,
        const pthread_attr_t *attr,
        void *(*start_routine) (void *),
        void *arg
    ):
    pAttr = Attr()
    cdef int fail = pAttr.init(attr)
    if fail:
        return fail
    t = Thread()
    g = Greenlet()
    t.init(g.name.encode(), pAttr, start_routine, arg)
    g.run  =  run
    g.args = (t, )
    g.start()
    key = \
              <unsigned long>     \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>g
    greenlets[key] = g
    newthread[0] = \
                <pthread_t>       \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>g
    return 0

# Terminate calling thread.
#
# The registered cleanup handlers are called via exception handling
# so we cannot mark this function with __THROW.
cdef public void pthread_exit(void *retval):
    g = gevent.getcurrent()
    cdef pthread_t th = \
                <pthread_t>       \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>g
    del g
    __cancel(th, retval)

cdef void __cancel(pthread_t th, void *retval):
    key = <unsigned long><libc.stdint.uintptr_t>th
    g   = <Greenlet?>greenlets[key]
    t   = <Thread?>g.args[0]
    if retval != NULL:
        t.retval = retval
    g._exc_info = (None, None, None)
    g.value = None
    if g._links and not g._notifier:
        g._notifier = (<greenlet>g) \
                    .    parent     \
                    .     loop      \
                    . run_callback(g._notify_links)
    g.args = ()
    g.kwargs.clear()
    del g.run
    del greenlets[key]
    del t
    del key
    cdef cpython.object.PyObject *pMyHub = \
        <cpython.object.PyObject*>(<greenlet>g).parent
    (<PyGreenlet*>g).stack_start = NULL
    del g
    # XXX
    _PyObject_CallMethod(pMyHub, b'switch', NULL)

# Make calling thread wait for termination of the thread TH.  The
# exit status of the thread is stored in *THREAD_RETURN, if THREAD_RETURN
# is not NULL.
#
# This function is a cancellation point and therefore not marked with
# __THROW.
cdef public int pthread_join(pthread_t th, void **thread_return):
    key = <unsigned long><libc.stdint.uintptr_t>th
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    if t.attr.detachstate != PTHREAD_CREATE_JOINABLE:
        return libc.errno.EINVAL
    g.join()
    if thread_return != NULL:
        thread_return = &t.retval
    return 0

# Check whether thread TH has terminated.  If yes return the status of
# the thread in *THREAD_RETURN, if THREAD_RETURN is not NULL.
cdef public int pthread_tryjoin_np(pthread_t th, void **thread_return):
    key = <unsigned long><libc.stdint.uintptr_t>th
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    if t.attr.detachstate != PTHREAD_CREATE_JOINABLE:
        return libc.errno.EINVAL
    if g.ready():
        if thread_return != NULL:
            thread_return = &t.retval
        return 0
    else:
        return libc.errno.EBUSY

# Make calling thread wait for termination of the thread TH, but only
# until TIMEOUT.  The exit status of the thread is stored in
# *THREAD_RETURN, if THREAD_RETURN is not NULL.
#
# This function is a cancellation point and therefore not marked with
# __THROW.
cdef public int pthread_timedjoin_np \
    (
        pthread_t th,
        void **thread_return,
        const posix.time.timespec *abstime
    ):
    key = <unsigned long><libc.stdint.uintptr_t>th
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    if t.attr.detachstate != PTHREAD_CREATE_JOINABLE:
        return libc.errno.EINVAL
    g.join(timeout=<long>abstime.tv_sec)
    if g.ready():
        if thread_return != NULL:
            thread_return = &t.retval
        return 0
    else:
        return libc.errno.ETIMEDOUT

# Indicate that the thread TH is never to be joined with PTHREAD_JOIN.
# The resources of TH will therefore be freed immediately when it
# terminates, instead of waiting for another thread to perform PTHREAD_JOIN
# on it.
cdef public int pthread_detach(pthread_t th):
    key = <unsigned long><libc.stdint.uintptr_t>th
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    t.attr.detachstate = PTHREAD_CREATE_DETACHED
    return 0

# Obtain the identifier of the current thread.
cdef public pthread_t pthread_self():
    cdef pthread_t th
    if C10kPthread_initialized:
        g = gevent.getcurrent()
        if g is g_main:
            return TH_MAIN
        else:
            th = \
                        <pthread_t>       \
                  <libc.stdint.uintptr_t> \
                <cpython.object.PyObject*>g
            return th
    else:
        return TH_MAIN

# Compare two thread identifiers.
cdef public int pthread_equal(pthread_t thread1, pthread_t thread2):
    key1 = <unsigned long><libc.stdint.uintptr_t>thread1
    key2 = <unsigned long><libc.stdint.uintptr_t>thread2
    if key1 == key2:
        if key1 in greenlets:
            return 1
        else:
            return libc.errno.ESRCH
    else:
        if   key1 not in greenlets:
            return libc.errno.ESRCH
        elif key2 not in greenlets:
            return libc.errno.ESRCH
        else:
            return 0

###########################################################################
#                       Thread attribute handling.                        #
###########################################################################

# Initialize thread attribute *ATTR with attributes corresponding to the
# already running thread TH.  It shall be called on uninitialized ATTR
# and destroyed with pthread_attr_destroy when no longer needed.
cdef public int pthread_getattr_np(pthread_t th, pthread_attr_t *attr):
    key = <unsigned long><libc.stdint.uintptr_t>th
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    return t.attr.get(attr)

###########################################################################
#                    Functions for scheduling control.                    #
###########################################################################

# Set the scheduling parameters for TARGET_THREAD according to POLICY
# and *PARAM.
cdef public int pthread_setschedparam \
    (
        pthread_t target_thread,
        int policy,
        const sched_param *param
    ):
    key = <unsigned long><libc.stdint.uintptr_t>target_thread
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    t.schedpolicy = policy
    t.schedparam.sched_priority = param.sched_priority
    return 0

# Return in *POLICY and *PARAM the scheduling parameters for TARGET_THREAD.
cdef public int pthread_getschedparam \
    (
        pthread_t target_thread,
        int *policy,
        sched_param *param
    ):
    key = <unsigned long><libc.stdint.uintptr_t>target_thread
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    policy[0] = t.schedpolicy
    param.sched_priority = t.schedparam.sched_priority
    return 0

# Set the scheduling priority for TARGET_THREAD.
cdef public int pthread_setschedprio(pthread_t target_thread, int prio):
    key = <unsigned long><libc.stdint.uintptr_t>target_thread
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    t.schedparam.sched_priority = prio
    return 0

# Get thread name visible in the kernel and its interfaces.
cdef public int pthread_getname_np \
    (
        pthread_t target_thread,
        char *buf,
        size_t buflen
    ):
    key = <unsigned long><libc.stdint.uintptr_t>target_thread
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    if len(t.name) > buflen:
        return libc.errno.ERANGE
    name = t.name
    return 0

# Set thread name visible in the kernel and its interfaces.
cdef public int pthread_setname_np \
    (
        pthread_t target_thread,
        const char *name
    ):
    key = <unsigned long><libc.stdint.uintptr_t>target_thread
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    t.name = name
    return 0

# Determine level of concurrency.
cdef public int pthread_getconcurrency():
    return __concurrency

# Set new concurrency level to LEVEL.
cdef public int pthread_setconcurrency(int level):
    if level < 0:
        return libc.errno.EINVAL
    __concurrency = level
    return 0

# Yield the processor to another thread or process.
# This function is similar to the POSIX `sched_yield' function but
# might be differently implemented in the case of a m-on-n thread
# implementation.
cdef public int pthread_yield():
    gevent.idle()
    return 0

# XXX
#
# Limit specified thread TH to run only on the processors represented
# in CPUSET.
cdef public int pthread_setaffinity_np \
    (
        pthread_t th,
        size_t cpusetsize,
        const cpu_set_t *cpuset
    ):
    return libc.errno.ENOSYS

# XXX
#
# Get bit set in CPUSET representing the processors TH can run on.
cdef public int pthread_getaffinity_np \
    (
        pthread_t th,
        size_t cpusetsize,
        cpu_set_t *cpuset
    ):
    return libc.errno.ENOSYS

###########################################################################
#                  Functions for handling initialization.                 #
###########################################################################

# Guarantee that the initialization function INIT_ROUTINE will be called
# only once, even if pthread_once is executed several times with the
# same ONCE_CONTROL argument. ONCE_CONTROL must point to a static or
# extern variable initialized to PTHREAD_ONCE_INIT.
#
# The initialization functions might throw exception which is why
# this function is not marked with __THROW.
cdef public int pthread_once \
    (
        pthread_once_t *once_control,
        void (*init_routine) ()
    ):
    if PTHREAD_ONCE_INIT == once_control[0]:
        once_control[0] = ONCE_DONE
        init_routine()
        return 0
    else:
        return 0

###########################################################################
#                   Functions for handling cancellation.                  #
#
# Note that these functions are explicitly not marked to not throw an     #
# exception in C++ code.  If cancellation is implemented by unwinding     #
# this is necessary to have the compiler generate the unwind information. #
###########################################################################

# Set cancelability state of current thread to STATE, returning old
# state in *OLDSTATE if OLDSTATE is not NULL.
cdef public int pthread_setcancelstate(int state, int *oldstate):
    g   = gevent.getcurrent()
    key = <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g
    if key not in greenlets:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    oldstate[0]   = t.cancelstate
    t.cancelstate = state
    return 0

# Set cancellation state of current thread to TYPE, returning the old
# type in *OLDTYPE if OLDTYPE is not NULL.
cdef public int pthread_setcanceltype(int type_, int *oldtype):
    g   = gevent.getcurrent()
    key = <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    oldtype[0]   = t.canceltype
    t.canceltype = type_
    return 0

# Cancel THREAD immediately or at the next possibility.
cdef public int pthread_cancel(pthread_t th):
    key = <unsigned long><libc.stdint.uintptr_t>th
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    t.cancelstate = PTHREAD_CANCEL_ENABLE
    del t
    del g
    del key
    __cancel(th, PTHREAD_CANCELED)
    return 0

# Test for pending cancellation for the current thread and terminate
# the thread as per pthread_exit(PTHREAD_CANCELED) if it has been
# cancelled.
cdef public void pthread_testcancel():
    g   = gevent.getcurrent()
    key = <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g
    if key not in greenlets:
        return
    cdef pthread_t th = <pthread_t><libc.stdint.uintptr_t><PyGreenlet*>g
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return
    if PTHREAD_CANCEL_ENABLE != t.cancelstate:
        return
    del t
    del key
    del g
    __cancel(th, PTHREAD_CANCELED)

# XXX
cdef public int pthread_kill(pthread_t th, int sig):
    key = <unsigned long><libc.stdint.uintptr_t>th
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    return libc.errno.ENOSYS

###########################################################################
#                             Mutex handling.                             #
###########################################################################

cdef class MutexAttr:

    cdef int pshared
    cdef int kind
    cdef int protocol
    cdef int prioceiling
    cdef int robustness

    cdef int init(self, const pthread_mutexattr_t *attr):
        if NULL == attr:
            return self.set_default()
        else:
            return self.set(attr)

    cdef int set_default(self):
        cdef pthread_mutexattr_t attr
        cdef int fail
        fail = pthread_mutexattr_init(&attr)
        if fail:
            return fail
        return self.set(&attr)

    cdef int set(self, const pthread_mutexattr_t *attr):
        cdef int fail = pthread_mutexattr_getpshared(attr, &self.pshared)
        if fail:
            return fail
        fail = pthread_mutexattr_gettype(attr, &self.kind)
        if fail:
            return fail
        fail = pthread_mutexattr_getprotocol(attr, &self.protocol)
        if fail:
            return fail
        fail = \
            pthread_mutexattr_getprioceiling(
                attr,
                &self.prioceiling
            )
        if fail:
            return fail
        fail = pthread_mutexattr_getrobust(attr, &self.robustness)
        if fail:
            return fail
        return 0

    cdef int get(self, pthread_mutexattr_t *attr):
        cdef int fail = pthread_mutexattr_setpshared(attr, self.pshared)
        if fail:
            return fail
        fail = pthread_mutexattr_settype(attr, self.kind)
        if fail:
            return fail
        fail = pthread_mutexattr_setprotocol(attr, self.protocol)
        if fail:
            return fail
        fail = pthread_mutexattr_setprioceiling(attr, self.prioceiling)
        if fail:
            return fail
        fail = pthread_mutexattr_setrobust(attr, self.robustness)
        if fail:
            return fail
        return 0

cdef class Mutex:

    cdef MutexAttr attr
    cdef object  _block
    cdef object  _owner
    cdef object  _count
    cdef object __weakref__

    def __init__(self):
        self._block = gevent.lock.Semaphore(1)
        self._owner = None
        self._count = 0

    cdef int acquire(self, blocking, timeout):
        if self._owner is None:
            owner = None
        else:
            owner = self._owner()
            if owner is None or owner.ready():
                return EOWNERDEAD
        me = gevent.getcurrent()
        if owner is me:
            if   self.attr.kind == PTHREAD_MUTEX_RECURSIVE_NP:
                self._count = self._count + 1
                return 0
            elif self.attr.kind == PTHREAD_MUTEX_ERRORCHECK_NP:
                return EDEADLK
        rc = self._block.acquire(blocking, timeout)
        if rc:
            self._owner = weakref.ref(me)
            self._count = 1
            return 0
        else:
            if timeout is None:
                return libc.errno.EBUSY
            else:
                return libc.errno.ETIMEDOUT

    cdef int release(self):
        if self._owner is None:
            owner = None
        else:
            owner = self._owner()
        me   = gevent.getcurrent()
        attr = self.attr
        if owner is not me and \
           (
               attr.kind == PTHREAD_MUTEX_ERRORCHECK or \
               attr.kind == PTHREAD_MUTEX_RECURSIVE  or \
               attr.robustness
           ):
            return libc.errno.EPERM
        count = self._count - 1
        self._count = count
        if not count:
            self._owner = None
            self._block.release()

    cdef int cond_wait_check(self):
        if PTHREAD_MUTEX_ERRORCHECK == self.attr.kind or \
           self.attr.robustness:
            if self._owner is None:
                return EOWNERDEAD
            else:
                owner = self._owner()
                if owner is None:
                    return EOWNERDEAD
            me = gevent.getcurrent()
            if owner is not me:
                return libc.errno.EPERM
        return 0

# Initialize a mutex.
cdef public int pthread_mutex_init \
    (
        pthread_mutex_t *mutex,
        const pthread_mutexattr_t *mutexattr
    ):
    if not C10kPthread_initialized:
        (<libc.stdint.uintptr_t*>mutex)[0] = 0
        return 0
    pAttr = MutexAttr()
    cdef int fail = pAttr.init(mutexattr)
    if fail:
        return fail
    pMutex = Mutex()
    pMutex.attr = pAttr
    key = \
              <unsigned long>     \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pMutex
    mutexes[key] = pMutex
    (<libc.stdint.uintptr_t*>mutex)[0] = \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pMutex
    return 0

# Destroy a mutex.
cdef public int pthread_mutex_destroy(pthread_mutex_t *mutex):
    if 0 == (<libc.stdint.uintptr_t*>mutex)[0]:
        return 0
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        del mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    else:
        return 0

# Try locking a mutex.
cdef public int pthread_mutex_trylock(pthread_mutex_t *mutex):
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        pMutex = <Mutex?>mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    return pMutex.acquire(False, None)

# Lock a mutex.
cdef public int pthread_mutex_lock(pthread_mutex_t *mutex):
    if 0 == (<libc.stdint.uintptr_t*>mutex)[0]:
        return 0
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        pMutex = <Mutex?>mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    return pMutex.acquire(True, None)

# Wait until lock becomes available, or specified time passes.
cdef public int pthread_mutex_timedlock \
    (
        pthread_mutex_t *mutex,
        const posix.time.timespec *abstime
    ):
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        pMutex = <Mutex?>mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    return pMutex.acquire(True, <long>abstime.tv_sec)

# Unlock a mutex.
cdef public int pthread_mutex_unlock(pthread_mutex_t *mutex):
    if 0 == (<libc.stdint.uintptr_t*>mutex)[0]:
        return 0
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        pMutex = <Mutex?>mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    return pMutex.release()

# Get the priority ceiling of MUTEX.
cdef public int pthread_mutex_getprioceiling \
    (
        const pthread_mutex_t *mutex,
        int *prioceiling
    ):
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        pMutex = <Mutex?>mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    prioceiling[0] = pMutex.attr.prioceiling

# XXX
#
# Set the priority ceiling of MUTEX to PRIOCEILING, return old
# priority ceiling value in *OLD_CEILING.
cdef public int pthread_mutex_setprioceiling \
    (
        pthread_mutex_t *mutex,
        int  prioceiling,
        int *old_ceiling
    ):
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        pMutex = <Mutex?>mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    g = gevent.getcurrent()
    key = <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g
    try:
        g = greenlets[key]
    except KeyError:
        return libc.errno.ESRCH
    try:
        t = <Thread?>g.args[0]
    except TypeError:
        return libc.errno.ESRCH
    attr = pMutex.attr
    if   attr.protocol == PTHREAD_PRIO_NONE:
        return libc.errno.EINVAL
    elif attr.protocol == PTHREAD_PRIO_PROTECT and \
         t.schedparam.sched_priority > attr.prioceiling:
        return libc.errno.EINVAL
    cdef int fail = pMutex.acquire(True, None)
    if fail:
        return fail
    old_ceiling[0] = pMutex.attr.prioceiling
    pMutex.attr.prioceiling = prioceiling
    pMutex.release()
    return 0

# XXX
#
# Declare the state protected by MUTEX as consistent.
cdef public int pthread_mutex_consistent(pthread_mutex_t *mutex):
    key = <unsigned long>(<libc.stdint.uintptr_t*>mutex)[0]
    try:
        pMutex = <Mutex?>mutexes[key]
    except KeyError:
        return libc.errno.ESRCH
    if pMutex.attr.robustness:
        return 0
    else:
        return libc.errno.EINVAL

cdef public int pthread_mutex_consistent_np(pthread_mutex_t *mutex):
    return pthread_mutex_consistent(mutex)

###########################################################################
#                Functions for handling read-write locks.                 #
###########################################################################

cdef class RwlockAttr:

    cdef int pshared
    cdef int pref

    cdef int init(self, const pthread_rwlockattr_t *attr):
        if NULL == attr:
            return self.set_default()
        else:
            return self.set(attr)

    cdef int set_default(self):
        cdef pthread_rwlockattr_t attr
        cdef int fail = pthread_rwlockattr_init(&attr)
        if fail:
            return fail
        return self.set(&attr)

    cdef int set(self, const pthread_rwlockattr_t *attr):
        cdef int fail = pthread_rwlockattr_getpshared(attr, &self.pshared)
        if fail:
            return fail
        fail = pthread_rwlockattr_getkind_np(attr, &self.pref)
        if fail:
            return fail
        return 0

    cdef int get(self, pthread_rwlockattr_t *attr):
        cdef int fail = pthread_rwlockattr_setpshared(attr, self.pshared)
        if fail:
            return fail
        fail = pthread_rwlockattr_setkind_np(attr, self.pref)
        if fail:
            return fail
        return 0

cdef class Rwlock_PREFER_READER:

    cdef RwlockAttr attr
    cdef int    balance
    cdef object lock
    cdef object ready
    cdef dict   owners
    cdef object __weakref__

    def __init__(self):
        self.balance = 0
        self.lock    = gevent.lock.Semaphore(1)
        self.ready   = gevent.event.Event()
        self.owners  = {}

    cdef int rd_acquire(self, blocking=True, timeout=None):
        g   = gevent.getcurrent()
        key = <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g
        if key in self.owners:
            return EDEADLK
        if self.balance > 0:
            self.balance += 1
            self.owners[key] = 0
            return 0
        elif 0 == self.balance:
            self.balance = -1
            rc = self.lock.acquire(blocking, timeout)
            if rc:
                self.balance = abs(self.balance)
                self.ready.set()
                self.owners[key] = 0
                return 0
            else:
                if timeout is None:
                    return libc.errno.EBUSY
                else:
                    return libc.errno.ETIMEDOUT
        else:
            self.balance -= 1
            rc = self.ready.wait(timeout)
            if rc:
                self.owners[key] = 0
                return 0
            else:
                return libc.errno.ETIMEDOUT

    cdef int wr_acquire(self, blocking, timeout):
        g   = gevent.getcurrent()
        key = <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g
        if key in self.owners:
            return EDEADLK
        rc = self.lock.acquire(blocking, timeout)
        if rc:
            self.owner[key] = 1
            return 0
        else:
            if timeout is None:
                return libc.errno.EBUSY
            else:
                return libc.errno.ETIMEDOUT

    cdef int release(self):
        g   = gevent.getcurrent()
        key = <unsigned long><libc.stdint.uintptr_t><PyGreenlet*>g
        is_writer = self.owner.get(key)
        if key is None:
            return libc.errno.EPERM
        if key:
            self.lock.release()
            del self.owner[key]
            return 0
        else:
            self.balance -= 1
            if 0 == self.balance:
                self.ready.clear()
                self.lock.release()
            del self.owner[key]
            return 0

# Initialize read-write lock RWLOCK using attributes ATTR, or use
# the default values if later is NULL.
cdef public int pthread_rwlock_init \
    (
        pthread_rwlock_t *rwlock,
        const pthread_rwlockattr_t *attr
    ):
    pAttr = RwlockAttr()
    cdef int fail = pAttr.init(attr)
    if fail:
        return fail
    pRwlock = Rwlock_PREFER_READER()
    pRwlock.attr = pAttr
    key = \
              <unsigned long>     \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pRwlock
    rwlocks[key] = pRwlock
    (<libc.stdint.uintptr_t*>rwlock)[0] = \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pRwlock
    return 0

# Destroy read-write lock RWLOCK.
cdef public int pthread_rwlock_destroy(pthread_rwlock_t *rwlock):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        del rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    else:
        return 0

# Acquire read lock for RWLOCK.
cdef public int pthread_rwlock_rdlock(pthread_rwlock_t *rwlock):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        pRwlock = rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    return pRwlock.rd_acquire(True, None)

# Try to acquire read lock for RWLOCK.
cdef public int pthread_rwlock_tryrdlock(pthread_rwlock_t *rwlock):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        pRwlock = rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    return pRwlock.rd_acquire(False, None)

# Try to acquire read lock for RWLOCK or return after specfied time.
cdef public int pthread_rwlock_timedrdlock \
    (
        pthread_rwlock_t *rwlock,
        const posix.time.timespec *abstime
    ):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        pRwlock = rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    return pRwlock.rd_acquire(True, <long>abstime.tv_sec)

# Acquire write lock for RWLOCK.
cdef public int pthread_rwlock_wrlock(pthread_rwlock_t *rwlock):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        pRwlock = rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    return pRwlock.wr_acquire(True, None)

# Try to acquire write lock for RWLOCK.
cdef public int pthread_rwlock_trywrlock(pthread_rwlock_t *rwlock):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        pRwlock = rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    return pRwlock.wr_acquire(False, None)

# Try to acquire write lock for RWLOCK or return after specfied time.
cdef public int pthread_rwlock_timedwrlock \
    (
        pthread_rwlock_t *rwlock,
        const posix.time.timespec *abstime
    ):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        pRwlock = rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    return pRwlock.wr_acquire(True, <long>abstime.tv_sec)

# Unlock RWLOCK.
cdef public int pthread_rwlock_unlock(pthread_rwlock_t *rwlock):
    key = <unsigned long>(<libc.stdint.uintptr_t*>rwlock)[0]
    try:
        pRwlock = rwlocks[key]
    except KeyError:
        return libc.errno.ESRCH
    return pRwlock.release()

###########################################################################
#              Functions for handling conditional variables.              #
###########################################################################

cdef class CondAttr:

    cdef int pshared
    cdef __clockid_t clock_id

    cdef int init(self, const pthread_condattr_t *attr):
        if NULL == attr:
            return self.set_default()
        else:
            return self.set(attr)

    cdef int set_default(self):
        cdef pthread_condattr_t attr
        cdef int fail = pthread_condattr_init(&attr)
        if fail:
            return fail
        return self.set(&attr)

    cdef int set(self, const pthread_condattr_t *attr):
        cdef int fail = pthread_condattr_getpshared(attr, &self.pshared)
        if fail:
            return fail
        fail = pthread_condattr_getclock(attr, &self.clock_id)
        if fail != 0:
            return fail
        return 0

    cdef int get(self, pthread_condattr_t *attr):
        cdef int fail = pthread_condattr_setpshared(attr, self.pshared)
        if fail:
            return fail
        fail = pthread_condattr_setclock(attr, self.clock_id)
        if fail:
            return fail
        return 0

cdef class Cond:

    cdef CondAttr attr
    cdef public object queue

    def __init__(self):
        self.queue = gevent.queue.Queue()

    cdef int init(self, CondAttr attr):
        self.attr = attr
        return 0

# Initialize condition variable COND using attributes ATTR, or use
# the default values if later is NULL.
cdef public int pthread_cond_init \
    (
        pthread_cond_t *cond,
        const pthread_condattr_t *cond_attr
    ):
    if not C10kPthread_initialized:
        (<libc.stdint.uintptr_t*>cond)[0] = 0
        return 0
    pAttr = CondAttr()
    cdef int fail = pAttr.init(cond_attr)
    if fail:
        return fail
    pCond = Cond()
    pCond.attr = pAttr
    key = \
              <unsigned long>     \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pCond
    conds[key] = pCond
    (<libc.stdint.uintptr_t*>cond)[0] = \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pCond
    return 0

# Destroy condition variable COND.
cdef public int pthread_cond_destroy(pthread_cond_t *cond):
    key = <unsigned long>(<libc.stdint.uintptr_t*>cond)[0]
    try:
        del conds[key]
    except KeyError:
        return libc.errno.ESRCH
    else:
        return 0

# Wake up one thread waiting for condition variable COND.
cdef public int pthread_cond_signal(pthread_cond_t *cond):
    if 0 == (<libc.stdint.uintptr_t*>cond)[0]:
        return 0
    key = <unsigned long>(<libc.stdint.uintptr_t*>cond)[0]
    try:
        pCond = conds[key]
    except KeyError:
        return libc.errno.ESRCH
    queue = pCond.queue
    if len(queue.getters) > 0:
        queue.put(None)
        return 0
    else:
        return 0

# Wake up all threads waiting for condition variables COND.
cdef public int pthread_cond_broadcast(pthread_cond_t *cond):
    key = <unsigned long>(<libc.stdint.uintptr_t*>cond)[0]
    try:
        pCond = conds[key]
    except KeyError:
        return libc.errno.ESRCH
    queue = pCond.queue
    if len(queue.getters) > 0:
        pCond.queue = gevent.queue.Queue()
        while len(queue.getters) > 0:
            queue.put(None)
        return 0
    else:
        return 0

# Wait for condition variable COND to be signaled or broadcast.
# MUTEX is assumed to be locked before.
#
# This function is a cancellation point and therefore not marked with
# __THROW.
cdef public int pthread_cond_wait \
    (
        pthread_cond_t *cond,
        pthread_mutex_t *mutex
    ):
    if 0 == (<libc.stdint.uintptr_t*>cond)[0]:
        return 0
    key = <unsigned long>(<libc.stdint.uintptr_t*>cond)[0]
    try:
        pCond = conds[key]
    except KeyError:
        return libc.errno.ESRCH
    pCond.queue.get(block=True)
    return 0

# Wait for condition variable COND to be signaled or broadcast until
# ABSTIME.  MUTEX is assumed to be locked before.  ABSTIME is an
# absolute time specification; zero is the beginning of the epoch
# (00:00:00 GMT, January 1, 1970).
#
# This function is a cancellation point and therefore not marked with
# __THROW.
cdef public int pthread_cond_timedwait \
    (
        pthread_cond_t *cond,
        pthread_mutex_t *mutex,
        const posix.time.timespec *abstime
    ):
    key = <unsigned long>(<libc.stdint.uintptr_t*>cond)[0]
    try:
        pCond = conds[key]
    except KeyError:
        return libc.errno.ESRCH
    pCond.queue.get(block=True, timeout=<long>abstime.tv_sec)
    return 0

# TODO
###########################################################################
#                     Functions to handle spinlocks.                      #
###########################################################################
'''
# Initialize the spinlock LOCK.  If PSHARED is nonzero the spinlock can
# be shared between different processes.
cdef public int pthread_spin_init(pthread_spinlock_t *lock, int pshared):
    return 0

# Destroy the spinlock LOCK.
cdef public int pthread_spin_destroy(pthread_spinlock_t *lock):
    return 0

# Wait until spinlock LOCK is retrieved.
cdef public int pthread_spin_lock(pthread_spinlock_t *lock):
    return 0

# Try to lock spinlock LOCK.
cdef public int pthread_spin_trylock(pthread_spinlock_t *lock):
    return 0

# Release spinlock LOCK.
cdef public int pthread_spin_unlock(pthread_spinlock_t *lock):
    return 0
'''
# TODO
###########################################################################
#                      Functions to handle barriers.                      #
###########################################################################
'''
cdef class BarrierAttr:

    cdef int pshared

    cdef int init(self, const pthread_barrierattr_t *attr):
        if NULL == attr:
            return self.set_default()
        else:
            return self.set(attr)

    cdef int set_default(self):
        cdef pthread_barrierattr_t attr
        cdef int fail = pthread_barrierattr_init(&attr)
        if fail:
            return fail
        return self.set(&attr)

    cdef int set(self, const pthread_barrierattr_t *attr):
        return pthread_barrierattr_getpshared(attr, &self.pshared)

    cdef int get(self, pthread_barrierattr_t *attr):
        return pthread_barrierattr_setpshared(attr, self.pshared)

cdef class Barrier:

    cdef BarrierAttr attr

    cdef int init(self, BarrierAttr attr):
        self.attr = attr
        return 0

# Initialize BARRIER with the attributes in ATTR.  The barrier is
# opened when COUNT waiters arrived.
cdef public int pthread_barrier_init \
    (
        pthread_barrier_t *barrier,
        const pthread_barrierattr_t *attr,
        unsigned int count
    ):
    return 0

# Destroy a previously dynamically initialized barrier BARRIER.
cdef public int pthread_barrier_destroy(pthread_barrier_t *barrier):
    return 0

# Wait on barrier BARRIER.
cdef public int pthread_barrier_wait(pthread_barrier_t *barrier):
    return 0
'''
###########################################################################
#              Functions for handling thread-specific data.               #
###########################################################################

cdef class Key:

    cdef void *specific
    cdef (void (*) (void *) nogil) destr_function

    def __dealloc__(self):
        if self.specific != NULL and self.destr_function != NULL:
            self.destr_function(self.specific)

# Create a key value identifying a location in the thread-specific
# data area.  Each thread maintains a distinct thread-specific data
# area.  DESTR_FUNCTION, if non-NULL, is called with the value
# associated to that key when the key is destroyed.
# DESTR_FUNCTION is not called if the value associated is NULL when
# the key is destroyed.
cdef public int pthread_key_create \
    (
        pthread_key_t *key,
        void (*destr_function) (void *) nogil
    ):
    global key_limbo_specific
    if not C10kPthread_initialized:
        key_limbo_specific = NULL
        key[0] = key_limbo
        return 0
    if LOCAL_KEY not in local.__dict__:
        local.__dict__[LOCAL_KEY] = {}
    pKey = Key()
    pKey.specific = NULL
    pKey.destr_function = destr_function
    id_ = \
              <unsigned long>     \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pKey
    local.__dict__[LOCAL_KEY][id_] = pKey
    key[0] = \
              <pthread_key_t>     \
          <libc.stdint.uintptr_t> \
        <cpython.object.PyObject*>pKey
    return 0

# Destroy KEY.
cdef public int pthread_key_delete(pthread_key_t key):
    if LOCAL_KEY not in local.__dict__:
        return libc.errno.ESRCH
    id_ = <unsigned long><libc.stdint.uintptr_t>key
    try:
        del local.__dict__[id_]
    except KeyError:
        return libc.errno.ESRCH
    return 0

# Return current value of the thread-specific data slot identified by KEY.
cdef public void *pthread_getspecific(pthread_key_t key):
    if key == key_limbo:
        return key_limbo_specific
    if LOCAL_KEY not in local.__dict__:
        return NULL
    id_ = <unsigned long><libc.stdint.uintptr_t>key
    try:
        pKey = <Key?>local.__dict__[id_]
    except KeyError:
        return NULL
    return pKey.specific

# Store POINTER in the thread-specific data slot identified by KEY.
cdef public int pthread_setspecific \
    (
        pthread_key_t key,
        const void *pointer
    ):
    global key_limbo_specific
    if key == key_limbo:
        key_limbo_specific = pointer
        return 0
    if LOCAL_KEY not in local.__dict__:
        return libc.errno.ESRCH
    id_ = <unsigned long><libc.stdint.uintptr_t>key
    try:
        pKey = <Key?>local.__dict__[id_]
    except KeyError:
        return libc.errno.ESRCH
    pKey.specific = pointer
    return 0

# TODO
###########################################################################
# Install handlers to be called when a new process is created with FORK.  #
# The PREPARE handler is called in the parent process just before         #
# performing FORK. The PARENT handler is called in the parent process     #
# just after FORK.                                                        #
# The CHILD handler is called in the child process.  Each of the three    #
# handlers can be NULL, meaning that no handler needs to be called at     #
# that point.                                                             #
# PTHREAD_ATFORK can be called several times, in which case the PREPARE   #
# handlers are called in LIFO order (last added with PTHREAD_ATFORK,      #
# first called before FORK), and the PARENT and CHILD handlers are called #
# in FIFO (first added, first called).                                    #
###########################################################################
'''
cdef public posix.types.pid_t pthread_atfork \
    (
        void (*prepare) (),
        void (*parent) (),
        void (*child) ()
    ):
    return 0
'''
