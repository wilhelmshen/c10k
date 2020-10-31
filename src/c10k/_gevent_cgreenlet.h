#ifndef __GEVENT_CGREENLET_H
#define __GEVENT_CGREENLET_H

#include <greenlet/greenlet.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _c10k_gevent_greenlet {
	PyGreenlet __pyx_base;
	void     * __pyx_vtab;
	PyObject *value;
	PyObject *args;
	PyObject *kwargs;
	PyObject *spawning_greenlet;
	PyObject *spawning_stack;
	PyObject *spawn_tree_locals;
	PyObject *_links;
	PyObject *_exc_info;
	PyObject *_notifier;
	PyObject *_start_event;
	PyObject *_formatted_info;
	PyObject *_ident;
} PyC10kGeventGreenlet;

#ifdef __cplusplus
}
#endif
#endif /* !__GEVENT_CGREENLET */
