#!/usr/bin/make

CYTHON := cython3
PYTHON := python3

define PY_CONFIG_VAR_CC
import distutils.sysconfig; \
print (distutils.sysconfig.get_config_var('CC'))
endef
CC := $(shell $(PYTHON) -c "$(PY_CONFIG_VAR_CC)")

define PY_CONFIG_VAR_PYX_EXT_SUFFIX
import distutils.sysconfig; print (\
distutils.sysconfig.get_config_var('EXT_SUFFIX') or '.so')
endef
PYX_EXT_SUFFIX := $(shell $(PYTHON) -c "$(PY_CONFIG_VAR_PYX_EXT_SUFFIX)")

define PY_CONFIG_VAR_LIB_EXT_SUFFIX
import distutils.sysconfig; import os.path; print (os.path.splitext(\
distutils.sysconfig.get_config_var('EXT_SUFFIX') or '.so')[1])
endef
LIB_EXT_SUFFIX := $(shell $(PYTHON) -c "$(PY_CONFIG_VAR_LIB_EXT_SUFFIX)")

PYX_SOURCES   := $(wildcard *.pyx)
PYX_C_SOURCES := $(PYX_SOURCES:.pyx=.c)
PYX_C_HEADERS := $(PYX_SOURCES:.pyx=.h)
PYX_MODULES   := $(PYX_SOURCES:.pyx=$(PYX_EXT_SUFFIX))
LIB_MODULES   := libc10k$(LIB_EXT_SUFFIX)
MODULES       := $(PYX_MODULES) $(LIB_MODULES)

all: $(MODULES)

%$(PYX_EXT_SUFFIX): %.c %.setup
	$(PYTHON) $(patsubst %.c,%,$<).setup build_ext --inplace

%$(LIB_EXT_SUFFIX): %.c %.setup
	$(PYTHON) $(patsubst %.c,%,$<).setup build_ext --inplace

%.c: %.pyx
	$(CYTHON) --embed -I. -IIncludes $<

clean:
	rm -rf        build      \
		   $(MODULES)    \
		$(PYX_C_SOURCES) \
		$(PYX_C_HEADERS) \
		   __pycache__
	find . -name '*.pyc' -exec rm {} \;
	find . -name '__pycache__' -exec rm -d {} \;

.PRECIOUS: $(SOURCES)

.PHONY: all clean
