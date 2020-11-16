=========
C10K plan
=========

Introduction
------------

C10K is a coroutine-based alternative implementation of the posix thread.
It allows existing non-asynchronous programs, regardless of the programming
language they use, to become coroutine-based asynchronous programs without
any modifications, and makes it possible for programs to handle a large
number of clients at the same time.

At this moment C10K is still under heavy development.


Usage
-----

The **c10k** command can start a specified program that runs
asynchronously.

.. code-block:: console

    $ c10k ab -c 1000 -n 10000 http://example.com/

.. code-block:: console

    $ c10k bash
