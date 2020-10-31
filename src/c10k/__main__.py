import sys

sys.dont_write_bytecode = True

import argparse
import copy
import os
import os.path
import subprocess
import sysconfig

from . import   __doc__   as package__doc__
from . import __version__

def main(**kwargs):
    program, args, parser = parse(**kwargs)
    sys.exit(run(program, args))

def run(program, args):
    bin_dir = os.path.abspath(os.path.dirname(sys.argv[0]))
    lib_dir = \
        os.path.abspath(
            os.path.join(
                os.path.dirname(__file__),
                os.path.pardir
            )
        )
    pyx_ext_suffix = sysconfig.get_config_var('EXT_SUFFIX')
    lib_ext_suffix = os.path.splitext(pyx_ext_suffix)[1]
    for libpython_so in sysconfig.get_config_var('LDLIBRARY').split():
        if libpython_so.startswith('libpython3.') and \
           libpython_so.endswith(lib_ext_suffix):
            break
    else:
        raise FileNotFoundError(2, 'cannot find shared object file '
                                   'libpython3.*'+lib_ext_suffix)
    lib_path       = os.path.abspath(os.path.dirname(__file__))
    libc10k_so     = os.path.join(lib_path,   'libc10k'  +lib_ext_suffix)
    C10kPthread_so = os.path.join(lib_path, 'C10kPthread'+pyx_ext_suffix)
    libs = [libpython_so, C10kPthread_so, libc10k_so]
    platform = sys.platform.lower()
    if 'linux' in platform:
        if 'LD_PRELOAD' in os.environ:
            libs = set(os.environ['LD_PRELOAD'].split() + libs)
        os.environ['LD_PRELOAD'] = ' '.join(libs)
    elif 'darwin' == platform:
        if 'DYLD_INSERT_LIBRARIES' in os.environ:
            libs = set(os.environ['DYLD_INSERT_LIBRARIES'].split() + libs)
        os.environ['DYLD_INSERT_LIBRARIES'] = ' '.join(libs)
        os.environ['DYLD_FORCE_FLAT_NAMESPACE'] = 1
    else:
        raise NotImplementedError(f'the platform "{sys.platform}" '
                                    'is not currently supported')
    if 'PATH' in os.environ:
        os.environ['PATH'] = bin_dir + ':' + os.environ['PATH']
    else:
        os.environ['PATH'] = bin_dir
    try:
        p = subprocess.Popen([program] + args)
    except Exception as err:
        print (err, file=sys.stderr)
        return getattr(err, 'errno', 256)
    p.communicate()
    return p.returncode

def parse(**kwargs):
    defaults  = copy.copy(kwargs)
    arguments = defaults.pop('arguments', None)
    if arguments is None:
        arguments = sys.argv[1:]
    parser    = ParserFactory(**defaults)
    args      = parser.parse_args(arguments[:1])
    return (args.program, arguments[1:], parser)

def ParserFactory(**kwargs):
    parser = \
        argparse.ArgumentParser(
                description=package__doc__,
            formatter_class=argparse.RawDescriptionHelpFormatter
        )
    parser.add_argument(
                'program',
        metavar='program',
           type=str,
           help='program to be executed.'
    )
    parser.add_argument(
                'args',
        metavar='arg',
          nargs='*',
           help='program arguments.'
    )
    return parser
