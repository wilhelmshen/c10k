cdef extern from '<pthread.h>':

    ctypedef struct pthread_t:
        pass

    ctypedef struct pthread_attr_t:
        pass

    ctypedef struct pthread_once_t:
        pass

    ctypedef struct pthread_mutex_t:
        pass

    ctypedef struct pthread_mutexattr_t:
        pass

    ctypedef struct pthread_rwlock_t:
        pass

    ctypedef struct pthread_rwlockattr_t:
        pass

    ctypedef struct pthread_cond_t:
        pass

    ctypedef struct pthread_condattr_t:
        pass

    ctypedef struct pthread_spinlock_t:
        pass

    ctypedef struct pthread_barrier_t:
        pass

    ctypedef struct pthread_barrierattr_t:
        pass

    ctypedef struct pthread_key_t:
        pass

    struct sched_param:
        int sched_priority

    ctypedef struct cpu_set_t:
        pass

    ctypedef struct __clockid_t:
        pass

    enum:
        # Scheduling algorithms.
        SCHED_OTHER,         # 0
        SCHED_FIFO,          # 1
        SCHED_RR,            # 2
        SCHED_BATCH,         # 3
        SCHED_ISO,           # 4
        SCHED_IDLE,          # 5
        SCHED_DEADLINE,      # 6
        SCHED_RESET_ON_FORK  # 0x40000000

    enum:
        # Detach state.
        PTHREAD_CREATE_JOINABLE,
        PTHREAD_CREATE_DETACHED,
        # Mutex types.
        PTHREAD_MUTEX_TIMED_NP,
        PTHREAD_MUTEX_RECURSIVE_NP,
        PTHREAD_MUTEX_ERRORCHECK_NP,
        PTHREAD_MUTEX_ADAPTIVE_NP,
        PTHREAD_MUTEX_NORMAL,       # = PTHREAD_MUTEX_TIMED_NP
        PTHREAD_MUTEX_RECURSIVE,    # = PTHREAD_MUTEX_RECURSIVE_NP
        PTHREAD_MUTEX_ERRORCHECK,   # = PTHREAD_MUTEX_ERRORCHECK_NP
        PTHREAD_MUTEX_DEFAULT,      # = PTHREAD_MUTEX_NORMAL
        PTHREAD_MUTEX_FAST_NP,      # = PTHREAD_MUTEX_TIMED_NP
        # Robust mutex or not flags.
        PTHREAD_MUTEX_STALLED,
        PTHREAD_MUTEX_STALLED_NP,   # = PTHREAD_MUTEX_STALLED
        PTHREAD_MUTEX_ROBUST,
        PTHREAD_MUTEX_ROBUST_NP,    # = PTHREAD_MUTEX_ROBUST
        # Mutex protocols.
        PTHREAD_PRIO_NONE,
        PTHREAD_PRIO_INHERIT,
        PTHREAD_PRIO_PROTECT,
        # Read-write lock types.
        PTHREAD_RWLOCK_PREFER_READER_NP,
        PTHREAD_RWLOCK_PREFER_WRITER_NP,
        PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP,
        PTHREAD_RWLOCK_DEFAULT_NP,  # = PTHREAD_RWLOCK_PREFER_READER_NP
        # Scheduler inheritance.
        PTHREAD_INHERIT_SCHED,
        PTHREAD_EXPLICIT_SCHED,
        # Scope handling.
        PTHREAD_SCOPE_SYSTEM,
        PTHREAD_SCOPE_PROCESS,
        # Process shared or private flag.
        PTHREAD_PROCESS_PRIVATE,
        PTHREAD_PROCESS_SHARED,
        # Cancellation
        PTHREAD_CANCEL_ENABLE,
        PTHREAD_CANCEL_DISABLE
        PTHREAD_CANCEL_DEFERRED,
        PTHREAD_CANCEL_ASYNCHRONOUS

    # Single execution handling.
    pthread_once_t PTHREAD_ONCE_INIT

    void *PTHREAD_CANCELED  # ((void *) -1)

    ###################################################################
    #                    Thread attribute handling.                   #
    ###################################################################

    # Initialize thread attribute *ATTR with default attributes
    # (detachstate is PTHREAD_JOINABLE, scheduling policy is SCHED_OTHER,
    # no user-provided stack).
    int pthread_attr_init (pthread_attr_t *) nogil
    # Destroy thread attribute *ATTR.
    int pthread_attr_destroy (pthread_attr_t *) nogil
    # Get detach state attribute.
    int pthread_attr_getdetachstate (const pthread_attr_t *, int *) nogil
    # Set detach state attribute.
    int pthread_attr_setdetachstate (pthread_attr_t *, int) nogil
    # Get the size of the guard area created for stack overflow protection.
    int pthread_attr_getguardsize (const pthread_attr_t *, size_t *) nogil
    # Set the size of the guard area created for stack overflow protection.
    int pthread_attr_setguardsize (pthread_attr_t *, size_t) nogil
    # Return in *PARAM the scheduling parameters of *ATTR.
    int pthread_attr_getschedparam (const pthread_attr_t *,
                                    sched_param *) nogil
    # Set scheduling parameters (priority, etc) in *ATTR according to
    # PARAM.
    int pthread_attr_setschedparam (pthread_attr_t *,
                                    const sched_param *) nogil
    # Return in *POLICY the scheduling policy of *ATTR.
    int pthread_attr_getschedpolicy (const pthread_attr_t *, int *) nogil
    # Set scheduling policy in *ATTR according to POLICY.
    int pthread_attr_setschedpolicy (pthread_attr_t *, int) nogil
    # Return in *INHERIT the scheduling inheritance mode of *ATTR.
    int pthread_attr_getinheritsched (const pthread_attr_t *, int *) nogil
    # Set scheduling inheritance mode in *ATTR according to INHERIT.
    int pthread_attr_setinheritsched (pthread_attr_t *, int) nogil
    # Return in *SCOPE the scheduling contention scope of *ATTR.
    int pthread_attr_getscope (const pthread_attr_t *, int *) nogil
    # Set scheduling contention scope in *ATTR according to SCOPE.
    int pthread_attr_setscope (pthread_attr_t *, int) nogil
    # Return the previously set address for the stack.
    int pthread_attr_getstackaddr (const pthread_attr_t *, void **) nogil
    # Set the starting address of the stack of the thread to be created.
    # Depending on whether the stack grows up or down the value must either
    # be higher or lower than all the address in the memory block.  The
    # minimal size of the block must be PTHREAD_STACK_MIN.
    int pthread_attr_setstackaddr (pthread_attr_t *, void *) nogil
    # Return the currently used minimal stack size.
    int pthread_attr_getstacksize (const pthread_attr_t *, size_t *) nogil
    # Add information about the minimum stack size needed for the thread
    # to be started.  This size must never be less than PTHREAD_STACK_MIN
    # and must also not exceed the system limits.
    int pthread_attr_setstacksize (pthread_attr_t *, size_t) nogil
    # Return the previously set address for the stack.
    int pthread_attr_getstack (const pthread_attr_t *, void **,
                               size_t *) nogil
    # The following two interfaces are intended to replace the last two.
    # They require setting the address as well as the size since only
    # setting the address will make the implementation on some
    # architectures impossible.
    int pthread_attr_setstack (pthread_attr_t *, void *, size_t) nogil
    # Thread created with attribute ATTR will be limited to run only on
    # the processors represented in CPUSET.
    int pthread_attr_setaffinity_np (pthread_attr_t *, size_t,
                                     const cpu_set_t *) nogil
    # Get bit set in CPUSET representing the processors threads created
    # with ATTR can run on.
    int pthread_attr_getaffinity_np (const pthread_attr_t *, size_t,
                                     cpu_set_t *) nogil
    # Get the default attributes used by pthread_create in this process.
    int pthread_getattr_default_np (pthread_attr_t *) nogil
    # Set the default attributes to be used by pthread_create in this
    # process.
    int pthread_setattr_default_np (const pthread_attr_t *) nogil

    #######################################################################
    #              Functions for handling mutex attributes.               #
    #######################################################################

    # Initialize mutex attribute object ATTR with default attributes
    # (kind is PTHREAD_MUTEX_TIMED_NP).
    int pthread_mutexattr_init (pthread_mutexattr_t *) nogil
    # Destroy mutex attribute object ATTR.
    int pthread_mutexattr_destroy (pthread_mutexattr_t *) nogil
    # Get the process-shared flag of the mutex attribute ATTR.
    int pthread_mutexattr_getpshared \
        (
            const pthread_mutexattr_t *,
            int *
        ) nogil
    # Set the process-shared flag of the mutex attribute ATTR.
    int pthread_mutexattr_setpshared (pthread_mutexattr_t *, int) nogil
    # Return in *KIND the mutex kind attribute in *ATTR.
    int pthread_mutexattr_gettype \
        (
            const pthread_mutexattr_t *,
            int *
        ) nogil
    # Set the mutex kind attribute in *ATTR to KIND (
    # either PTHREAD_MUTEX_NORMAL,
    # PTHREAD_MUTEX_RECURSIVE, PTHREAD_MUTEX_ERRORCHECK, or
    # PTHREAD_MUTEX_DEFAULT).
    int pthread_mutexattr_settype (pthread_mutexattr_t *, int) nogil
    # Return in *PROTOCOL the mutex protocol attribute in *ATTR.
    int pthread_mutexattr_getprotocol \
        (
            const pthread_mutexattr_t *,
            int *
        ) nogil
    # Set the mutex protocol attribute in *ATTR to PROTOCOL (either
    # PTHREAD_PRIO_NONE, PTHREAD_PRIO_INHERIT, or PTHREAD_PRIO_PROTECT).
    int pthread_mutexattr_setprotocol (pthread_mutexattr_t *, int) nogil
    # Return in *PRIOCEILING the mutex prioceiling attribute in *ATTR.
    int pthread_mutexattr_getprioceiling \
        (
            const pthread_mutexattr_t *,
            int *
        ) nogil
    # Set the mutex prioceiling attribute in *ATTR to PRIOCEILING.
    int pthread_mutexattr_setprioceiling (pthread_mutexattr_t *, int) nogil
    # Get the robustness flag of the mutex attribute ATTR.
    int pthread_mutexattr_getrobust \
        (
            const pthread_mutexattr_t *,
            int *
        ) nogil
    int pthread_mutexattr_getrobust_np \
        (
            const pthread_mutexattr_t *,
            int *
        ) nogil
    # Set the robustness flag of the mutex attribute ATTR.
    int pthread_mutexattr_setrobust    (pthread_mutexattr_t *, int) nogil
    int pthread_mutexattr_setrobust_np (pthread_mutexattr_t *, int) nogil

    #######################################################################
    #         Functions for handling read-write lock attributes.          #
    #######################################################################

    # Initialize attribute object ATTR with default values.
    int pthread_rwlockattr_init (pthread_rwlockattr_t *) nogil
    # Destroy attribute object ATTR.
    int pthread_rwlockattr_destroy (pthread_rwlockattr_t *) nogil
    # Return current setting of process-shared attribute of ATTR in
    # PSHARED.
    int pthread_rwlockattr_getpshared \
        (
            const pthread_rwlockattr_t *,
            int *
        ) nogil
    # Set process-shared attribute of ATTR to PSHARED.
    int pthread_rwlockattr_setpshared (pthread_rwlockattr_t *, int) nogil
    # Return current setting of reader/writer preference.
    int pthread_rwlockattr_getkind_np \
        (
            const pthread_rwlockattr_t *,
            int *
        ) nogil
    # Set reader/write preference.
    int pthread_rwlockattr_setkind_np (pthread_rwlockattr_t *, int) nogil

    #######################################################################
    #        Functions for handling condition variable attributes.        #
    #######################################################################

    # Initialize condition variable attribute ATTR.
    int pthread_condattr_init (pthread_condattr_t *) nogil
    # Destroy condition variable attribute ATTR.
    int pthread_condattr_destroy (pthread_condattr_t *) nogil
    # Get the process-shared flag of the condition variable attribute ATTR.
    int pthread_condattr_getpshared \
        (
            const pthread_condattr_t *,
            int *
        ) nogil

    # Set the process-shared flag of the condition variable attribute ATTR.
    int pthread_condattr_setpshared (pthread_condattr_t *, int) nogil
    # Get the clock selected for the condition variable attribute ATTR.
    int pthread_condattr_getclock \
        (
            const pthread_condattr_t *,
            __clockid_t *
        ) nogil
    # Set the clock selected for the condition variable attribute ATTR.
    int pthread_condattr_setclock (pthread_condattr_t *, __clockid_t) nogil

    # Initialize barrier attribute ATTR.
    int pthread_barrierattr_init (pthread_barrierattr_t *) nogil
    # Destroy previously dynamically initialized barrier attribute ATTR.
    int pthread_barrierattr_destroy (pthread_barrierattr_t *) nogil
    # Get the process-shared flag of the barrier attribute ATTR.
    int pthread_barrierattr_getpshared \
        (
            const pthread_barrierattr_t *,
            int *
        ) nogil
    # Set the process-shared flag of the barrier attribute ATTR.
    int pthread_barrierattr_setpshared (pthread_barrierattr_t *, int) nogil
